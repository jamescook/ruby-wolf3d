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
  # branch in it, and every count is a variable of the routine's (#routine_var). The chip's nine
  # channels are written out nine times as the routine is built, since the routine has no lists of
  # variables, so each is its own variables.
  class MusicUnpacking
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

    CHANNEL_FIELDS = %i[low_pitch high_pitch block key feedback additive last before_last].freeze

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
      @channels = Array.new(Opl2Track::CHANNELS) do |c|
        CHANNEL_FIELDS.to_h { |field| [field, routine_var(:"channel_#{c}_#{field}")] }
                      .merge(modulator: @chip.operator(:"modulator_#{c}"), carrier: @chip.operator(:"carrier_#{c}"))
      end
      @operators = @channels.flat_map { |channel| [channel[:modulator], channel[:carrier]] }
      @b.repeat(self.class.numbers.length) { |song| render(song) }
    end

    private

    # SONG +song+ (its place in MusicUnpacking.numbers) into its room: each write, then its wait in
    # ticks, as Opl2Track#render. What is left of the room is counted and stays nought.
    def render(song)
      written = routine_var(:written)
      written.store!(0)
      routine_var(:room).store!(@rooms[song])
      find(song)
      if routine_var(:held) == 1
        set_up(song)
        play_writes(song)
      end
      @pack[:music_length][song] = written
      @copy.count_written routine_var(:room) - written
    end

    # WHERE THE TRACK'S WRITES ARE, into from, and how many, into writes: AdlibMusic#writes. held is
    # nought for a track this copy lacks, and for one whose length would lie outside AUDIOT, which
    # only a damaged copy has. A log running past the end of AUDIOT is cut to the writes there.
    def find(song)
      from = routine_var(:from)
      chunk = routine_var(:chunk)
      writes = routine_var(:writes)
      held = routine_var(:held)
      rest = routine_var(:rest)
      chunk.store!(AdlibMusic::FIRST_CHUNK + @numbers[song])
      held.store!(0)
      if chunk + 1 < @head.size / 4
        from.store!(@head.word(4 * chunk))
        if (from >= 0) && (from + AdlibMusic::LENGTH_BYTES <= @audio.size)
          writes.store!(@audio.half(from))
          rest.store!(@audio.size - from - AdlibMusic::LENGTH_BYTES)
          writes.store!(rest) if writes > rest
          writes.store!(writes / AdlibMusic::WRITE_BYTES)
          from.store!(from + AdlibMusic::LENGTH_BYTES)
          held.store!(1) if writes > 0
        end
      end
    end

    # The chip as Opl2Track.new leaves it, and the scale its samples are taken to the byte by:
    # Opl2Track#render at the computer's rate, a step a sample.
    def set_up(song)
      @channels.each do |channel|
        CHANNEL_FIELDS.each { |field| channel[field].store!(0) }
        @chip.reset(channel[:modulator])
        @chip.reset(channel[:carrier])
      end
      routine_var(:tremolo_shift).store!(Opl2::TREMOLO_SHIFT)
      routine_var(:vibrato_shift).store!(Opl2Track::VIBRATO_SHIFT)
      routine_var(:steps).store!(0)
      routine_var(:dither).store!(Opl2Track::DITHER_SEED)
      routine_var(:limit).store!(@loudest[@numbers[song]])
      routine_var(:scale).store!((Opl2Track::LOUDEST_SAMPLE << Opl2Track::SCALE_BITS) / routine_var(:limit))
    end

    # Opl2Track#play: each write, then a tick of steps for each tick of its wait.
    def play_writes(song)
      write = routine_var(:write)
      wait = routine_var(:wait)
      left = routine_var(:left)
      at = routine_var(:at)
      write.store!(0)
      while write < routine_var(:writes)
        at.store!(routine_var(:from) + (write * AdlibMusic::WRITE_BYTES))
        write_register(@audio.byte(at), @audio.byte(at + 1))
        wait.store!(@audio.half(at + 2))
        while wait > 0
          start_tick
          left.store!(Opl2Track::STEPS_PER_TICK)
          while left > 0
            play_step(song)
            left.store!(left - 1)
          end
          wait.store!(wait - 1)
        end
        write.store!(write + 1)
      end
    end

    # Opl2Track#write, for register +register+ and +value+, two bytes of the log.
    def write_register(register, value)
      number = routine_var(:register)
      byte = routine_var(:value)
      number.store!(register)
      byte.store!(value)
      if number == Opl2Track::DEPTHS
        routine_var(:tremolo_shift).store!(Opl2::TREMOLO_SHIFT)
        routine_var(:tremolo_shift).store!(Opl2Track::DEEP_TREMOLO_SHIFT) if (byte & Opl2Track::DEEP_TREMOLO) != 0
        routine_var(:vibrato_shift).store!(Opl2Track::VIBRATO_SHIFT)
        routine_var(:vibrato_shift).store!(Opl2Track::DEEP_VIBRATO_SHIFT) if (byte & Opl2Track::DEEP_VIBRATO) != 0
      elsif (number >= Opl2Track::LOW_PITCH) & (number < Opl2Track::LOW_PITCH + Opl2Track::CHANNELS)
        on_channel(number - Opl2Track::LOW_PITCH) do |channel|
          channel[:low_pitch].store!(byte)
          retune(channel)
        end
      elsif (number >= Opl2Track::KEY) & (number < Opl2Track::KEY + Opl2Track::CHANNELS)
        on_channel(number - Opl2Track::KEY) { |channel| write_key(channel, byte) }
      elsif (number >= Opl2Track::CONNECTION) & (number < Opl2Track::CONNECTION + Opl2Track::CHANNELS)
        on_channel(number - Opl2Track::CONNECTION) do |channel|
          channel[:additive].store!(byte & 1)
          channel[:feedback].store!((byte >> 1) & 7)
        end
      else
        write_operator(number, byte)
      end
    end

    # The block with the channel numbered +index+, a number the routine worked out: one branch for
    # each of the nine.
    def on_channel(index)
      which = routine_var(:channel)
      which.store!(index)
      @channels.each_with_index do |channel, c|
        yield channel if which == c
      end
    end

    # Opl2Track::Channel#key=.
    def write_key(channel, byte)
      key = routine_var(:key)
      channel[:block].store!((byte >> 2) & 7)
      channel[:high_pitch].store!(byte & 3)
      retune(channel)
      key.store!((byte >> 5) & 1)
      if key != channel[:key]
        channel[:key].store!(key)
        if key == 1
          @chip.key_on(channel[:modulator])
          @chip.key_on(channel[:carrier])
        else
          @chip.key_off(channel[:modulator])
          @chip.key_off(channel[:carrier])
        end
      end
    end

    # Opl2Track::Channel#retune.
    def retune(channel)
      fnum = routine_var(:fnum)
      fnum.store!((channel[:high_pitch] << 8) | channel[:low_pitch])
      @chip.tune(channel[:modulator], channel[:block], fnum)
      @chip.tune(channel[:carrier], channel[:block], fnum)
    end

    # Opl2Track#write_operator: the operator the cell names, if any, one branch for each of the
    # eighteen.
    def write_operator(number, byte)
      which = routine_var(:operator)
      which.store!(@cell_operators[number & 0x1f])
      @operators.each_with_index do |operator, n|
        @chip.write_register(operator, number & 0xe0, byte) if which == n
      end
    end

    # Opl2Track#start_tick.
    def start_tick
      count = routine_var(:tremolo_count)
      steps = routine_var(:steps)
      shape = routine_var(:shape)
      count.store!((steps / Opl2Track::TREMOLO_STEPS) % (2 * Opl2::TREMOLO_PEAK))
      count.store!((2 * Opl2::TREMOLO_PEAK) - count) if count >= Opl2::TREMOLO_PEAK
      routine_var(:tremor).store!(count >> routine_var(:tremolo_shift))
      shape.store!(@vibrato_shape[(steps / Opl2Track::VIBRATO_STEPS) & 7] - VIBRATO_LIFT)
      @operators.each { |operator| @chip.vibrate(operator, shape, routine_var(:vibrato_shift)) }
    end

    # ONE STEP OF THE NINE CHANNELS, which at the computer's rate is one sample, written into the
    # song's room: Opl2Track#play's step and Opl2Track#sample_of.
    def play_step(song)
      sum = routine_var(:sum)
      written = routine_var(:written)
      sum.store!(0)
      @channels.each do |channel|
        if (channel[:modulator][:stage] != Opl2::OFF) | (channel[:carrier][:stage] != Opl2::OFF)
          sum.store!(sum + step_channel(channel))
        end
      end
      routine_var(:steps).store!(routine_var(:steps) + 1)
      if written < routine_var(:room)
        @pack[:music_samples][@song_at[song] + written] = sample_of(sum)
        @copy.count_written 1
        written.store!(written + 1)
      end
    end

    # Opl2Track::Channel#step, into the variable it hands back.
    def step_channel(channel)
      out = routine_var(:channel_out)
      heard = routine_var(:heard)
      bend = routine_var(:bend)
      tremor = routine_var(:tremor)
      out.store!(0)
      if channel[:modulator][:stage] != Opl2::OFF
        bend.store!(0)
        if channel[:feedback] != 0
          bend.store!((channel[:last] + channel[:before_last]) >> (Opl2Track::FEEDBACK_SHIFT - channel[:feedback]))
        end
        out.store!(@chip.step(channel[:modulator], bend, tremor))
        channel[:before_last].store!(channel[:last])
        channel[:last].store!(out)
      end
      heard.store!(0)
      if channel[:carrier][:stage] != Opl2::OFF
        bend.store!(out)
        bend.store!(0) if channel[:additive] == 1
        heard.store!(@chip.step(channel[:carrier], bend, tremor))
      end
      heard.store!(heard + out) if channel[:additive] == 1
      heard
    end

    # Opl2Track#sample_of, into the variable it hands back.
    def sample_of(sum)
      limit = routine_var(:limit)
      dither = routine_var(:dither)
      noise = routine_var(:noise)
      value = routine_var(:sample)
      value.store!(sum)
      value.store!(limit) if value > limit
      value.store!(0 - limit) if value < 0 - limit
      dither.store!(((dither * Opl2Track::DITHER_MULTIPLIER) + Opl2Track::DITHER_INCREMENT) & Opl2Track::DITHER_MASK)
      noise.store!(dither)
      dither.store!(((dither * Opl2Track::DITHER_MULTIPLIER) + Opl2Track::DITHER_INCREMENT) & Opl2Track::DITHER_MASK)
      noise.store!(noise - dither)
      value.store!(((value * routine_var(:scale)) + noise + (1 << (Opl2Track::SCALE_BITS - 1))) >> Opl2Track::SCALE_BITS)
      value
    end

    # A variable of the routine's, made the first time it is asked for.
    def routine_var(name) = (@routine_vars ||= {})[name] ||= @b.var(:"_music_unpacking_#{name}", 0)
  end
end
