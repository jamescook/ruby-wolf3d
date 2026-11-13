# frozen_string_literal: true

module Wolf3D
  # THE ADLIB EFFECTS, PLAYED THROUGH THE CHIP BY THE GAME ITSELF into the data pack (DataPack):
  # the knife, the pickups, the locked door, the tally's sounds, which Sounds makes into samples
  # for a trimmed build (AdlibSounds#recording).
  #
  # AUDIOT keeps each as a recipe for the AdLib card's chip (AdlibSounds says the layout), so this
  # is that chip, one channel of it, as game code: Opl2's arithmetic step for step, its operators
  # Opl2Routine's, and making the samples Opl2 makes. Opl2 says what each step is and why; a change
  # to one is a change to the other, and test_floor_unpacking holds them together.
  #
  # Each effect has a room of its own in adlib_samples, ROOM_SAMPLES long, at EFFECT_AT, signed samples at
  # Opl2::RENDER_RATE with nought after it ends, and three numbers beside: its length in samples
  # (nought for an effect this copy lacks, or one that makes no sound), the frames its notes last
  # and its priority, which are AdlibSounds::Recording's.
  #
  # This file is game code (VBlank.require_game_file): an `if` on a number the routine reads is a
  # branch in it, and a number one method sets and another reads is one of its game_variables.
  class AdlibUnpacking
    game_variables :written, :length, :room, :held, :from, :notes, :priority, :block,
                   :clock, :sum, :in_sum, :tremor

    # The effects held, in Sounds' order, by their numbers in AUDIOT.
    # Asked for as the routine is built, since Sounds loads after this file.
    def self.numbers = Sounds::ADLIB_EFFECT_NUMBERS.values

    # EACH EFFECT'S ROOM_SAMPLES, in samples: how long it runs through the chip, its fade included, counted
    # off the copies with Opl2 (the original's source does not say; both releases keep the same
    # effects). Spear keeps other effects and will want a list of its own.
    ROOM_SAMPLES = [429, 2478, 5884, 4572, 3275, 8216, 3223, 7963, 8064, 6057, 11_107, 14_099, 16_038, 3078, 12_186,
            11_255, 8529, 8977, 9633].freeze
    EFFECTS = ROOM_SAMPLES.length

    # Where each effect's room starts in adlib_samples.
    EFFECT_AT = ROOM_SAMPLES.each_with_object([0]) { |room, starts| starts << (starts.last + room) }.first(EFFECTS).freeze

    # An operator's five registers are two bytes each in the instrument, the modulator's first, in
    # INSTRUMENT_REGISTERS' order.
    INSTRUMENT_BYTE = 6
    INSTRUMENT_REGISTERS = [Opl2::CHAR_REGISTER, Opl2::SCALE_REGISTER, Opl2::ATTACK_REGISTER, Opl2::SUSTAIN_REGISTER,
                            Opl2::WAVE_REGISTER].freeze
    BLOCK_BYTE = 22

    # The slots the effects take, declared on +slots+ (the data pack's).
    def self.declare(slots)
      slots.samples :adlib_samples, count: ROOM_SAMPLES.sum
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
      @numbers = @b.table(:adlib_number, self.class.numbers, width: :byte)
      @rooms = @b.table(:adlib_room, ROOM_SAMPLES, width: :half)
      @effect_at = @b.table(:adlib_effect_at, EFFECT_AT, width: :word)
      @chip = Opl2Routine.new(@b, :adlib_chip, Opl2::NATIVE_CLOCK)
      @modulator = @chip.operator
      @carrier = @chip.operator
      @written = 0
      @length = 0
      @room = 0
      @held = false
      @from = 0
      @notes = 0
      @priority = 0
      @block = 0
      @clock = 0
      @sum = 0
      @in_sum = 0
      @tremor = 0
      @b.repeat(EFFECTS) { |effect| render(effect) }
    end

    private

    # EFFECT +effect+ (its place in AdlibUnpacking.numbers) into its room: each note for a tick of the chip's
    # samples, then the fade until the carrier is quiet, as Opl2#render. What is left of the room
    # is counted and stays nought.
    def render(effect)
      @written = 0
      @length = 0
      @room = @rooms[effect]
      find(effect)
      if @held
        set_up(@modulator, 0)
        set_up(@carrier, 1)
        @clock = 0
        @sum = 0
        @in_sum = 0
        play_notes(effect)
        play_tail(effect)
        @pack[:adlib_length][effect] = @length
        if @length > 0
          @pack[:adlib_note_frames][effect] = ((@notes * AdlibSounds::FRAMES_PER_SECOND) +
                                               Opl2::TICKS_PER_SECOND - 1) / Opl2::TICKS_PER_SECOND
          @pack[:adlib_priority][effect] = @priority
        end
      end
      @copy.count_written @room - @written
    end

    # WHERE THE EFFECT IS, into @from, with how many notes it has and its priority: AUDIOHED's
    # offset for its chunk, as AdlibSounds#effect finds it. @held is false for an effect this copy
    # lacks, and for one whose header would lie outside AUDIOT, which only a damaged copy has. A
    # count of notes running past the end of AUDIOT is cut to what is there.
    def find(effect)
      chunk = AdlibSounds::FIRST_CHUNK + @numbers[effect]
      @held = false
      if chunk + 1 < @head.size / 4
        @from = @head.word(4 * chunk)
        next_chunk = @head.word((4 * chunk) + 4)
        if (@from >= 0) && (next_chunk - @from >= AdlibSounds::HEADER_BYTES) &&
           (@from + AdlibSounds::HEADER_BYTES <= @audio.size)
          @held = true
          @notes = @audio.word(@from)
          rest = @audio.size - @from - AdlibSounds::HEADER_BYTES
          @notes = rest if (@notes < 0) || (@notes > rest)
          @priority = @audio.half(@from + 4)
          @block = @audio.byte(@from + BLOCK_BYTE) & 7
        end
      end
    end

    # One operator as the instrument sets it, +side+ nought for the modulator and one for the
    # carrier, at the effect's block: Opl2#operator_of.
    def set_up(operator, side)
      at = @from + INSTRUMENT_BYTE + side
      @chip.reset(operator)
      INSTRUMENT_REGISTERS.each_with_index do |kind, n|
        @chip.write_register(operator, kind, @audio.byte(at + (2 * n)))
      end
      @chip.tune(operator, @block, 0)
    end

    def play_notes(effect)
      tick = 0
      while tick < @notes
        key_note(@audio.byte(@from + AdlibSounds::HEADER_BYTES + tick))
        left = Opl2::NATIVE_SAMPLES_PER_TICK
        while left > 0
          play_sample(effect)
          left -= 1
        end
        tick += 1
      end
    end

    def play_tail(effect)
      @chip.key_off(@modulator)
      @chip.key_off(@carrier)
      left = Opl2::TAIL_SAMPLES
      quiet = @chip.quiet?(@carrier)
      while left > 0 && !quiet
        play_sample(effect)
        left -= 1
        quiet = @chip.quiet?(@carrier)
      end
    end

    # A tick's byte: the tremolo for the tick, then the key down at that pitch, or up for nought.
    # Opl2#key_note.
    def key_note(note)
      count = (@clock >> 6) % (2 * Opl2::TREMOLO_PEAK)
      count = (2 * Opl2::TREMOLO_PEAK) - count if count >= Opl2::TREMOLO_PEAK
      @tremor = count >> Opl2::TREMOLO_SHIFT
      if note == 0
        @chip.key_off(@modulator)
        @chip.key_off(@carrier)
      else
        [@modulator, @carrier].each do |operator|
          @chip.tune(operator, @block, note)
          @chip.key_on(operator)
        end
      end
    end

    # ONE OF THE CHIP'S SAMPLES, and every seventh time the average of seven written into the
    # effect's room: Opl2#play_sample. A sample that is not nought moves the effect's length on to
    # it, so the length ends at the last sound.
    def play_sample(effect)
      bend = 0
      bend = @chip.step(@modulator, 0, @tremor) if @modulator.stage != Opl2::OFF
      @sum += @chip.step(@carrier, bend, @tremor) if @carrier.stage != Opl2::OFF
      @clock += 1
      @in_sum += 1
      if @in_sum == Opl2::RATE_DIVIDER
        value = ((((@sum + Opl2::FULL_SUM) * Opl2::FULL_SAMPLE) + (Opl2::FULL_SUM / 2)) / Opl2::FULL_SUM) -
                Opl2::FULL_SAMPLE
        if @written < @room
          @pack[:adlib_samples][@effect_at[effect] + @written] = value
          @copy.count_written 1
          @written += 1
          @length = @written if value != 0
        end
        @sum = 0
        @in_sum = 0
      end
    end
  end
end
