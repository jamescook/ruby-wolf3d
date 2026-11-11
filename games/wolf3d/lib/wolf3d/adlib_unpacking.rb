# frozen_string_literal: true

module Wolf3D
  # THE ADLIB EFFECTS, PLAYED THROUGH THE CHIP BY THE GAME ITSELF into the data pack (DataPack):
  # the knife, the pickups, the locked door, the tally's sounds, which Sounds makes into samples
  # for a trimmed build (AdlibSounds#recording).
  #
  # AUDIOT keeps each as a recipe for the AdLib card's chip (AdlibSounds says the layout), so this
  # is that chip, one channel of it, as game code: Opl2's arithmetic step for step, reading Opl2's
  # tables, and making the samples Opl2 makes. Opl2 says what each step is and why; a change to
  # one is a change to the other, and test_floor_unpacking holds them together.
  #
  # Each effect has a room of its own in adlib_samples, ROOM long, at EFFECT_AT, signed samples at
  # Opl2::RENDER_RATE with nought after it ends, and three numbers beside: its length in samples
  # (nought for an effect this copy lacks, or one that makes no sound), the frames its notes last
  # and its priority, which are AdlibSounds::Recording's.
  #
  # This file is game code (VBlank.require_game_file): an `if` on a number the routine reads is a
  # branch in it, and every count is a variable of the routine's (#routine_var).
  class AdlibUnpacking
    # The effects held, in Sounds' order, by their numbers in AUDIOT.
    # Asked for as the routine is built, since Sounds loads after this file.
    def self.numbers = Sounds::ADLIB_EFFECT_NUMBERS.values

    # EACH EFFECT'S ROOM, in samples: how long it runs through the chip, its fade included, counted
    # off the copies with Opl2 (the original's source does not say; both releases keep the same
    # effects). Spear keeps other effects and will want a list of its own.
    ROOM = [429, 2478, 5884, 4572, 3275, 8216, 3223, 7963, 8064, 6057, 11_107, 14_099, 16_038, 3078, 12_186,
            11_255, 8529, 8977, 9633].freeze
    EFFECTS = ROOM.length

    # Where each effect's room starts in adlib_samples.
    EFFECT_AT = ROOM.each_with_object([0]) { |room, starts| starts << (starts.last + room) }.first(EFFECTS).freeze

    # An operator's five registers are two bytes each in the instrument, the modulator's first.
    INSTRUMENT_AT = 6
    BLOCK_AT = 22

    # The slots the effects take, declared on +slots+ (the data pack's).
    def self.declare(slots)
      slots.samples :adlib_samples, count: ROOM.sum
      slots.numbers :adlib_length, count: EFFECTS, width: :half, signed: false
      slots.numbers :adlib_note_frames, count: EFFECTS, width: :half, signed: false
      slots.numbers :adlib_priority, count: EFFECTS, width: :half, signed: false
    end

    # +b+ is the routine's builder, and +copy+, +pack+ and +release+ what `fill_from_copy` hands it.
    def initialize(b, copy, pack, release)
      @b = b
      @copy = copy
      @pack = pack
      @release = release
    end

    def fill
      @head = @copy.file("AUDIOHED.#{@release}")
      @audio = @copy.file("AUDIOT.#{@release}")
      declare_tables
      @modulator = operator_vars(:modulator)
      @carrier = operator_vars(:carrier)
      @b.repeat(EFFECTS) { |effect| render(effect) }
    end

    private

    def declare_tables
      @numbers = @b.table(:adlib_number, self.class.numbers, width: :byte)
      @rooms = @b.table(:adlib_room, ROOM, width: :half)
      @effect_at = @b.table(:adlib_effect_at, EFFECT_AT, width: :word)
      @sine = @b.table(:adlib_sine, Opl2::SINE, width: :half)
      @gain = @b.table(:adlib_gain, Opl2::GAIN, width: :half)
      @fall = @b.table(:adlib_fall, Opl2::FALL, width: :word)
      @rise = @b.table(:adlib_rise, Opl2::RISE, width: :word)
      @attack_loss = @b.table(:adlib_attack_loss, Opl2::ATTACK_LOSS, width: :half)
      @doubled_multiples = @b.table(:adlib_doubled_multiple, Opl2::DOUBLED_MULTIPLES, width: :byte)
      @key_scale_loss = @b.table(:adlib_key_scale_loss, Opl2::KEY_SCALE_LOSS, width: :byte)
    end

    # The variables one operator keeps, by name: what Opl2::Operator keeps in itself.
    def operator_vars(side)
      %i[stage loss risen phase step scale_loss doubled_multiple tremolo holds_sustain level key_scale wave attack rise
         decay_fall release_fall sustain].to_h { |name| [name, routine_var(:"#{side}_#{name}")] }
    end

    # EFFECT +effect+ (its place in AdlibUnpacking.numbers) into its room: each note for a tick of the chip's
    # samples, then the fade until the carrier is quiet, as Opl2#render. What is left of the room
    # is counted and stays nought.
    def render(effect)
      written = routine_var(:written)
      length = routine_var(:length)
      written.store!(0)
      length.store!(0)
      routine_var(:room).store!(@rooms[effect])
      find(effect)
      if routine_var(:held) == 1
        set_up(@modulator, 0)
        set_up(@carrier, 1)
        routine_var(:clock).store!(0)
        routine_var(:sum).store!(0)
        routine_var(:in_sum).store!(0)
        play_notes(effect)
        play_tail(effect)
        @pack[:adlib_length][effect] = length
        if length > 0
          @pack[:adlib_note_frames][effect] = ((routine_var(:notes) * AdlibSounds::FRAMES_PER_SECOND) +
                                               Opl2::TICKS_PER_SECOND - 1) / Opl2::TICKS_PER_SECOND
          @pack[:adlib_priority][effect] = routine_var(:priority)
        end
      end
      @copy.count_written routine_var(:room) - written
    end

    # WHERE THE EFFECT IS, into from, with how many notes it has and its priority: AUDIOHED's
    # offset for its chunk, as AdlibSounds#effect finds it. held is nought for an effect this copy
    # lacks, and for one whose header would lie outside AUDIOT, which only a damaged copy has. A
    # count of notes running past the end of AUDIOT is cut to what is there.
    def find(effect)
      from = routine_var(:from)
      notes = routine_var(:notes)
      held = routine_var(:held)
      chunk = routine_var(:chunk)
      chunk.store!(AdlibSounds::FIRST_CHUNK + @numbers[effect])
      held.store!(0)
      if chunk + 1 < @head.size / 4
        from.store!(@head.word(4 * chunk))
        routine_var(:next_chunk).store!(@head.word((4 * chunk) + 4))
        if (from >= 0) && (routine_var(:next_chunk) - from >= AdlibSounds::HEADER_BYTES) &&
           (from + AdlibSounds::HEADER_BYTES <= @audio.size)
          held.store!(1)
          notes.store!(@audio.word(from))
          routine_var(:rest).store!(@audio.size - from - AdlibSounds::HEADER_BYTES)
          notes.store!(routine_var(:rest)) if (notes < 0) | (notes > routine_var(:rest))
          routine_var(:priority).store!(@audio.half(from + 4))
          routine_var(:block).store!(@audio.byte(from + BLOCK_AT) & 7)
        end
      end
    end

    # One operator as the instrument sets it, +side+ nought for the modulator and one for the
    # carrier: Opl2::Operator#initialize.
    def set_up(operator, side)
      at = routine_var(:from) + INSTRUMENT_AT + side
      char = routine_var(:char)
      register = routine_var(:register)
      block = routine_var(:block)
      offset = routine_var(:rate_offset)
      char.store!(@audio.byte(at))
      operator[:doubled_multiple].store!(@doubled_multiples[char & 0x0f])
      operator[:tremolo].store!((char >> 7) & 1)
      operator[:holds_sustain].store!((char >> 5) & 1)
      register.store!(@audio.byte(at + 2))
      operator[:level].store!((register & 0x3f) * Opl2::LEVEL_STEPS)
      operator[:key_scale].store!(register >> 6)
      operator[:wave].store!(@audio.byte(at + 8) & 3)
      offset.store!(block >> 1)
      offset.store!(block * 2) if ((char >> 4) & 1) == 1
      register.store!(@audio.byte(at + 4))
      operator[:attack].store!(register >> 4)
      find_rate(register >> 4)
      operator[:rise].store!(@rise[routine_var(:rate)])
      find_rate(register & 0x0f)
      operator[:decay_fall].store!(@fall[routine_var(:rate)])
      register.store!(@audio.byte(at + 6))
      find_rate(register & 0x0f)
      operator[:release_fall].store!(@fall[routine_var(:rate)])
      register.store!(register >> 4)
      operator[:sustain].store!((register * Opl2::SUSTAIN_STEPS) << Opl2::ENVELOPE_BITS)
      operator[:sustain].store!(Opl2::LOWEST_SUSTAIN << Opl2::ENVELOPE_BITS) if register == Opl2::LOWEST_SUSTAIN_LEVEL
      operator[:stage].store!(Opl2::OFF)
      operator[:loss].store!(Opl2::SILENT << Opl2::ENVELOPE_BITS)
      operator[:risen].store!(0)
      operator[:phase].store!(0)
      operator[:step].store!(0)
      operator[:scale_loss].store!(0)
    end

    # The chip's rate for a register's setting, into rate: Opl2::Operator#rate.
    def find_rate(setting)
      rate = routine_var(:rate)
      rate.store!(0)
      if setting > 0
        rate.store!((setting * 4) + routine_var(:rate_offset))
        rate.store!(Opl2::RATES - 1) if rate > Opl2::RATES - 1
      end
    end

    def play_notes(effect)
      tick = routine_var(:tick)
      left = routine_var(:left)
      tick.store!(0)
      while tick < routine_var(:notes)
        key_note(@audio.byte(routine_var(:from) + AdlibSounds::HEADER_BYTES + tick))
        left.store!(Opl2::NATIVE_SAMPLES_PER_TICK)
        while left > 0
          play_sample(effect)
          left.store!(left - 1)
        end
        tick.store!(tick + 1)
      end
    end

    def play_tail(effect)
      left = routine_var(:left)
      key_off(@modulator)
      key_off(@carrier)
      left.store!(Opl2::TAIL_SAMPLES)
      find_quiet
      while (left > 0) & (routine_var(:quiet) == 0)
        play_sample(effect)
        left.store!(left - 1)
        find_quiet
      end
    end

    # Whether the carrier has stopped, into quiet: Opl2::Operator#quiet?.
    def find_quiet
      quiet = routine_var(:quiet)
      quiet.store!(0)
      quiet.store!(1) if @carrier[:stage] == Opl2::OFF
      quiet.store!(1) if (@carrier[:loss] >> Opl2::ENVELOPE_BITS) + @carrier[:level] >= Opl2::QUIET
    end

    # A tick's byte: the tremolo for the tick, then the key down at that pitch, or up for nought.
    # Opl2#key_note.
    def key_note(note)
      count = routine_var(:tremolo_count)
      pitch = routine_var(:pitch)
      pitch.store!(note)
      count.store!((routine_var(:clock) >> 6) % (2 * Opl2::TREMOLO_PEAK))
      count.store!((2 * Opl2::TREMOLO_PEAK) - count) if count >= Opl2::TREMOLO_PEAK
      routine_var(:tremor).store!(count >> Opl2::TREMOLO_SHIFT)
      if pitch == 0
        key_off(@modulator)
        key_off(@carrier)
      else
        key_on(@modulator, pitch)
        key_on(@carrier, pitch)
      end
    end

    # Opl2::Operator#key_on.
    def key_on(operator, pitch)
      cut = routine_var(:cut)
      stage = operator[:stage]
      operator[:step].store!(((pitch << routine_var(:block)) * operator[:doubled_multiple]) >> 1)
      cut.store!(@key_scale_loss[pitch >> 6] - (Opl2::KEY_SCALE_OCTAVE * (Opl2::TOP_BLOCK - routine_var(:block))))
      cut.store!(0) if cut < 0
      if operator[:key_scale] == 0
        cut.store!(0)
      elsif operator[:key_scale] == 1
        cut.store!(cut >> 1)
      elsif operator[:key_scale] == 2
        cut.store!(cut >> 2)
      end
      operator[:scale_loss].store!(cut)
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

    # ONE OF THE CHIP'S SAMPLES, and every seventh time the average of seven written into the
    # effect's room: Opl2#play_sample. A sample that is not nought moves the effect's length on to
    # it, so the length ends at the last sound.
    def play_sample(effect)
      bend = routine_var(:bend)
      sum = routine_var(:sum)
      in_sum = routine_var(:in_sum)
      written = routine_var(:written)
      value = routine_var(:value)
      bend.store!(0)
      if @modulator[:stage] != Opl2::OFF
        step(@modulator, 0)
        bend.store!(routine_var(:out))
      end
      if @carrier[:stage] != Opl2::OFF
        step(@carrier, bend)
        sum.store!(sum + routine_var(:out))
      end
      routine_var(:clock).store!(routine_var(:clock) + 1)
      in_sum.store!(in_sum + 1)
      if in_sum == Opl2::RATE_DIVIDER
        value.store!(((((sum + Opl2::FULL_SUM) * Opl2::FULL_SAMPLE) + (Opl2::FULL_SUM / 2)) / Opl2::FULL_SUM) -
                     Opl2::FULL_SAMPLE)
        if written < routine_var(:room)
          @pack[:adlib_samples][@effect_at[effect] + written] = value
          @copy.count_written 1
          written.store!(written + 1)
          routine_var(:length).store!(written) if value != 0
        end
        sum.store!(0)
        in_sum.store!(0)
      end
    end

    # One sample of +operator+ into out, bent by +bend+ of the sine's places: Opl2::Operator#step.
    def step(operator, bend)
      place = routine_var(:place)
      loss = routine_var(:total_loss)
      wave = routine_var(:wave_value)
      half = Opl2::SINE_PLACES / 2
      move_envelope(operator)
      operator[:phase].store!((operator[:phase] + operator[:step]) & Opl2::PHASE_MASK)
      loss.store!((operator[:loss] >> Opl2::ENVELOPE_BITS) + operator[:level] + operator[:scale_loss])
      loss.store!(loss + routine_var(:tremor)) if operator[:tremolo] == 1
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
      routine_var(:out).store!((wave * @gain[loss]) >> Opl2::GAIN_BITS)
    end

    # Opl2::Operator#move_envelope.
    def move_envelope(operator)
      stage = operator[:stage]
      silent = Opl2::SILENT << Opl2::ENVELOPE_BITS
      if stage == Opl2::ATTACK
        rise(operator)
      elsif stage == Opl2::DECAY
        fall_toward(operator, operator[:sustain], operator[:decay_fall])
        stage.store!(Opl2::SUSTAIN) if routine_var(:fallen) == 1
      elsif stage == Opl2::SUSTAIN
        if operator[:holds_sustain] == 0
          fall_toward(operator, silent, operator[:release_fall])
          stage.store!(Opl2::OFF) if routine_var(:fallen) == 1
        end
      elsif stage == Opl2::RELEASE
        fall_toward(operator, silent, operator[:release_fall])
        stage.store!(Opl2::OFF) if routine_var(:fallen) == 1
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
      fallen = routine_var(:fallen)
      loss = operator[:loss]
      fallen.store!(1)
      if loss < floor
        loss.store!(loss + fall)
        fallen.store!(0) if loss < floor
      end
    end

    # A variable of the routine's, made the first time it is asked for.
    def routine_var(name) = (@routine_vars ||= {})[name] ||= @b.var(:"_adlib_unpacking_#{name}", 0)
  end
end
