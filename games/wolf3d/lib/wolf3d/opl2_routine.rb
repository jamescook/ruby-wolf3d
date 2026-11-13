# frozen_string_literal: true

module Wolf3D
  # OPL2::OPERATOR AS GAME CODE, for the data pack's routine: AdlibUnpacking plays the effects
  # through it and MusicUnpacking the music. Each method is Opl2::Operator's of the same name, step
  # for step, reading Opl2's tables and the clock's; Opl2 says what each step is and why. An operator
  # is an Operator, the routine's variables for what Opl2::Operator keeps in itself.
  #
  # This file is game code (VBlank.require_game_file): an `if` on a number the routine reads is a
  # branch in it.
  class Opl2Routine
    # One operator's registers and envelope, each field a variable of the routine's.
    Operator = Struct.new(:block, :fnum, :doubled_multiple, :key_scale_rate, :holds_sustain, :vibrato, :tremolo,
                          :level, :key_scale, :attack, :decay, :sustain, :release, :wave, :stage, :loss, :risen,
                          :phase, :step, :rise, :decay_fall, :release_fall, :scale_loss) do
      # The pitch the operator's channel is set to (#tune): its octave and its frequency number.
      game_variables :block, :fnum
      # The settings written to the chip's CHAR_REGISTER: tremolo and vibrato on or off, whether the
      # envelope holds at the sustain level while the key is down, whether the rates follow the key,
      # and the frequency multiple, kept doubled so the half setting stays whole.
      game_variables :tremolo, :vibrato, :holds_sustain, :key_scale_rate, :doubled_multiple
      # The settings written to SCALE_REGISTER, ATTACK_REGISTER, SUSTAIN_REGISTER and WAVE_REGISTER:
      # how quiet the operator is and how much quieter higher notes get, the envelope's four rates and
      # levels, and which of the four waves it plays.
      game_variables :level, :key_scale, :attack, :decay, :sustain, :release, :wave
      # Worked out from the pitch and the settings by #retune, so #step does not work them out each
      # sample: how far the phase moves a sample, how fast the attack rises, how fast decay and
      # release fall, and how much quieter the key makes the operator.
      game_variables :step, :rise, :decay_fall, :release_fall, :scale_loss
      # The envelope as it moves (#move_envelope): its stage, how quiet it is now, and how far the
      # attack has gone.
      game_variables :stage, :loss, :risen
      # Where the operator is in its wave.
      game_variables :phase
    end

    # +b+ is the routine's builder. +prefix+ names this chip's tables apart from any other's, and
    # +clock+ (Opl2.clock) is how often #step is called.
    def initialize(b, prefix, clock)
      @b = b
      @sine = @b.table(:"#{prefix}_sine", Opl2::SINE, width: :half)
      @gain = @b.table(:"#{prefix}_gain", Opl2::GAIN, width: :half)
      @fall = @b.table(:"#{prefix}_fall", clock.fall, width: :word)
      @rise = @b.table(:"#{prefix}_rise", clock.rise, width: :word)
      @attack_loss = @b.table(:"#{prefix}_attack_loss", Opl2::ATTACK_LOSS, width: :half)
      @doubled_multiples = @b.table(:"#{prefix}_doubled_multiple", Opl2::DOUBLED_MULTIPLES, width: :byte)
      @key_scale_loss = @b.table(:"#{prefix}_key_scale_loss", Opl2::KEY_SCALE_LOSS, width: :byte)
      @phase_ratio = clock.phase_ratio
    end

    # A new operator, every register nought.
    def operator = Operator.new(*Array.new(Operator.members.length, 0))

    # Opl2::Operator#initialize: every register nought and the key up.
    def reset(operator)
      operator.block = 0
      operator.fnum = 0

      operator.tremolo = 0
      operator.vibrato = 0
      operator.holds_sustain = 0
      operator.key_scale_rate = 0
      operator.doubled_multiple = Opl2::DOUBLED_MULTIPLES[0]

      operator.level = 0
      operator.key_scale = 0
      operator.attack = 0
      operator.decay = 0
      operator.sustain = 0
      operator.release = 0
      operator.wave = 0

      operator.step = 0
      operator.rise = 0
      operator.decay_fall = 0
      operator.release_fall = 0
      operator.scale_loss = 0

      operator.stage = Opl2::OFF
      operator.loss = Opl2::SILENT << Opl2::ENVELOPE_BITS
      operator.risen = 0

      operator.phase = 0
      retune(operator)
    end

    # A WRITE OF +value+ TO ONE OF THE OPERATOR'S FIVE REGISTERS, +kind+ being which (Opl2's
    # CHAR_REGISTER and the rest), either of them a number or one the routine read:
    # Opl2::Operator#char= and the four after it.
    def write_register(operator, kind, value)
      register = value
      if kind == Opl2::CHAR_REGISTER
        operator.tremolo = (register >> 7) & 1
        operator.vibrato = (register >> 6) & 1
        operator.holds_sustain = (register >> 5) & 1
        operator.key_scale_rate = (register >> 4) & 1
        operator.doubled_multiple = @doubled_multiples[register & 0x0f]
      elsif kind == Opl2::SCALE_REGISTER
        operator.key_scale = register >> 6
        operator.level = (register & 0x3f) * Opl2::LEVEL_STEPS
      elsif kind == Opl2::ATTACK_REGISTER
        operator.attack = register >> 4
        operator.decay = register & 0x0f
      elsif kind == Opl2::SUSTAIN_REGISTER
        operator.release = register & 0x0f
        sustain = register >> 4
        operator.sustain = (sustain * Opl2::SUSTAIN_STEPS) << Opl2::ENVELOPE_BITS
        operator.sustain = Opl2::LOWEST_SUSTAIN << Opl2::ENVELOPE_BITS if sustain == Opl2::LOWEST_SUSTAIN_LEVEL
      elsif kind == Opl2::WAVE_REGISTER
        operator.wave = register & 3
      end
      retune(operator)
    end

    # Opl2::Operator#tune.
    def tune(operator, block, fnum)
      operator.block = block
      operator.fnum = fnum
      retune(operator)
    end

    # Opl2::Operator#key_on.
    def key_on(operator)
      if operator.stage == Opl2::OFF || operator.stage == Opl2::RELEASE
        operator.risen = 0
        if operator.attack == Opl2::FASTEST_REGISTER
          operator.stage = Opl2::DECAY
          operator.loss = 0
        else
          operator.stage = Opl2::ATTACK
        end
      end
    end

    def key_off(operator)
      operator.stage = Opl2::RELEASE if operator.stage != Opl2::OFF
    end

    # Opl2::Operator#vibrate.
    def vibrate(operator, shape, shift)
      if operator.vibrato == 1
        fnum = operator.fnum
        operator.step = phase_step(operator, fnum + (((fnum >> 7) * shape) >> shift))
      end
    end

    # Opl2::Operator#quiet?.
    def quiet?(operator)
      operator.stage == Opl2::OFF || (operator.loss >> Opl2::ENVELOPE_BITS) + operator.level >= Opl2::QUIET
    end

    # ONE SAMPLE OF +operator+, bent by +bend+ of the sine's places and +tremor+ quieter where its
    # tremolo is on: Opl2::Operator#step.
    def step(operator, bend, tremor)
      half = Opl2::SINE_PLACES / 2
      move_envelope(operator)
      operator.phase = (operator.phase + operator.step) & Opl2::PHASE_MASK
      loss = (operator.loss >> Opl2::ENVELOPE_BITS) + operator.level + operator.scale_loss
      loss += tremor if operator.tremolo == 1
      loss = Opl2::SILENT if loss > Opl2::SILENT
      place = ((operator.phase >> Opl2::PHASE_FRACTION_BITS) + bend) & (Opl2::SINE_PLACES - 1)
      wave = 0
      if operator.wave == 0
        wave = @sine[place]
      elsif operator.wave == 1
        wave = @sine[place] if place < half
      elsif operator.wave == 2
        wave = @sine[place & (half - 1)]
      elsif (place & (half / 2)) == 0
        wave = @sine[place & (half - 1)]
      end
      (wave * @gain[loss]) >> Opl2::GAIN_BITS
    end

    private

    # Opl2::Operator#retune.
    def retune(operator)
      operator.step = phase_step(operator, operator.fnum)
      key_code = (operator.block * 2) | ((operator.fnum >> 9) & 1)
      offset = key_code >> 2
      offset = key_code if operator.key_scale_rate == 1
      operator.rise = @rise[rate(operator.attack, offset)]
      operator.decay_fall = @fall[rate(operator.decay, offset)]
      operator.release_fall = @fall[rate(operator.release, offset)]
      operator.scale_loss = scale_loss(operator)
    end

    # Opl2::Operator#phase_step.
    def phase_step(operator, fnum)
      ((((fnum << operator.block) * @phase_ratio) >> Opl2::PHASE_RATIO_BITS) * operator.doubled_multiple) >> 1
    end

    # The chip's rate for a register's setting, +offset+ from the key: Opl2::Operator#rate.
    def rate(setting, offset)
      rate = 0
      if setting > 0
        rate = (setting * 4) + offset
        rate = Opl2::RATES - 1 if rate > Opl2::RATES - 1
      end
      rate
    end

    # Opl2::Operator#scale_loss.
    def scale_loss(operator)
      key_scale = operator.key_scale
      cut = @key_scale_loss[operator.fnum >> 6] - (Opl2::KEY_SCALE_OCTAVE * (Opl2::TOP_BLOCK - operator.block))
      cut = 0 if cut < 0
      if key_scale == 0
        cut = 0
      elsif key_scale == 1
        cut >>= 1
      elsif key_scale == 2
        cut >>= 2
      end
      cut
    end

    # Opl2::Operator#move_envelope.
    def move_envelope(operator)
      silent = Opl2::SILENT << Opl2::ENVELOPE_BITS
      if operator.stage == Opl2::ATTACK
        rise(operator)
      elsif operator.stage == Opl2::DECAY
        fall_toward(operator, operator.sustain, operator.decay_fall)
        operator.stage = Opl2::SUSTAIN if operator.loss >= operator.sustain
      elsif operator.stage == Opl2::SUSTAIN
        if operator.holds_sustain == 0
          fall_toward(operator, silent, operator.release_fall)
          operator.stage = Opl2::OFF if operator.loss >= silent
        end
      elsif operator.stage == Opl2::RELEASE
        fall_toward(operator, silent, operator.release_fall)
        operator.stage = Opl2::OFF if operator.loss >= silent
      end
    end

    # Opl2::Operator#rise.
    def rise(operator)
      if operator.rise > 0
        operator.risen += operator.rise
        if operator.risen >= Opl2::ATTACK_FULL
          operator.loss = 0
          operator.stage = Opl2::DECAY
        else
          operator.loss = @attack_loss[operator.risen >> Opl2::ATTACK_PLACE_BITS] << Opl2::ENVELOPE_BITS
        end
      end
    end

    # One sample down toward +floor+ by +fall+; the caller asks whether the loss has got there
    # (Opl2::Operator#fallen_to?).
    def fall_toward(operator, floor, fall)
      operator.loss += fall if operator.loss < floor
    end
  end
end
