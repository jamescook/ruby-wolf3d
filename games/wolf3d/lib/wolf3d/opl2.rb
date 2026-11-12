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
  # its top three bits, and an effect's pitch is one byte, so they are always nought. The music
  # uses all three, and Opl2Track is all nine channels, made of this file's Operator.
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
    # sample. A clock's fall is what one sample of a decay or a release adds at each of the chip's
    # 64 rates, and nought where the rate never moves. The slowest that moves, rate 4, takes 39.28
    # seconds to fall right down, and each four rates halve that.
    ENVELOPE_BITS = 20
    SLOWEST_DECAY_SECONDS = 39.28
    SLOWEST_RATE = 4
    RATES = 64

    # AN ATTACK CLIMBS IN AMPLITUDE and not in decibels, so it is heard from its first moments:
    # a count runs from nought to ATTACK_FULL, a clock's rise a sample (rate 4 takes 2.826 seconds),
    # and its top eight bits pick the loss that amplitude is.
    ATTACK_BITS = 28
    ATTACK_FULL = 1 << ATTACK_BITS
    ATTACK_PLACE_BITS = 20
    SLOWEST_ATTACK_SECONDS = 2.826

    # A place in a cycle moves by the pitch times a clock's phase ratio, out of 1 << PHASE_RATIO_BITS.
    PHASE_RATIO_BITS = 10

    # HOW OFTEN AN OPERATOR IS STEPPED, and what that makes of its tables. The chip steps at
    # NATIVE_RATE, which is what the effects use. The music steps at the rate it is written at, so
    # it moves further each step: by +phase_ratio+ out of 1 << PHASE_RATIO_BITS, and its envelope by
    # its own +fall+ and +rise+ for each rate.
    Clock = Data.define(:phase_ratio, :fall, :rise)

    def self.clock(rate)
      Clock.new(
        phase_ratio: ((NATIVE_RATE.to_f / rate) * (1 << PHASE_RATIO_BITS)).round,
        fall: envelope_steps((SILENT + 1) << ENVELOPE_BITS, SLOWEST_DECAY_SECONDS, rate),
        rise: envelope_steps(ATTACK_FULL, SLOWEST_ATTACK_SECONDS, rate)
      )
    end

    # What one step at +rate+ moves an envelope that crosses +span+ in +slowest_seconds+ at rate 4,
    # for each of the 64 rates.
    def self.envelope_steps(span, slowest_seconds, rate)
      (0...RATES).map do |chip_rate|
        next 0 if chip_rate < SLOWEST_RATE

        (span / (slowest_seconds * rate) * (2.0**((chip_rate - SLOWEST_RATE) / 4.0))).round
      end
    end

    NATIVE_CLOCK = Ractor.make_shareable(clock(NATIVE_RATE))
    FALL = NATIVE_CLOCK.fall
    RISE = NATIVE_CLOCK.rise
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

    # AN OPERATOR'S FIVE REGISTERS, by the top bits of the register's number. The cell below them
    # says which operator (Opl2Track::CELLS).
    CHAR_REGISTER = 0x20
    SCALE_REGISTER = 0x40
    ATTACK_REGISTER = 0x60
    SUSTAIN_REGISTER = 0x80
    WAVE_REGISTER = 0xe0

    # The stages of an envelope.
    OFF = 0
    ATTACK = 1
    DECAY = 2
    SUSTAIN = 3
    RELEASE = 4

    # Seven samples at full wave, which a written sample is a share of, out of FULL_SAMPLE.
    FULL_SUM = RATE_DIVIDER * FULL_WAVE
    FULL_SAMPLE = 127

    # ONE OF THE TWO SINE WAVES, and its envelope. It starts with every register nought and its key
    # up. A write to any of its five registers, or a new pitch, settles at once what the operator
    # keeps for its steps: how far a step moves it, how fast it rises and falls, the loss its key
    # scaling takes. The music writes them while a note sounds; an effect, once before its notes.
    class Operator
      attr_reader :stage

      # +clock+ is how often #step is called (Opl2.clock).
      def initialize(clock)
        @clock = clock
        @block = 0
        @fnum = 0
        @doubled_multiple = DOUBLED_MULTIPLES[0]
        @key_scale_rate = 0
        @holds_sustain = 0
        @vibrato = 0
        @tremolo = 0
        @level = 0
        @key_scale = 0
        @attack = 0
        @decay = 0
        @sustain = 0
        @release = 0
        @wave = 0
        @stage = OFF
        @loss = SILENT << ENVELOPE_BITS
        @risen = 0
        @phase = 0
        retune
      end

      # The five registers of +registers+ (AdlibSounds::Operator), as an instrument sets them.
      def load(registers)
        self.char = registers.char
        self.scale = registers.scale
        self.attack = registers.attack
        self.sustain = registers.sustain
        self.wave = registers.wave
      end

      # Register 0x20: tremolo, vibrato, whether the sustain holds, whether the rates scale by the
      # key, and the multiple.
      def char=(value)
        @tremolo = (value >> 7) & 1
        @vibrato = (value >> 6) & 1
        @holds_sustain = (value >> 5) & 1
        @key_scale_rate = (value >> 4) & 1
        @doubled_multiple = DOUBLED_MULTIPLES[value & 0x0f]
        retune
      end

      # Register 0x40: the key scaling of the level, and the level, four steps to each of its 64.
      def scale=(value)
        @key_scale = value >> 6
        @level = (value & 0x3f) * LEVEL_STEPS
        retune
      end

      # Register 0x60: the attack and decay rates.
      def attack=(value)
        @attack = value >> 4
        @decay = value & 0x0f
        retune
      end

      # Register 0x80: the sustain level, sixteen steps to each of its 16, the last nearly silence,
      # and the release rate.
      def sustain=(value)
        level = value >> 4
        @sustain = (level == LOWEST_SUSTAIN_LEVEL ? LOWEST_SUSTAIN : level * SUSTAIN_STEPS) << ENVELOPE_BITS
        @release = value & 0x0f
        retune
      end

      # Register 0xE0: which of the four shapes.
      def wave=(value)
        @wave = value & 3
      end

      # The channel's pitch: its block (the octave) and its ten bits of fnum.
      def tune(block, fnum)
        @block = block
        @fnum = fnum
        retune
      end

      # A key already down keeps its envelope, which is why a run of notes is one long sound.
      def key_on
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

      # THE CHIP'S SLOW WOBBLE OF PITCH, for an operator whose vibrato is on: the pitch moved by its
      # top three bits times +shape+, shifted down by +shift+, until the next retune or wobble.
      def vibrate(shape, shift)
        @step = phase_step(@fnum + (((@fnum >> 7) * shape) >> shift)) if @vibrato == 1
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

      # What a register or the pitch settles. The key code is the block and the top bit of the
      # pitch, and a rate goes up by all of it where the rates scale by the key, or by its top two
      # bits where they do not.
      def retune
        @step = phase_step(@fnum)
        key_code = (@block * 2) | ((@fnum >> 9) & 1)
        offset = @key_scale_rate == 1 ? key_code : key_code >> 2
        @rise = @clock.rise[rate(@attack, offset)]
        @decay_fall = @clock.fall[rate(@decay, offset)]
        @release_fall = @clock.fall[rate(@release, offset)]
        @scale_loss = scale_loss
      end

      # How far a step moves the place in the cycle at +fnum+: fnum shifted up by the block, times
      # the clock's ratio, times the multiple.
      def phase_step(fnum)
        ((((fnum << @block) * @clock.phase_ratio) >> PHASE_RATIO_BITS) * @doubled_multiple) >> 1
      end

      # The chip's rate for a register's setting: four to a setting, and a little more the higher
      # the note. A setting of nought never moves at all.
      def rate(register, offset)
        return 0 if register.zero?

        [(register * 4) + offset, RATES - 1].min
      end

      def scale_loss
        cut = KEY_SCALE_LOSS[@fnum >> 6] - (KEY_SCALE_OCTAVE * (TOP_BLOCK - @block))
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
      @block = effect.block & 7
      @notes = effect.notes
      @modulator = operator_of(effect.instrument.modulator)
      @carrier = operator_of(effect.instrument.carrier)
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

    # The instrument's registers, at the effect's block, every rate settled by it alone: a pitch of
    # one byte never reaches the bit of fnum that would move them.
    def operator_of(registers)
      operator = Operator.new(NATIVE_CLOCK)
      operator.load(registers)
      operator.tune(@block, 0)
      operator
    end

    def key_note(note)
      count = (@clock / TREMOLO_SAMPLES) % (2 * TREMOLO_PEAK)
      @tremor = (count < TREMOLO_PEAK ? count : (2 * TREMOLO_PEAK) - count) >> TREMOLO_SHIFT
      return key_off_both if note.zero?

      [@modulator, @carrier].each do |operator|
        operator.tune(@block, note)
        operator.key_on
      end
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
