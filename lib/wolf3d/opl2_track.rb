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
    RATE = Opl2::RENDER_RATE

    # Each sample written is this many of the operators', averaged, which keeps out the high notes
    # that would otherwise fold back down as noise. Fewer than the seven an effect takes, since a
    # track has up to eighteen operators and lasts minutes.
    STEPS_A_SAMPLE = 4
    STEP_RATE = RATE * STEPS_A_SAMPLE
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

    # Nine channels at full level would be far past a byte, and in the music four or five sound at
    # once, each well below full.
    GAIN = Opl2::FULL_SAMPLE * 0.8

    # TWO OPERATORS AND HOW THEY ARE JOINED.
    class Channel
      attr_reader :operators

      def initialize
        @modulator = Opl2::Oscillator.new(EMPTY_OPERATOR, rate: STEP_RATE)
        @carrier = Opl2::Oscillator.new(EMPTY_OPERATOR, rate: STEP_RATE)
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

        carrier_step(bend * Opl2::FULL_MODULATION_CYCLES, wobble, tremor)
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

    def self.render(writes) = new(writes).render

    def initialize(writes)
      @writes = writes
      @channels = Array.new(CHANNELS) { Channel.new }
      @vibrato_depth = Opl2::VIBRATO_DEPTH
      @tremolo_decibels = Opl2::TREMOLO_DECIBELS
      @out = []
      @due = 0.0
      @steps = 0
      @sum = 0.0
    end

    # Signed bytes at RATE, as long as the track is.
    def render
      @writes.each do |register, value, wait|
        write(register, value)
        @due += wait * STEPS_PER_TICK
        play_step while @due >= 1.0
      end
      @out
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
      @tremolo_decibels = value.anybits?(DEEP_TREMOLO) ? DEEP_TREMOLO_DECIBELS : Opl2::TREMOLO_DECIBELS
      @vibrato_depth = value.anybits?(DEEP_VIBRATO) ? DEEP_VIBRATO_DEPTH : Opl2::VIBRATO_DEPTH
    end

    def play_step
      @due -= 1.0
      @steps += 1
      time = @steps.to_f / STEP_RATE
      wobble = @vibrato_depth * Math.sin(2 * Math::PI * Opl2::VIBRATO_HERTZ * time)
      tremor = @tremolo_decibels * (1 + Math.sin(2 * Math::PI * Opl2::TREMOLO_HERTZ * time)) / 2
      @channels.each { |channel| @sum += channel.step(wobble, tremor) unless channel.silent? }
      return unless (@steps % STEPS_A_SAMPLE).zero?

      @out << (@sum / STEPS_A_SAMPLE * GAIN).round.clamp(-128, 127)
      @sum = 0.0
    end
  end
end
