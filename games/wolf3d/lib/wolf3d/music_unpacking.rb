# frozen_string_literal: true

module Wolf3D
  # THE MUSIC, PLAYED THROUGH THE WHOLE CHIP BY THE GAME ITSELF into the data pack (DataPack): every
  # song a whole build holds (Music::WHOLE_SONGS), which a trimmed build makes with
  # AdlibMusic#recording.
  #
  # AUDIOT keeps each track as a log of writes to the AdLib card's chip (AdlibMusic says the layout),
  # so this is that chip, all nine channels, as game code: Opl2Track's arithmetic step for step, its
  # operators Opl2Routine's, making the samples Opl2Track makes at the computer's rate. Opl2Track
  # says what each step is and why; a change to one is a change to the other, and
  # test_floor_unpacking holds them together.
  #
  # Each song has a room of its own in music_samples, as long as its track runs in either release
  # (AdlibMusic::TICKS), at SONG_AT, and its length in samples beside it in music_length: nought for
  # a song this copy lacks, which the shareware does for most. Each song is played from the copy and
  # nothing another song left, so the songs could be played apart, each on a core of its own.
  #
  # This file is game code (VBlank.require_game_file): an `if` on a number the routine reads is a
  # branch in it, and a number one method sets and another reads is one of its game_variables. The chip's nine
  # channels are written out nine times as the routine is built, since the routine has no lists of
  # variables, so each is its own variables.
  class MusicUnpacking
    # The song being played (#render): how many samples of its room are written, and how long the
    # room is.
    game_variables :written, :room
    # Where the song's track is in AUDIOT (#find): whether this copy holds it, where its writes
    # start, and how many there are.
    game_variables :held, :from, :writes
    # What the whole chip shares, not one channel: how deep the tremolo and vibrato are (set by a
    # write to Opl2Track::DEPTHS), the steps played since the song began, which time both, and how
    # much quieter the tremolo makes an operator this tick (#start_tick).
    game_variables :tremolo_shift, :vibrato_shift, :steps, :tremor
    # Taking the nine channels' sum to a sample (#sample_of): the song's loudest sum, the scale that
    # takes it to the loudest sample, and the dither's noise, drawn afresh for each sample.
    game_variables :limit, :scale, :dither

    # The songs held, by their numbers in AUDIOT. Asked for as the routine is built, since Music
    # loads after this file.
    def self.numbers = Music::WHOLE_SONGS

    # Each song's room, in samples at the computer's rate.
    def self.rooms = numbers.map { |number| AdlibMusic::TICKS[number] * Opl2Track::STEPS_PER_TICK }

    # Where each song's room starts in music_samples.
    def self.song_at = rooms.each_with_object([0]) { |room, starts| starts << (starts.last + room) }.first(numbers.length)

    # The slots the music takes, declared on +slots+ (the data pack's).
    def self.declare(slots)
      slots.samples :music_samples, count: rooms.sum
      slots.numbers :music_length, count: numbers.length, width: :word, signed: false
    end

    # Which operator of the eighteen each cell of the chip is, two to a channel, the modulator
    # first; NO_OPERATOR where Opl2Track::CELLS has none.
    NO_OPERATOR = 255
    CELL_OPERATORS = (0...32).map do |cell|
      at = Opl2Track::CELLS[cell] or next NO_OPERATOR
      group = at / (Opl2Track::OPERATORS_A_CHANNEL * 2)
      within = at % (Opl2Track::OPERATORS_A_CHANNEL * 2)
      channel = (group * Opl2Track::OPERATORS_A_CHANNEL) + (within % Opl2Track::OPERATORS_A_CHANNEL)
      (channel * 2) + (within / Opl2Track::OPERATORS_A_CHANNEL)
    end.freeze

    # Opl2Track::VIBRATO_SHAPE lifted above nought for a table of bytes, and how far.
    VIBRATO_LIFT = 2
    LIFTED_VIBRATO_SHAPE = Opl2Track::VIBRATO_SHAPE.map { |shape| shape + VIBRATO_LIFT }.freeze

    # One of the chip's nine channels: what its registers hold, the last two samples its modulator
    # gave (for feedback), and its two operators (Opl2Routine::Operator).
    Channel = Struct.new(:low_pitch, :high_pitch, :block, :key, :feedback, :additive, :last, :before_last,
                         :modulator, :carrier) do
      # What the track wrote to the channel's registers: its frequency number in two parts, its
      # octave, whether its key is down, how much of the modulator feeds back into itself, and
      # whether the two operators are heard added together rather than one bending the other.
      game_variables :low_pitch, :high_pitch, :block, :key, :feedback, :additive
      # The modulator's last two samples, which its feedback adds up.
      game_variables :last, :before_last
    end
    CHANNEL_NUMBERS = %i[low_pitch high_pitch block key feedback additive last before_last].freeze

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
      @numbers = @b.table(:music_number, self.class.numbers, width: :byte)
      @rooms = @b.table(:music_room, self.class.rooms, width: :word)
      @song_at = @b.table(:music_song_at, self.class.song_at, width: :word)
      @loudest = @b.table(:music_loudest, AdlibMusic::LOUDEST, width: :half)
      @cell_operators = @b.table(:music_cell_operator, CELL_OPERATORS, width: :byte)
      @vibrato_shape = @b.table(:music_vibrato_shape, LIFTED_VIBRATO_SHAPE, width: :byte)
      @chip = Opl2Routine.new(@b, :music_chip, Opl2Track::CLOCK)
      @channels = Array.new(Opl2Track::CHANNELS) do
        Channel.new(*Array.new(CHANNEL_NUMBERS.length, 0), @chip.operator, @chip.operator)
      end
      @operators = @channels.flat_map { |channel| [channel.modulator, channel.carrier] }
      @written = 0
      @room = 0

      @held = false
      @from = 0
      @writes = 0

      @tremolo_shift = 0
      @vibrato_shift = 0
      @steps = 0
      @tremor = 0

      @limit = 0
      @scale = 0
      @dither = 0
      @b.repeat(self.class.numbers.length) { |song| render(song) }
    end

    private

    # SONG +song+ (its place in MusicUnpacking.numbers) into its room: each write, then its wait in
    # ticks, as Opl2Track#render. What is left of the room is counted and stays nought.
    def render(song)
      @written = 0
      @room = @rooms[song]
      find(song)
      if @held
        set_up(song)
        play_writes(song)
      end
      @pack[:music_length][song] = @written
      @copy.count_written @room - @written
    end

    # WHERE THE TRACK'S WRITES ARE, into @from, and how many, into @writes: AdlibMusic#writes. @held
    # is false for a track this copy lacks, and for one whose length would lie outside AUDIOT, which
    # only a damaged copy has. A log running past the end of AUDIOT is cut to the writes there.
    def find(song)
      chunk = AdlibMusic::FIRST_CHUNK + @numbers[song]
      @held = false
      if chunk + 1 < @head.size / 4
        @from = @head.word(4 * chunk)
        if (@from >= 0) && (@from + AdlibMusic::LENGTH_BYTES <= @audio.size)
          @writes = @audio.half(@from)
          rest = @audio.size - @from - AdlibMusic::LENGTH_BYTES
          @writes = rest if @writes > rest
          @writes /= AdlibMusic::WRITE_BYTES
          @from += AdlibMusic::LENGTH_BYTES
          @held = true if @writes > 0
        end
      end
    end

    # The chip as Opl2Track.new leaves it, and the scale its samples are taken to the byte by:
    # Opl2Track#render at the computer's rate, a step a sample.
    def set_up(song)
      @channels.each do |channel|
        channel.low_pitch = 0
        channel.high_pitch = 0
        channel.block = 0
        channel.key = 0
        channel.feedback = 0
        channel.additive = 0
        channel.last = 0
        channel.before_last = 0
        @chip.reset(channel.modulator)
        @chip.reset(channel.carrier)
      end
      @tremolo_shift = Opl2::TREMOLO_SHIFT
      @vibrato_shift = Opl2Track::VIBRATO_SHIFT
      @steps = 0
      @dither = Opl2Track::DITHER_SEED
      @limit = @loudest[@numbers[song]]
      @scale = (Opl2Track::LOUDEST_SAMPLE << Opl2Track::SCALE_BITS) / @limit
    end

    # Opl2Track#play: each write, then a tick of steps for each tick of its wait.
    def play_writes(song)
      write = 0
      while write < @writes
        at = @from + (write * AdlibMusic::WRITE_BYTES)
        write_register(@audio.byte(at), @audio.byte(at + 1))
        wait = @audio.half(at + 2)
        while wait > 0
          start_tick
          left = Opl2Track::STEPS_PER_TICK
          while left > 0
            play_step(song)
            left -= 1
          end
          wait -= 1
        end
        write += 1
      end
    end

    # Opl2Track#write, for register +number+ and +byte+, two bytes of the log.
    def write_register(number, byte)
      if number == Opl2Track::DEPTHS
        @tremolo_shift = Opl2::TREMOLO_SHIFT
        @tremolo_shift = Opl2Track::DEEP_TREMOLO_SHIFT if (byte & Opl2Track::DEEP_TREMOLO) != 0
        @vibrato_shift = Opl2Track::VIBRATO_SHIFT
        @vibrato_shift = Opl2Track::DEEP_VIBRATO_SHIFT if (byte & Opl2Track::DEEP_VIBRATO) != 0
      elsif (number >= Opl2Track::LOW_PITCH) && (number < Opl2Track::LOW_PITCH + Opl2Track::CHANNELS)
        with_channel(number - Opl2Track::LOW_PITCH) do |channel|
          channel.low_pitch = byte
          retune(channel)
        end
      elsif (number >= Opl2Track::KEY) && (number < Opl2Track::KEY + Opl2Track::CHANNELS)
        with_channel(number - Opl2Track::KEY) { |channel| write_key(channel, byte) }
      elsif (number >= Opl2Track::CONNECTION) && (number < Opl2Track::CONNECTION + Opl2Track::CHANNELS)
        with_channel(number - Opl2Track::CONNECTION) do |channel|
          channel.additive = byte & 1
          channel.feedback = (byte >> 1) & 7
        end
      else
        write_operator(number, byte)
      end
    end

    # The block with the channel numbered +index+, a number the routine worked out: one branch for
    # each of the nine.
    def with_channel(index)
      @channels.each_with_index do |channel, c|
        yield channel if index == c
      end
    end

    # Opl2Track::Channel#key=.
    def write_key(channel, byte)
      channel.block = (byte >> 2) & 7
      channel.high_pitch = byte & 3
      retune(channel)
      key = (byte >> 5) & 1
      if key != channel.key
        channel.key = key
        if key == 1
          @chip.key_on(channel.modulator)
          @chip.key_on(channel.carrier)
        else
          @chip.key_off(channel.modulator)
          @chip.key_off(channel.carrier)
        end
      end
    end

    # Opl2Track::Channel#retune.
    def retune(channel)
      fnum = (channel.high_pitch << 8) | channel.low_pitch
      @chip.tune(channel.modulator, channel.block, fnum)
      @chip.tune(channel.carrier, channel.block, fnum)
    end

    # Opl2Track#write_operator: the operator the cell names, if any, one branch for each of the
    # eighteen.
    def write_operator(number, byte)
      which = @cell_operators[number & 0x1f]
      @operators.each_with_index do |operator, n|
        @chip.write_register(operator, number & 0xe0, byte) if which == n
      end
    end

    # Opl2Track#start_tick.
    def start_tick
      count = (@steps / Opl2Track::TREMOLO_STEPS) % (2 * Opl2::TREMOLO_PEAK)
      count = (2 * Opl2::TREMOLO_PEAK) - count if count >= Opl2::TREMOLO_PEAK
      @tremor = count >> @tremolo_shift
      shape = @vibrato_shape[(@steps / Opl2Track::VIBRATO_STEPS) & 7] - VIBRATO_LIFT
      @operators.each { |operator| @chip.vibrate(operator, shape, @vibrato_shift) }
    end

    # ONE STEP OF THE NINE CHANNELS, which at the computer's rate is one sample, written into the
    # song's room: Opl2Track#play's step and Opl2Track#sample_of.
    def play_step(song)
      sum = 0
      @channels.each do |channel|
        if (channel.modulator.stage != Opl2::OFF) || (channel.carrier.stage != Opl2::OFF)
          sum += step_channel(channel)
        end
      end
      @steps += 1
      if @written < @room
        @pack[:music_samples][@song_at[song] + @written] = sample_of(sum)
        @copy.count_written 1
        @written += 1
      end
    end

    # Opl2Track::Channel#step.
    def step_channel(channel)
      out = 0
      if channel.modulator.stage != Opl2::OFF
        bend = 0
        bend = (channel.last + channel.before_last) >> (Opl2Track::FEEDBACK_SHIFT - channel.feedback) if channel.feedback != 0
        out = @chip.step(channel.modulator, bend, @tremor)
        channel.before_last = channel.last
        channel.last = out
      end
      heard = 0
      if channel.carrier.stage != Opl2::OFF
        bend = out
        bend = 0 if channel.additive == 1
        heard = @chip.step(channel.carrier, bend, @tremor)
      end
      heard += out if channel.additive == 1
      heard
    end

    # Opl2Track#sample_of.
    def sample_of(sum)
      value = sum
      value = @limit if value > @limit
      value = 0 - @limit if value < 0 - @limit
      noise = next_dither
      noise -= next_dither
      ((value * @scale) + noise + (1 << (Opl2Track::SCALE_BITS - 1))) >> Opl2Track::SCALE_BITS
    end

    # The next step of Opl2Track's dither, Opl2Track#draw_dither.
    def next_dither
      @dither = ((@dither * Opl2Track::DITHER_MULTIPLIER) + Opl2Track::DITHER_INCREMENT) & Opl2Track::DITHER_MASK
      @dither
    end
  end
end
