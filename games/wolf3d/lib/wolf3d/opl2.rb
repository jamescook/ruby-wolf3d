# frozen_string_literal: true

module Wolf3D
  # THE ADLIB CARD'S CHIP, THE YAMAHA YM3812, ONE CHANNEL OF IT, WHICH IS WHAT A SOUND EFFECT USES.
  # Written from the chip's data sheet, IN WHOLE NUMBERS AND TABLES, as the chip itself works.
  #
  # IT IS WRITTEN TWICE, and the two must make the same samples. This one is plain Ruby, and plays
  # an effect while a trimmed build is made. AdlibUnpacking is the same arithmetic as game code,
  # which a whole build runs on the player's machine at LOAD ROM, where there are no floats. So
  # every step here is one the game's numbers can take: adds, shifts, table reads, and no division
  # of a number that can be below nought. The tables are worked out here, with floats, once, and
  # both read them. test_floor_unpacking holds the two to each other for every effect of both
  # releases.
  #
  # A SOUND IS TWO SINE WAVES. The carrier is what you hear. The modulator is not heard at all: its
  # output is added to the carrier's place in its cycle, which bends the shape of the wave and gives
  # a note its colour. Each one has an envelope, which is how loud it is over time: up at the attack
  # rate, down at the decay rate to the sustain level, and down at the release rate after the note
  # ends.
  #
  # THE EFFECTS DRIVE IT VERY SIMPLY (id_sd.cpp, SDL_ALPlaySound and the service routine). One channel,
  # the instrument's registers once, feedback nought whatever the instrument says, and then every
  # 1/140 of a second a byte: the low part of the pitch, with the key held down, or nought to let go.
  # The high part of the pitch never changes, so the block is the octave of the whole effect.
  #
  # NOT HERE: rhythm mode and the percussion, which no effect uses; the feedback and additive
  # connection, which this driver never turns on; and vibrato, which on the chip moves a pitch by
  # its top three bits, and an effect's pitch is one byte, so they are always nought.
  class Opl2
    # The chip's own sample rate, and a seventh of it, which is about the rate of the recordings in
    # VSWAP. Each sample written is seven of the chip's, averaged, which keeps out the high notes
    # that would fold back down as noise.
    NATIVE_RATE = 49_716
    RATE_DIVIDER = 7
    RENDER_RATE = NATIVE_RATE / RATE_DIVIDER

    TICKS_PER_SECOND = 140
    NATIVE_SAMPLES_PER_TICK = NATIVE_RATE / TICKS_PER_SECOND

    # A note ends and its release may still be sounding. Half a second is more than any effect's.
    TAIL_SAMPLES = NATIVE_RATE / 2

    # A PLACE IN A CYCLE is 20 bits: the top ten pick one of SINE's 1024
    # places and the low ten are the fraction. A step moves it by the pitch shifted up by the
    # block, times the multiple, which is the data sheet's F = fnum * 49716 * 2^(block - 20).
    PHASE_MASK = (1 << 20) - 1
    PHASE_FRACTION_BITS = 10
    SINE_PLACES = 1024

    # One cycle of a sine, from -FULL_WAVE to FULL_WAVE, read at the middle of each place so the
    # second half is the first below nought and no place is nought.
    FULL_WAVE = 4095
    SINE = Ractor.make_shareable(
      (0...SINE_PLACES).map { |place| (Math.sin(2 * Math::PI * (place + 0.5) / SINE_PLACES) * FULL_WAVE).round }
    )

    # LOUDNESS IS KEPT AS LOSS, in the chip's own steps of 3/16 of a decibel: nought is full and
    # SILENT is 96 decibels down. GAIN turns a loss into what a wave is multiplied by, out of
    # 1 << GAIN_BITS. An operator's level is four steps to each of its 64 settings (0.75 decibels),
    # and its sustain sixteen to each of its 16 (3 decibels), the last of which is nearly silence.
    STEP_DECIBELS = 0.1875
    SILENT = 511
    GAIN_BITS = 12
    GAIN = Ractor.make_shareable((0..SILENT).map { |loss| ((1 << GAIN_BITS) * (10.0**(-loss * STEP_DECIBELS / 20))).round })
    LEVEL_STEPS = 4
    SUSTAIN_STEPS = 16
    LOWEST_SUSTAIN_LEVEL = 15
    LOWEST_SUSTAIN = 31 * SUSTAIN_STEPS

    # Below this it counts as having stopped, about the last bit of an eight-bit sample: 48 decibels.
    QUIET = 256

    # AN ENVELOPE'S LOSS HAS 20 MORE BITS BELOW ITS STEPS, so a slow decay can move a little on every
    # sample. FALL is what one sample of a decay or a release adds at each of the chip's 64 rates,
    # and nought where the rate never moves. The slowest that moves, rate 4, takes 39.28 seconds
    # to fall right down, and each four rates halve that.
    ENVELOPE_BITS = 20
    SLOWEST_DECAY_SECONDS = 39.28
    SLOWEST_RATE = 4
    RATES = 64
    FALL = Ractor.make_shareable(
      (0...RATES).map do |rate|
        next 0 if rate < SLOWEST_RATE

        (((SILENT + 1) << ENVELOPE_BITS) / (SLOWEST_DECAY_SECONDS * NATIVE_RATE) * (2.0**((rate - SLOWEST_RATE) / 4.0))).round
      end
    )

    # AN ATTACK CLIMBS IN AMPLITUDE and not in decibels, so it is heard from its first moments:
    # a count runs from nought to ATTACK_FULL, RISE a sample (rate 4 takes 2.826 seconds), and its
    # top eight bits pick the loss that amplitude is.
    ATTACK_BITS = 28
    ATTACK_FULL = 1 << ATTACK_BITS
    ATTACK_PLACE_BITS = 20
    SLOWEST_ATTACK_SECONDS = 2.826
    RISE = Ractor.make_shareable(
      (0...RATES).map do |rate|
        next 0 if rate < SLOWEST_RATE

        (ATTACK_FULL / (SLOWEST_ATTACK_SECONDS * NATIVE_RATE) * (2.0**((rate - SLOWEST_RATE) / 4.0))).round
      end
    )
    ATTACK_LOSS = Ractor.make_shareable(
      (0...256).map { |place| [(-20 * Math.log10((place + 0.5) / 256) / STEP_DECIBELS).round, SILENT].min }
    )
    FASTEST_REGISTER = 15

    # Twice the multiple of the pitch each of the sixteen settings gives, the first being a half.
    # The repeats are the chip's.
    DOUBLED_MULTIPLES = Ractor.make_shareable([1, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 20, 24, 24, 30, 30])

    # Loss taken off the top octave, by the top four bits of the pitch: the table in the manual, in
    # steps. It falls by three decibels, sixteen steps, for each block below the top one, and the
    # two bits of key scaling take all of it, a half, a quarter or none.
    KEY_SCALE_LOSS = Ractor.make_shareable([0, 48, 64, 74, 80, 86, 90, 94, 96, 100, 102, 104, 106, 108, 110, 112])
    KEY_SCALE_OCTAVE = 16
    TOP_BLOCK = 7

    # Tremolo is the chip's own slow loss of level: a count that moves every 64 samples, up to 105
    # and back, a sixteenth of which is the loss, at the shallow setting since the driver leaves
    # that register at nought. Read once a tick here.
    TREMOLO_SAMPLES = 64
    TREMOLO_PEAK = 105
    TREMOLO_SHIFT = 4

    # The stages of an envelope.
    OFF = 0
    ATTACK = 1
    DECAY = 2
    SUSTAIN = 3
    RELEASE = 4

    # Seven samples at full wave, which a written sample is a share of, out of FULL_SAMPLE.
    FULL_SUM = RATE_DIVIDER * FULL_WAVE
    FULL_SAMPLE = 127

    # ONE OF THE TWO SINE WAVES, and its envelope.
    class Operator
      attr_reader :stage

      # +operator+ is the five registers (AdlibSounds::Operator) and +block+ the effect's octave,
      # which with a pitch of one byte settles every rate for the whole effect.
      def initialize(operator, block)
        @block = block
        @doubled_multiple = DOUBLED_MULTIPLES[operator.char & 0x0f]
        @tremolo = (operator.char >> 7) & 1
        @holds_sustain = (operator.char >> 5) & 1
        @level = (operator.scale & 0x3f) * LEVEL_STEPS
        @key_scale = operator.scale >> 6
        @wave = operator.wave & 3
        offset = (operator.char >> 4) & 1 == 1 ? block * 2 : (block * 2) >> 2
        @attack = operator.attack >> 4
        @rise = RISE[rate(@attack, offset)]
        @decay_fall = FALL[rate(operator.attack & 0x0f, offset)]
        @release_fall = FALL[rate(operator.sustain & 0x0f, offset)]
        sustain = operator.sustain >> 4
        @sustain = (sustain == LOWEST_SUSTAIN_LEVEL ? LOWEST_SUSTAIN : sustain * SUSTAIN_STEPS) << ENVELOPE_BITS
        @stage = OFF
        @loss = SILENT << ENVELOPE_BITS
        @risen = 0
        @phase = 0
        @step = 0
        @scale_loss = 0
      end

      # A key already down keeps its envelope, which is why a run of notes is one long sound.
      def key_on(fnum)
        @step = ((fnum << @block) * @doubled_multiple) >> 1
        @scale_loss = scale_loss(fnum)
        return if @stage == ATTACK || @stage == DECAY || @stage == SUSTAIN

        @risen = 0
        if @attack == FASTEST_REGISTER
          @stage = DECAY
          @loss = 0
        else
          @stage = ATTACK
        end
      end

      def key_off
        @stage = RELEASE unless @stage == OFF
      end

      # One of the chip's samples, from -FULL_WAVE to FULL_WAVE. +bend+ is in SINE's places, and
      # +tremor+ the slow loss of level for this moment.
      def step(bend, tremor)
        move_envelope
        @phase = (@phase + @step) & PHASE_MASK
        loss = (@loss >> ENVELOPE_BITS) + @level + @scale_loss
        loss += tremor if @tremolo == 1
        loss = SILENT if loss > SILENT
        (wave_at(((@phase >> PHASE_FRACTION_BITS) + bend) & (SINE_PLACES - 1)) * GAIN[loss]) >> GAIN_BITS
      end

      def quiet? = @stage == OFF || (@loss >> ENVELOPE_BITS) + @level >= QUIET

      private

      # The chip's rate for a register's setting: four to a setting, and a little more the higher
      # the note. A setting of nought never moves at all.
      def rate(register, offset)
        return 0 if register.zero?

        [(register * 4) + offset, RATES - 1].min
      end

      def scale_loss(fnum)
        cut = KEY_SCALE_LOSS[fnum >> 6] - (KEY_SCALE_OCTAVE * (TOP_BLOCK - @block))
        cut = 0 if cut.negative?
        case @key_scale
        when 0 then 0
        when 1 then cut >> 1
        when 2 then cut >> 2
        else cut
        end
      end

      # The four shapes: a sine, its upper half, both halves upward, and the first quarter of each
      # half. SINE's second half is its first below nought.
      def wave_at(place)
        half = SINE_PLACES / 2
        case @wave
        when 0 then SINE[place]
        when 1 then place < half ? SINE[place] : 0
        when 2 then SINE[place & (half - 1)]
        else (place & (half / 2)).zero? ? SINE[place & (half - 1)] : 0
        end
      end

      def move_envelope
        case @stage
        when ATTACK then rise
        when DECAY then @stage = SUSTAIN if fallen_to?(@sustain, @decay_fall)
        when SUSTAIN then @stage = OFF if @holds_sustain.zero? && fallen_to?(SILENT << ENVELOPE_BITS, @release_fall)
        when RELEASE then @stage = OFF if fallen_to?(SILENT << ENVELOPE_BITS, @release_fall)
        end
      end

      def rise
        return if @rise.zero?

        @risen += @rise
        if @risen >= ATTACK_FULL
          @loss = 0
          @stage = DECAY
        else
          @loss = ATTACK_LOSS[@risen >> ATTACK_PLACE_BITS] << ENVELOPE_BITS
        end
      end

      # One sample down toward +floor+, by +fall+: whether the loss has got there.
      def fallen_to?(floor, fall)
        return true if @loss >= floor

        @loss += fall
        @loss >= floor
      end
    end

    # EFFECT TO SAMPLES: signed bytes at RENDER_RATE, ending when the sound does.
    def self.render(effect) = new(effect).render

    def initialize(effect)
      block = effect.block & 7
      @notes = effect.notes
      @modulator = Operator.new(effect.instrument.modulator, block)
      @carrier = Operator.new(effect.instrument.carrier, block)
      @clock = 0
      @sum = 0
      @tremor = 0
      @out = []
    end

    def render
      @notes.each do |note|
        key_note(note)
        NATIVE_SAMPLES_PER_TICK.times { play_sample }
      end
      key_off_both
      TAIL_SAMPLES.times do
        break if @carrier.quiet?

        play_sample
      end
      @out.pop while @out.last&.zero?
      @out
    end

    private

    def key_note(note)
      count = (@clock / TREMOLO_SAMPLES) % (2 * TREMOLO_PEAK)
      @tremor = (count < TREMOLO_PEAK ? count : (2 * TREMOLO_PEAK) - count) >> TREMOLO_SHIFT
      return key_off_both if note.zero?

      @modulator.key_on(note)
      @carrier.key_on(note)
    end

    def key_off_both
      @modulator.key_off
      @carrier.key_off
    end

    def play_sample
      bend = @modulator.stage == OFF ? 0 : @modulator.step(0, @tremor)
      @sum += @carrier.stage == OFF ? 0 : @carrier.step(bend, @tremor)
      @clock += 1
      return unless (@clock % RATE_DIVIDER).zero?

      @out << sample_of(@sum)
      @sum = 0
    end

    # The seven samples' average out of FULL_SAMPLE, to the nearest. The sum is lifted above
    # nought before it is divided, since game code and Ruby divide a number below nought
    # differently.
    def sample_of(sum) = ((((sum + FULL_SUM) * FULL_SAMPLE) + (FULL_SUM / 2)) / FULL_SUM) - FULL_SAMPLE
  end
end
