# frozen_string_literal: true

module Wolf3D
  # A TRACK PLAYED THROUGH THE WHOLE CHIP: nine channels of two operators each, driven by the log of
  # register writes AdlibMusic reads. Opl2 is the one channel a sound effect needs.
  #
  # WHAT THE WRITES MEAN, from the chip's data sheet. An operator's five registers are spaced
  # through the chip in a pattern of cells with gaps in it, which CELLS spells out, and a channel's
  # modulator and carrier are three cells apart. A channel has a low byte of pitch, a high byte
  # holding the key, the block and the top of the pitch, and a byte of feedback and connection.
  #
  # THE TICKS ARE 700 A SECOND (SDL_IMFMusicPlayer), where other games' files of this format run at
  # 560. Getting that wrong plays every track at the wrong speed, and it sounds like a poor
  # conversion rather than a wrong constant.
  #
  # NOT HERE: the rhythm section of register 0xBD. The game's music never turns it on.
  class Opl2Track
    TICKS_PER_SECOND = 700

    # SAMPLES A SECOND, by what plays them. A byte at the rate sound effects use is static and a
    # muffle when it is music; the console can afford this much, and a computer the most a speaker
    # takes. Both divide STEP_RATE.
    CONSOLE_SAMPLE_RATE = 22_050
    COMPUTER_SAMPLE_RATE = 44_100

    # The operators are stepped this often, a little under twice the chip's own clock, and each
    # sample written is the average of the steps it covers. That keeps out the high notes that would
    # otherwise fold back down as noise.
    STEP_RATE = 88_200
    STEPS_PER_TICK = STEP_RATE.to_f / TICKS_PER_SECOND

    # Which channel and which of its two operators each cell of the chip is. Cells 6, 7, 14 and 15
    # are not there.
    CELLS = Ractor.make_shareable([0, 1, 2, 3, 4, 5, nil, nil, 6, 7, 8, 9, 10, 11, nil, nil, 12, 13, 14, 15, 16, 17])
    CHANNELS = 9
    OPERATORS_A_CHANNEL = 3

    EMPTY_OPERATOR = Ractor.make_shareable(AdlibSounds::Operator.new(char: 0, scale: 0, attack: 0, sustain: 0, wave: 0))

    # An operator's registers, by the top bits of the register number.
    OPERATOR_REGISTERS = Ractor.make_shareable({ 0x20 => :char, 0x40 => :scale, 0x60 => :attack, 0x80 => :sustain, 0xe0 => :wave })

    # Register 0xBD's top two bits deepen the chip's two slow wobbles.
    DEEP_TREMOLO = 0x80
    DEEP_VIBRATO = 0x40
    DEEP_TREMOLO_DECIBELS = 4.8
    DEEP_VIBRATO_DEPTH = 14.0 / 1200 * Math.log(2)

    # Feedback's seven settings run from a sixteenth of a half cycle to two whole cycles.
    FEEDBACK_TOP_CYCLES = 2.0
    FEEDBACK_SETTINGS = 7

    # THE LOUDEST MOMENT OF A TRACK IS PUT AT THE TOP OF A BYTE, less one step for the dither, since a
    # byte has so few steps that a quiet track uses half of them and is heard as static.
    LOUDEST_SAMPLE = 126

    # DITHER: noise of under one step, from a fixed seed, is added before rounding. Rounding alone
    # leaves an error that follows the music, which the ear hears as static; with the noise it is a
    # steady hiss far below the music. The seed makes the same track the same bytes every build.
    DITHER_SEED = 1992

    # The multiple of the pitch each of the sixteen settings gives. The repeats are the chip's.
    MULTIPLES = Ractor.make_shareable([0.5, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 12, 12, 15, 15])

    # 1.5, 3 and 6 decibels an octave for the settings, in the order the two bits number them.
    KEY_SCALE_SHARES = Ractor.make_shareable([0.0, 0.5, 0.25, 1.0])

    # Decibels taken off the top octave, by the top four bits of the pitch: the table in the manual.
    # It falls by three decibels for each block below the top one.
    KEY_SCALE_DECIBELS = Ractor.make_shareable(
      [0.0, 9.0, 12.0, 13.875, 15.0, 16.125, 16.875, 17.625, 18.0, 18.75, 19.125, 19.5, 19.875, 20.25, 20.625, 21.0]
    )

    LEVEL_STEP_DECIBELS = 0.75
    SUSTAIN_STEP_DECIBELS = 3.0

    # The last setting is not the next step down but nearly silence, 93 decibels.
    LOWEST_SUSTAIN_LEVEL = 15
    LOWEST_SUSTAIN_STEPS = 31
    SILENT_DECIBELS = 96.0

    # The time for the slowest real setting, in seconds: a decay right down, and an attack right up.
    # Each step of four in the rate halves it, which is one step of the register.
    SLOWEST_DECAY_SECONDS = 39.28
    SLOWEST_ATTACK_SECONDS = 2.826
    SLOWEST_RATE = 4
    RATE_STEPS_TO_HALVE = 4.0
    FASTEST_REGISTER = 15

    # At full level the modulator pushes the carrier four cycles either way.
    FULL_MODULATION_CYCLES = 4.0

    # Vibrato and tremolo are the chip's own slow wobble, at their shallow settings since the driver
    # leaves that register at nought.
    VIBRATO_HERTZ = 6.1
    VIBRATO_DEPTH = 7.0 / 1200 * Math.log(2)
    TREMOLO_HERTZ = 3.7
    TREMOLO_DECIBELS = 1.0

    # ONE OF THE TWO SINE WAVES, and its envelope, in floating point: the music is played while
    # building, where Ruby has floats. The effects' chip is Opl2, in whole numbers.
    class Oscillator
      TURN = 2 * Math::PI

      attr_reader :stage

      # +rate+ is how many times a second #step is called, which a track keeps down to save time.
      def initialize(operator, rate:)
        @rate = rate
        @tick_seconds = 1.0 / rate
        @block = 0
        @fnum = 0
        @char = 0
        @key_scale = 0
        %i[char scale attack sustain wave].each { |name| set(name, operator.public_send(name)) }
        @phase = 0.0
        @decibels = SILENT_DECIBELS
        @stage = :off
        tune(0, 0)
      end

      # A write to one of the five registers, which a track can make while a note sounds.
      def set(name, value)
        case name
        when :char
          @char = value
          @tremolo = value.anybits?(0x80)
          @vibrato = value.anybits?(0x40)
          @holds_sustain = value.anybits?(0x20)
          tune(@block, @fnum)
        when :scale
          @level = value & 0x3f
          @level_decibels = @level * LEVEL_STEP_DECIBELS
          @key_scale = value >> 6
          tune(@block, @fnum)
        when :attack
          @attack = value >> 4
          @decay = value & 0x0f
          @decay_fall = fall_a_step(@decay)
        when :sustain then set_sustain(value)
        when :wave then @wave = value & 3
        end
      end

      def multiple = MULTIPLES[@char & 0x0f]
      def scales_rate_by_key? = @char.anybits?(0x10)

      # A key already down keeps its envelope, which is why a run of notes is one long sound.
      def key_on(block, fnum)
        tune(block, fnum)
        return if %i[attack decay sustain].include?(@stage)

        @stage = @attack == FASTEST_REGISTER ? :decay : :attack
        @decibels = 0.0 if @stage == :decay
        @attack_seconds = seconds(SLOWEST_ATTACK_SECONDS, @attack)
        @attack_elapsed = 0.0
      end

      def key_off
        @stage = :release unless @stage == :off
      end

      def tune(block, fnum)
        @block = block
        @fnum = fnum
        @hertz = fnum * Opl2::NATIVE_RATE * (2.0**(block - 20)) * multiple
        @cycles_a_step = @hertz / @rate
        @key_code = (block * 2) + (fnum >> 9 & 1)
        @rate_offset = scales_rate_by_key? ? @key_code : @key_code >> 2
        @decay_fall = fall_a_step(@decay)
        @release_fall = fall_a_step(@release)
        octave_cut = KEY_SCALE_DECIBELS[fnum >> 6] - (3.0 * (7 - block))
        @scale_decibels = [octave_cut, 0.0].max * KEY_SCALE_SHARES[@key_scale]
      end

      # One of the chip's samples. +modulation+ is in cycles. +wobble+ is the slow shift of pitch and
      # +tremor+ the slow loss of level, both for this moment.
      #
      # This runs twice for every channel on every step of a track, tens of millions of times a
      # track, so what a register write settles is worked out at the write and kept: the cycles a
      # step moves, the decibels a step of decay or release falls, the level's decibels.
      def step(modulation, wobble, tremor)
        move_envelope
        @phase = (@phase + (@vibrato ? (@hertz * (1.0 + wobble)) / @rate : @cycles_a_step)) % 1.0
        loss = @decibels + @level_decibels + @scale_decibels + (@tremolo ? tremor : 0.0)
        wave_at(@phase + modulation) * (10.0**(-loss / 20))
      end

      private

      def set_sustain(value)
        level = value >> 4
        @sustain_decibels = (level == LOWEST_SUSTAIN_LEVEL ? LOWEST_SUSTAIN_STEPS : level) * SUSTAIN_STEP_DECIBELS
        @release = value & 0x0f
        @release_fall = fall_a_step(@release)
      end

      def wave_at(phase)
        sine = Math.sin(TURN * phase)
        case @wave
        when 0 then sine
        when 1 then sine.positive? ? sine : 0.0
        when 2 then sine.abs
        else (phase % 0.5) < 0.25 ? sine.abs : 0.0
        end
      end

      def move_envelope
        case @stage
        when :attack then rise
        when :decay then @stage = :sustain if fallen_to?(@sustain_decibels, @decay_fall)
        when :sustain then @stage = :off if !@holds_sustain && fallen_to?(SILENT_DECIBELS, @release_fall)
        when :release then @stage = :off if fallen_to?(SILENT_DECIBELS, @release_fall)
        end
      end

      # An attack climbs in amplitude and not in decibels, so it is heard from its first moments.
      def rise
        return if @attack_seconds.infinite?

        @attack_elapsed += @tick_seconds
        amplitude = @attack_elapsed / @attack_seconds
        @decibels = amplitude >= 1.0 ? 0.0 : -20 * Math.log10(amplitude)
        @stage = :decay if amplitude >= 1.0
      end

      # One step down toward +floor+, +fall+ decibels (nil where the rate never moves): whether the
      # level has got there.
      def fallen_to?(floor, fall)
        return true if @decibels >= floor
        return false unless fall

        @decibels += fall
        @decibels >= floor
      end

      # The decibels one step of a decay or release at +register+ falls, nil where it never moves.
      # Worked out at each write that changes it, never as the envelope moves.
      def fall_a_step(register)
        span = seconds(SLOWEST_DECAY_SECONDS, register || 0)
        span.infinite? ? nil : SILENT_DECIBELS / (span * @rate)
      end

      # A setting of nought never moves at all.
      def seconds(slowest, register)
        return Float::INFINITY if register.zero?

        rate = (register * 4) + @rate_offset
        slowest / (2.0**((rate - SLOWEST_RATE) / RATE_STEPS_TO_HALVE))
      end
    end

    # TWO OPERATORS AND HOW THEY ARE JOINED.
    class Channel
      attr_reader :operators

      def initialize
        @modulator = Oscillator.new(EMPTY_OPERATOR, rate: STEP_RATE)
        @carrier = Oscillator.new(EMPTY_OPERATOR, rate: STEP_RATE)
        @operators = [@modulator, @carrier]
        @low_pitch = 0
        @block = 0
        @high_pitch = 0
        @key = false
        @feedback = 0.0
        @additive = false
        @last = 0.0
        @before_last = 0.0
      end

      def low_pitch=(value)
        @low_pitch = value
        retune
      end

      def key=(value)
        @block = (value >> 2) & 7
        @high_pitch = value & 3
        key_now = value.anybits?(0x20)
        press(key_now) if key_now != @key
        @key = key_now
        retune
      end

      def connection=(value)
        @additive = value.anybits?(1)
        setting = (value >> 1) & 7
        @feedback = setting.zero? ? 0.0 : FEEDBACK_TOP_CYCLES / (2**(FEEDBACK_SETTINGS - setting))
      end

      def silent? = @modulator.stage == :off && @carrier.stage == :off

      # One sample of this channel, from -1 to 1 or so.
      def step(wobble, tremor)
        bend = modulator_step(wobble, tremor)
        return bend + carrier_step(0.0, wobble, tremor) if @additive

        carrier_step(bend * FULL_MODULATION_CYCLES, wobble, tremor)
      end

      private

      def carrier_step(modulation, wobble, tremor)
        @carrier.stage == :off ? 0.0 : @carrier.step(modulation, wobble, tremor)
      end

      def modulator_step(wobble, tremor)
        return 0.0 if @modulator.stage == :off

        out = @modulator.step((@last + @before_last) / 2 * @feedback, wobble, tremor)
        @before_last = @last
        @last = out
        out
      end

      def fnum = (@high_pitch << 8) | @low_pitch

      def press(down)
        @operators.each { |operator| down ? operator.key_on(@block, fnum) : operator.key_off }
      end

      def retune = @operators.each { |operator| operator.tune(@block, fnum) }
    end

    # +rate+ is the samples a second, CONSOLE_SAMPLE_RATE or COMPUTER_SAMPLE_RATE.
    def self.render(writes, rate:) = new(writes, rate: rate).render

    def initialize(writes, rate:)
      unless (STEP_RATE % rate).zero?
        raise ArgumentError, "Opl2Track cannot play at #{rate} samples a second. Give a rate that divides #{STEP_RATE}."
      end

      @writes = writes
      @steps_a_sample = STEP_RATE / rate
      @channels = Array.new(CHANNELS) { Channel.new }
      @vibrato_depth = VIBRATO_DEPTH
      @tremolo_decibels = TREMOLO_DECIBELS
      @out = []
      @due = 0.0
      @steps = 0
      @sum = 0.0
    end

    # Signed bytes at the rate asked for, as long as the track is.
    def render
      @writes.each do |register, value, wait|
        write(register, value)
        @due += wait * STEPS_PER_TICK
        play_step while @due >= 1.0
      end
      to_bytes
    end

    private

    def write(register, value)
      case register
      when 0xa0..0xa8 then @channels[register - 0xa0].low_pitch = value
      when 0xb0..0xb8 then @channels[register - 0xb0].key = value
      when 0xc0..0xc8 then @channels[register - 0xc0].connection = value
      when 0xbd then set_depths(value)
      else write_operator(register, value)
      end
    end

    def write_operator(register, value)
      name = OPERATOR_REGISTERS[register & 0xe0] or return
      cell = CELLS[register & 0x1f] or return

      channel, side = channel_and_side(cell)
      @channels[channel].operators[side].set(name, value)
    end

    # Cells run modulators of three channels, then carriers of the same three, in threes of channels.
    def channel_and_side(cell)
      group = cell / (OPERATORS_A_CHANNEL * 2)
      within = cell % (OPERATORS_A_CHANNEL * 2)
      [(group * OPERATORS_A_CHANNEL) + (within % OPERATORS_A_CHANNEL), within / OPERATORS_A_CHANNEL]
    end

    def set_depths(value)
      @tremolo_decibels = value.anybits?(DEEP_TREMOLO) ? DEEP_TREMOLO_DECIBELS : TREMOLO_DECIBELS
      @vibrato_depth = value.anybits?(DEEP_VIBRATO) ? DEEP_VIBRATO_DEPTH : VIBRATO_DEPTH
    end

    def play_step
      @due -= 1.0
      @steps += 1
      time = @steps.to_f / STEP_RATE
      wobble = @vibrato_depth * Math.sin(2 * Math::PI * VIBRATO_HERTZ * time)
      tremor = @tremolo_decibels * (1 + Math.sin(2 * Math::PI * TREMOLO_HERTZ * time)) / 2
      @channels.each { |channel| @sum += channel.step(wobble, tremor) unless channel.silent? }
      return unless (@steps % @steps_a_sample).zero?

      @out << (@sum / @steps_a_sample)
      @sum = 0.0
    end

    # Triangular noise, the sum of two draws, spans one step either way and averages nothing.
    def to_bytes
      loudest = @out.map(&:abs).max.to_f
      return @out.map { 0 } unless loudest.positive?

      scale = LOUDEST_SAMPLE / loudest
      noise = Random.new(DITHER_SEED)
      @out.map { |sample| ((sample * scale) + noise.rand - noise.rand).round.clamp(-128, 127) }
    end
  end
end
