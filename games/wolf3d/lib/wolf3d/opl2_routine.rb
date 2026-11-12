# frozen_string_literal: true

module Wolf3D
  # OPL2::OPERATOR AS GAME CODE, for the data pack's routine: AdlibUnpacking plays the effects
  # through it and MusicUnpacking the music. Each method is Opl2::Operator's of the same name, step
  # for step, reading Opl2's tables and the clock's; Opl2 says what each step is and why. An operator
  # is a Hash of the routine's variables by name (#operator), what Opl2::Operator keeps in itself.
  #
  # This file is game code (VBlank.require_game_file): an `if` on a number the routine reads is a
  # branch in it.
  class Opl2Routine
    # +b+ is the routine's builder. +prefix+ names this chip's variables and tables apart from any
    # other's, and +clock+ (Opl2.clock) is how often #step is called.
    def initialize(b, prefix, clock)
      @b = b
      @prefix = prefix
      @sine = @b.table(:"#{prefix}_sine", Opl2::SINE, width: :half)
      @gain = @b.table(:"#{prefix}_gain", Opl2::GAIN, width: :half)
      @fall = @b.table(:"#{prefix}_fall", clock.fall, width: :word)
      @rise = @b.table(:"#{prefix}_rise", clock.rise, width: :word)
      @attack_loss = @b.table(:"#{prefix}_attack_loss", Opl2::ATTACK_LOSS, width: :half)
      @doubled_multiples = @b.table(:"#{prefix}_doubled_multiple", Opl2::DOUBLED_MULTIPLES, width: :byte)
      @key_scale_loss = @b.table(:"#{prefix}_key_scale_loss", Opl2::KEY_SCALE_LOSS, width: :byte)
      @phase_ratio = clock.phase_ratio
    end

    FIELDS = %i[block fnum doubled_multiple key_scale_rate holds_sustain vibrato tremolo level key_scale attack decay
                sustain release wave stage loss risen phase step rise decay_fall release_fall scale_loss].freeze

    # The variables of the operator called +name+.
    def operator(name) = FIELDS.to_h { |field| [field, var(:"#{name}_#{field}")] }

    # Opl2::Operator#initialize: every register nought and the key up.
    def reset(operator)
      (FIELDS - %i[doubled_multiple stage loss]).each { |field| operator[field].store!(0) }
      operator[:doubled_multiple].store!(Opl2::DOUBLED_MULTIPLES[0])
      operator[:stage].store!(Opl2::OFF)
      operator[:loss].store!(Opl2::SILENT << Opl2::ENVELOPE_BITS)
      retune(operator)
    end

    # A WRITE OF +value+ TO ONE OF THE OPERATOR'S FIVE REGISTERS, +kind+ being which (Opl2's
    # CHAR_REGISTER and the rest), either of them a number or one the routine read:
    # Opl2::Operator#char= and the four after it.
    def write_register(operator, kind, value)
      register = var(:register)
      which = var(:register_kind)
      register.store!(value)
      which.store!(kind)
      if which == Opl2::CHAR_REGISTER
        operator[:tremolo].store!((register >> 7) & 1)
        operator[:vibrato].store!((register >> 6) & 1)
        operator[:holds_sustain].store!((register >> 5) & 1)
        operator[:key_scale_rate].store!((register >> 4) & 1)
        operator[:doubled_multiple].store!(@doubled_multiples[register & 0x0f])
      elsif which == Opl2::SCALE_REGISTER
        operator[:key_scale].store!(register >> 6)
        operator[:level].store!((register & 0x3f) * Opl2::LEVEL_STEPS)
      elsif which == Opl2::ATTACK_REGISTER
        operator[:attack].store!(register >> 4)
        operator[:decay].store!(register & 0x0f)
      elsif which == Opl2::SUSTAIN_REGISTER
        operator[:release].store!(register & 0x0f)
        register.store!(register >> 4)
        operator[:sustain].store!((register * Opl2::SUSTAIN_STEPS) << Opl2::ENVELOPE_BITS)
        operator[:sustain].store!(Opl2::LOWEST_SUSTAIN << Opl2::ENVELOPE_BITS) if register == Opl2::LOWEST_SUSTAIN_LEVEL
      elsif which == Opl2::WAVE_REGISTER
        operator[:wave].store!(register & 3)
      end
      retune(operator)
    end

    # Opl2::Operator#tune.
    def tune(operator, block, fnum)
      operator[:block].store!(block)
      operator[:fnum].store!(fnum)
      retune(operator)
    end

    # Opl2::Operator#key_on.
    def key_on(operator)
      stage = operator[:stage]
      if (stage == Opl2::OFF) | (stage == Opl2::RELEASE)
        operator[:risen].store!(0)
        if operator[:attack] == Opl2::FASTEST_REGISTER
          stage.store!(Opl2::DECAY)
          operator[:loss].store!(0)
        else
          stage.store!(Opl2::ATTACK)
        end
      end
    end

    def key_off(operator)
      operator[:stage].store!(Opl2::RELEASE) if operator[:stage] != Opl2::OFF
    end

    # Opl2::Operator#vibrate.
    def vibrate(operator, shape, shift)
      if operator[:vibrato] == 1
        fnum = operator[:fnum]
        find_phase_step(operator, fnum + (((fnum >> 7) * shape) >> shift))
        operator[:step].store!(var(:phase_step))
      end
    end

    # Opl2::Operator#quiet?, into the variable it hands back.
    def quiet(operator)
      quiet = var(:quiet)
      quiet.store!(0)
      quiet.store!(1) if operator[:stage] == Opl2::OFF
      quiet.store!(1) if (operator[:loss] >> Opl2::ENVELOPE_BITS) + operator[:level] >= Opl2::QUIET
      quiet
    end

    # ONE SAMPLE OF +operator+, bent by +bend+ of the sine's places and +tremor+ quieter where its
    # tremolo is on, into the variable it hands back: Opl2::Operator#step.
    def step(operator, bend, tremor)
      place = var(:place)
      loss = var(:total_loss)
      wave = var(:wave_value)
      half = Opl2::SINE_PLACES / 2
      move_envelope(operator)
      operator[:phase].store!((operator[:phase] + operator[:step]) & Opl2::PHASE_MASK)
      loss.store!((operator[:loss] >> Opl2::ENVELOPE_BITS) + operator[:level] + operator[:scale_loss])
      loss.store!(loss + tremor) if operator[:tremolo] == 1
      loss.store!(Opl2::SILENT) if loss > Opl2::SILENT
      place.store!(((operator[:phase] >> Opl2::PHASE_FRACTION_BITS) + bend) & (Opl2::SINE_PLACES - 1))
      wave.store!(0)
      if operator[:wave] == 0
        wave.store!(@sine[place])
      elsif operator[:wave] == 1
        wave.store!(@sine[place]) if place < half
      elsif operator[:wave] == 2
        wave.store!(@sine[place & (half - 1)])
      elsif (place & (half / 2)) == 0
        wave.store!(@sine[place & (half - 1)])
      end
      out = var(:out)
      out.store!((wave * @gain[loss]) >> Opl2::GAIN_BITS)
      out
    end

    private

    # Opl2::Operator#retune.
    def retune(operator)
      key_code = var(:key_code)
      offset = var(:rate_offset)
      find_phase_step(operator, operator[:fnum])
      operator[:step].store!(var(:phase_step))
      key_code.store!((operator[:block] * 2) | ((operator[:fnum] >> 9) & 1))
      offset.store!(key_code >> 2)
      offset.store!(key_code) if operator[:key_scale_rate] == 1
      find_rate(operator[:attack])
      operator[:rise].store!(@rise[var(:rate)])
      find_rate(operator[:decay])
      operator[:decay_fall].store!(@fall[var(:rate)])
      find_rate(operator[:release])
      operator[:release_fall].store!(@fall[var(:rate)])
      find_scale_loss(operator)
    end

    # Opl2::Operator#phase_step, into phase_step.
    def find_phase_step(operator, fnum)
      var(:phase_step).store!(((((fnum << operator[:block]) * @phase_ratio) >> Opl2::PHASE_RATIO_BITS) *
                               operator[:doubled_multiple]) >> 1)
    end

    # The chip's rate for a register's setting, into rate: Opl2::Operator#rate.
    def find_rate(setting)
      rate = var(:rate)
      rate.store!(0)
      if setting > 0
        rate.store!((setting * 4) + var(:rate_offset))
        rate.store!(Opl2::RATES - 1) if rate > Opl2::RATES - 1
      end
    end

    # Opl2::Operator#scale_loss, into the operator's scale_loss.
    def find_scale_loss(operator)
      cut = var(:cut)
      key_scale = operator[:key_scale]
      cut.store!(@key_scale_loss[operator[:fnum] >> 6] -
                 (Opl2::KEY_SCALE_OCTAVE * (Opl2::TOP_BLOCK - operator[:block])))
      cut.store!(0) if cut < 0
      if key_scale == 0
        cut.store!(0)
      elsif key_scale == 1
        cut.store!(cut >> 1)
      elsif key_scale == 2
        cut.store!(cut >> 2)
      end
      operator[:scale_loss].store!(cut)
    end

    # Opl2::Operator#move_envelope.
    def move_envelope(operator)
      stage = operator[:stage]
      silent = Opl2::SILENT << Opl2::ENVELOPE_BITS
      if stage == Opl2::ATTACK
        rise(operator)
      elsif stage == Opl2::DECAY
        fall_toward(operator, operator[:sustain], operator[:decay_fall])
        stage.store!(Opl2::SUSTAIN) if var(:fallen) == 1
      elsif stage == Opl2::SUSTAIN
        if operator[:holds_sustain] == 0
          fall_toward(operator, silent, operator[:release_fall])
          stage.store!(Opl2::OFF) if var(:fallen) == 1
        end
      elsif stage == Opl2::RELEASE
        fall_toward(operator, silent, operator[:release_fall])
        stage.store!(Opl2::OFF) if var(:fallen) == 1
      end
    end

    # Opl2::Operator#rise.
    def rise(operator)
      risen = operator[:risen]
      if operator[:rise] > 0
        risen.store!(risen + operator[:rise])
        if risen >= Opl2::ATTACK_FULL
          operator[:loss].store!(0)
          operator[:stage].store!(Opl2::DECAY)
        else
          operator[:loss].store!(@attack_loss[risen >> Opl2::ATTACK_PLACE_BITS] << Opl2::ENVELOPE_BITS)
        end
      end
    end

    # One sample down toward +floor+ by +fall+, and into fallen whether the loss has got there:
    # Opl2::Operator#fallen_to?.
    def fall_toward(operator, floor, fall)
      fallen = var(:fallen)
      loss = operator[:loss]
      fallen.store!(1)
      if loss < floor
        loss.store!(loss + fall)
        fallen.store!(0) if loss < floor
      end
    end

    # A variable of the routine's, made the first time it is asked for.
    def var(name) = (@vars ||= {})[name] ||= @b.var(:"_#{@prefix}_#{name}", 0)
  end
end
