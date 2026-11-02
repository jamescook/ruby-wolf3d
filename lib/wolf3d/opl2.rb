# frozen_string_literal: true

module Wolf3D
  # THE ADLIB CARD'S CHIP, THE YAMAHA YM3812, FOR AS MUCH OF IT AS A SOUND EFFECT USES. Written from
  # the chip's data sheet. It runs while the cartridge is built, and what it writes is a recording,
  # so nothing on the cartridge knows what FM synthesis is.
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
  # NOT HERE: rhythm mode and the percussion, which no effect uses, and the feedback and additive
  # connection, which this driver never turns on.
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
    MOST_TAIL_SECONDS = 0.5

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

    # The loudest a sample is written, with room for the two operators' rounding.
    FULL_SAMPLE = 127

    # Below this it counts as having stopped, about the last bit of an eight-bit sample.
    QUIET_DECIBELS = 48.0

    # ONE OF THE TWO SINE WAVES, and its envelope.
    class Oscillator
      TURN = 2 * Math::PI

      attr_reader :stage

      def initialize(operator)
        @char = operator.char
        @level = operator.scale & 0x3f
        @key_scale = operator.scale >> 6
        @attack = operator.attack >> 4
        @decay = operator.attack & 0x0f
        sustain_level = operator.sustain >> 4
        @sustain_decibels = (sustain_level == LOWEST_SUSTAIN_LEVEL ? LOWEST_SUSTAIN_STEPS : sustain_level) * SUSTAIN_STEP_DECIBELS
        @release = operator.sustain & 0x0f
        @wave = operator.wave & 3
        @phase = 0.0
        @decibels = SILENT_DECIBELS
        @stage = :off
      end

      def multiple = MULTIPLES[@char & 0x0f]
      def tremolo? = @char.anybits?(0x80)
      def vibrato? = @char.anybits?(0x40)
      def holds_sustain? = @char.anybits?(0x20)
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
        @hertz = fnum * NATIVE_RATE * (2.0**(block - 20)) * multiple
        @key_code = (block * 2) + (fnum >> 9 & 1)
        @rate_offset = scales_rate_by_key? ? @key_code : @key_code >> 2
        octave_cut = KEY_SCALE_DECIBELS[fnum >> 6] - (3.0 * (7 - block))
        @scale_decibels = [octave_cut, 0.0].max * KEY_SCALE_SHARES[@key_scale]
      end

      # One of the chip's samples. +modulation+ is in cycles. +wobble+ is the slow shift of pitch and
      # +tremor+ the slow loss of level, both for this moment.
      def step(modulation, wobble, tremor)
        move_envelope
        pitch = @hertz * (vibrato? ? 1.0 + wobble : 1.0)
        @phase = (@phase + (pitch / NATIVE_RATE)) % 1.0
        loss = @decibels + (@level * LEVEL_STEP_DECIBELS) + @scale_decibels + (tremolo? ? tremor : 0.0)
        wave_at(@phase + modulation) * (10.0**(-loss / 20))
      end

      def quiet? = @stage == :off || @decibels + (@level * LEVEL_STEP_DECIBELS) >= QUIET_DECIBELS

      private

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
        when :decay then fall_to(@sustain_decibels, @decay) { @stage = :sustain }
        when :sustain then fall_to(SILENT_DECIBELS, @release) { @stage = :off } unless holds_sustain?
        when :release then fall_to(SILENT_DECIBELS, @release) { @stage = :off }
        end
      end

      # An attack climbs in amplitude and not in decibels, so it is heard from its first moments.
      def rise
        return if @attack_seconds.infinite?

        @attack_elapsed += 1.0 / NATIVE_RATE
        amplitude = @attack_elapsed / @attack_seconds
        @decibels = amplitude >= 1.0 ? 0.0 : -20 * Math.log10(amplitude)
        @stage = :decay if amplitude >= 1.0
      end

      def fall_to(floor, register)
        return yield if @decibels >= floor

        span = seconds(SLOWEST_DECAY_SECONDS, register)
        return if span.infinite?

        @decibels += SILENT_DECIBELS / (span * NATIVE_RATE)
        yield if @decibels >= floor
      end

      # A setting of nought never moves at all.
      def seconds(slowest, register)
        return Float::INFINITY if register.zero?

        rate = (register * 4) + @rate_offset
        slowest / (2.0**((rate - SLOWEST_RATE) / RATE_STEPS_TO_HALVE))
      end
    end

    # EFFECT TO SAMPLES: signed bytes at RENDER_RATE, ending when the sound does.
    def self.render(effect) = new(effect).render

    def initialize(effect)
      @block = effect.block & 7
      @notes = effect.notes
      @modulator = Oscillator.new(effect.instrument.modulator)
      @carrier = Oscillator.new(effect.instrument.carrier)
      @clock = 0
      @out = []
    end

    def render
      @notes.each do |note|
        key_note(note)
        play_tick
      end
      key_off_both
      play_tail
      @out.pop while @out.last&.zero?
      @out
    end

    private

    def key_note(note)
      return key_off_both if note.zero?

      fnum = note
      [@modulator, @carrier].each { |oscillator| oscillator.key_on(@block, fnum) }
    end

    def key_off_both = [@modulator, @carrier].each(&:key_off)

    def play_tick = NATIVE_SAMPLES_PER_TICK.times { play_sample }

    def play_tail
      (NATIVE_RATE * MOST_TAIL_SECONDS).to_i.times do
        break if @carrier.quiet?

        play_sample
      end
    end

    def play_sample
      time = @clock.to_f / NATIVE_RATE
      wobble = VIBRATO_DEPTH * Math.sin(2 * Math::PI * VIBRATO_HERTZ * time)
      tremor = TREMOLO_DECIBELS * (1 + Math.sin(2 * Math::PI * TREMOLO_HERTZ * time)) / 2
      bend = @modulator.stage == :off ? 0.0 : @modulator.step(0.0, wobble, tremor) * FULL_MODULATION_CYCLES
      sample = @carrier.stage == :off ? 0.0 : @carrier.step(bend, wobble, tremor)
      collect(sample)
    end

    def collect(sample)
      @clock += 1
      @sum = @sum.to_f + sample
      return unless (@clock % RATE_DIVIDER).zero?

      @out << (@sum / RATE_DIVIDER * FULL_SAMPLE).round.clamp(-128, 127)
      @sum = 0.0
    end
  end
end
