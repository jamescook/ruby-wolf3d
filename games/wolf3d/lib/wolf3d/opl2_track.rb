# frozen_string_literal: true

module Wolf3D
  # A TRACK PLAYED THROUGH THE WHOLE CHIP: nine channels of two operators each (Opl2::Operator),
  # driven by the log of register writes AdlibMusic reads. Opl2 is the one channel a sound effect
  # needs.
  #
  # IT IS WRITTEN TWICE, as Opl2 is, and the two must make the same samples. This one is plain
  # Ruby, and plays a track while a trimmed build is made. MusicUnpacking is the same arithmetic as
  # game code, which a whole build runs at LOAD ROM, so every step is in whole numbers.
  # test_floor_unpacking holds the two to each other.
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

    # THE OPERATORS ARE STEPPED AT THE COMPUTER'S RATE, a little under the chip's own, so a tick is
    # a whole number of steps and a computer's sample is one step; the console's is two, averaged.
    STEP_RATE = COMPUTER_SAMPLE_RATE
    STEPS_PER_TICK = STEP_RATE / TICKS_PER_SECOND
    CLOCK = Ractor.make_shareable(Opl2.clock(STEP_RATE))

    # Which channel and which of its two operators each cell of the chip is. Cells 6, 7, 14 and 15
    # are not there.
    CELLS = Ractor.make_shareable([0, 1, 2, 3, 4, 5, nil, nil, 6, 7, 8, 9, 10, 11, nil, nil, 12, 13, 14, 15, 16, 17])
    CHANNELS = 9
    OPERATORS_A_CHANNEL = 3

    # A channel's registers, each followed by its number, nought to eight.
    LOW_PITCH = 0xa0
    KEY = 0xb0
    CONNECTION = 0xc0
    DEPTHS = 0xbd

    # THE CHIP'S TWO SLOW WOBBLES, read once a tick, each with a deep setting in register 0xBD's top
    # two bits. Tremolo is Opl2's count, moved every 64 of the chip's samples, which is 57 steps
    # here: its loss a sixteenth of the count, or a quarter deep (1 and 4.8 decibels). Vibrato moves
    # through VIBRATO_SHAPE every 1024 of the chip's samples, 908 steps, and moves a pitch by its top
    # three bits times the shape, a quarter of that, or a half deep (7 and 14 cents).
    DEEP_TREMOLO = 0x80
    DEEP_VIBRATO = 0x40
    TREMOLO_STEPS = 57
    DEEP_TREMOLO_SHIFT = 2
    VIBRATO_STEPS = 908
    VIBRATO_SHAPE = Ractor.make_shareable([0, 1, 2, 1, 0, -1, -2, -1])
    VIBRATO_SHIFT = 2
    DEEP_VIBRATO_SHIFT = 1

    # FEEDBACK bends a modulator by the sum of its last two samples, shifted down by nine less the
    # setting: two whole cycles at the top setting, seven, down to a sixteenth of one at one. Nought
    # is none.
    FEEDBACK_SHIFT = 9

    # THE LOUDEST MOMENT OF A TRACK IS PUT AT THE TOP OF A BYTE, less one step for the dither, since a
    # byte has so few steps that a quiet track uses half of them and is heard as static. How loud a
    # track's loudest step is, is AdlibMusic::LOUDEST, counted with #loudest; each sample is scaled by
    # LOUDEST_SAMPLE over it, in SCALE_BITS of fraction.
    LOUDEST_SAMPLE = 126
    SCALE_BITS = 16

    # DITHER: noise of under one step is added before rounding. Rounding alone leaves an error that
    # follows the music, which the ear hears as static; with the noise it is a steady hiss far below
    # the music. Each draw is the next of a sixteen-bit count, multiplied and added to, from a fixed
    # seed, so the same track is the same bytes every build, and the count stays inside the game's
    # numbers.
    DITHER_SEED = 1992
    DITHER_MULTIPLIER = 25_173
    DITHER_INCREMENT = 13_849
    DITHER_MASK = 0xffff

    # TWO OPERATORS AND HOW THEY ARE JOINED.
    class Channel
      attr_reader :modulator, :carrier

      def initialize
        @modulator = Opl2::Operator.new(CLOCK)
        @carrier = Opl2::Operator.new(CLOCK)
        @low_pitch = 0
        @high_pitch = 0
        @block = 0
        @key = 0
        @feedback = 0
        @additive = 0
        @last = 0
        @before_last = 0
      end

      def low_pitch=(value)
        @low_pitch = value
        retune
      end

      # The key, the block and the top two bits of the pitch. The key is pressed or let go only
      # when it changes.
      def key=(value)
        @block = (value >> 2) & 7
        @high_pitch = value & 3
        retune
        key = (value >> 5) & 1
        return if key == @key

        @key = key
        [@modulator, @carrier].each { |operator| key == 1 ? operator.key_on : operator.key_off }
      end

      def connection=(value)
        @additive = value & 1
        @feedback = (value >> 1) & 7
      end

      def silent? = @modulator.stage == Opl2::OFF && @carrier.stage == Opl2::OFF

      def vibrate(shape, shift)
        @modulator.vibrate(shape, shift)
        @carrier.vibrate(shape, shift)
      end

      # One step of this channel. Joined the usual way the modulator bends the carrier and only the
      # carrier is heard; joined additively both are heard and neither bends the other.
      def step(tremor)
        out = 0
        unless @modulator.stage == Opl2::OFF
          bend = @feedback.zero? ? 0 : (@last + @before_last) >> (FEEDBACK_SHIFT - @feedback)
          out = @modulator.step(bend, tremor)
          @before_last = @last
          @last = out
        end
        heard = @carrier.stage == Opl2::OFF ? 0 : @carrier.step(@additive == 1 ? 0 : out, tremor)
        @additive == 1 ? out + heard : heard
      end

      private

      def retune
        fnum = (@high_pitch << 8) | @low_pitch
        @modulator.tune(@block, fnum)
        @carrier.tune(@block, fnum)
      end
    end

    # +writes+ played at +rate+ samples a second (CONSOLE_SAMPLE_RATE or COMPUTER_SAMPLE_RATE), its
    # loudest step +loudest+ (#loudest): signed bytes, as long as the track is.
    def self.render(writes, rate:, loudest:) = new(writes).render(rate: rate, loudest: loudest)

    # How far from nought the loudest step of +writes+ goes, the nine channels together; one for a
    # silent track, so it can be divided by.
    def self.loudest(writes)
      most = 1
      new(writes).play { |sum| most = sum.abs if sum.abs > most }
      most
    end

    def initialize(writes)
      @writes = writes
      @channels = Array.new(CHANNELS) { Channel.new }
      @tremolo_shift = Opl2::TREMOLO_SHIFT
      @vibrato_shift = VIBRATO_SHIFT
      @steps = 0
    end

    def render(rate:, loudest:)
      unless (STEP_RATE % rate).zero?
        raise ArgumentError, "Opl2Track cannot play at #{rate} samples a second. Give a rate that divides #{STEP_RATE}."
      end

      steps_a_sample = STEP_RATE / rate
      @limit = loudest * steps_a_sample
      @scale = (LOUDEST_SAMPLE << SCALE_BITS) / @limit
      @dither = DITHER_SEED
      out = []
      sum = 0
      play do |step|
        sum += step
        next unless (@steps % steps_a_sample).zero?

        out << sample_of(sum)
        sum = 0
      end
      out
    end

    # Each step of the track, the nine channels' sum, to the block.
    def play
      @writes.each do |register, value, wait|
        write(register, value)
        wait.times do
          start_tick
          STEPS_PER_TICK.times do
            sum = 0
            @channels.each { |channel| sum += channel.step(@tremor) unless channel.silent? }
            @steps += 1
            yield sum
          end
        end
      end
    end

    private

    def write(register, value)
      if register == DEPTHS
        @tremolo_shift = value.anybits?(DEEP_TREMOLO) ? DEEP_TREMOLO_SHIFT : Opl2::TREMOLO_SHIFT
        @vibrato_shift = value.anybits?(DEEP_VIBRATO) ? DEEP_VIBRATO_SHIFT : VIBRATO_SHIFT
      elsif register.between?(LOW_PITCH, LOW_PITCH + CHANNELS - 1)
        @channels[register - LOW_PITCH].low_pitch = value
      elsif register.between?(KEY, KEY + CHANNELS - 1)
        @channels[register - KEY].key = value
      elsif register.between?(CONNECTION, CONNECTION + CHANNELS - 1)
        @channels[register - CONNECTION].connection = value
      else
        write_operator(register, value)
      end
    end

    def write_operator(register, value)
      cell = CELLS[register & 0x1f] or return
      channel = @channels[cell / (OPERATORS_A_CHANNEL * 2) * OPERATORS_A_CHANNEL + (cell % OPERATORS_A_CHANNEL)]
      operator = cell % (OPERATORS_A_CHANNEL * 2) < OPERATORS_A_CHANNEL ? channel.modulator : channel.carrier
      case register & 0xe0
      when Opl2::CHAR_REGISTER then operator.char = value
      when Opl2::SCALE_REGISTER then operator.scale = value
      when Opl2::ATTACK_REGISTER then operator.attack = value
      when Opl2::SUSTAIN_REGISTER then operator.sustain = value
      when Opl2::WAVE_REGISTER then operator.wave = value
      end
    end

    # The tick's tremolo and vibrato, from how many steps have gone by.
    def start_tick
      count = (@steps / TREMOLO_STEPS) % (2 * Opl2::TREMOLO_PEAK)
      @tremor = (count < Opl2::TREMOLO_PEAK ? count : (2 * Opl2::TREMOLO_PEAK) - count) >> @tremolo_shift
      shape = VIBRATO_SHAPE[(@steps / VIBRATO_STEPS) & 7]
      @channels.each { |channel| channel.vibrate(shape, @vibrato_shift) }
    end

    # A sample's sum of steps scaled so the loudest is LOUDEST_SAMPLE, the dither added, rounded to
    # the nearest. A sum is held to the loudest first, which a copy louder than the one counted could
    # pass. Rounding is a shift, which takes a number below nought down as game code does. It can
    # come to no more than LOUDEST_SAMPLE + 1 either way, so it needs no clamp.
    def sample_of(sum)
      sum = sum.clamp(-@limit, @limit)
      noise = draw_dither - draw_dither
      ((sum * @scale) + noise + (1 << (SCALE_BITS - 1))) >> SCALE_BITS
    end

    def draw_dither
      @dither = ((@dither * DITHER_MULTIPLIER) + DITHER_INCREMENT) & DITHER_MASK
    end
  end
end
