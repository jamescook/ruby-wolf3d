# frozen_string_literal: true

module Wolf3D
  # THE SOUND EFFECTS THAT ARE RECIPES RATHER THAN RECORDINGS, read from AUDIOT.
  #
  # AUDIOHED is a list of four-byte offsets into AUDIOT, one for each chunk and one for the end. The
  # chunks come in runs: every sound for the PC speaker, then every sound for the AdLib card, then
  # the digitised ones' placeholders, then the music. So an effect's number is the same in each run.
  #
  # AN ADLIB EFFECT is six bytes of length and priority, a sixteen-byte instrument, a byte saying
  # which octave it plays in, and then one byte for each 1/140 of a second: the pitch sounding then,
  # or nought for silence. Opl2 turns that into samples.
  class AdlibSounds
    # How many sounds there are, which is where the AdLib run begins (audiowl6.h).
    FIRST_CHUNK = 87

    # The bytes before an effect's notes.
    HEADER_BYTES = 23

    # The chip's five registers for one of the two sine waves in a sound.
    Operator = Data.define(:char, :scale, :attack, :sustain, :wave)

    # +modulator+ bends the pitch of +carrier+, and +carrier+ is what is heard.
    Instrument = Data.define(:modulator, :carrier)

    Effect = Data.define(:priority, :instrument, :block, :notes)

    # An effect as the cartridge holds it: samples, and how many a second.
    Recording = Data.define(:pcm, :rate, :priority)

    def self.from(game_data) = new(head: game_data.read("AUDIOHED"), audio: game_data.read("AUDIOT"))

    def initialize(head:, audio:)
      @offsets = head.unpack("V*")
      @audio = audio
    end

    # Effect +number+, or nil when this copy has none.
    def effect(number)
      chunk = FIRST_CHUNK + number
      return if chunk + 1 >= @offsets.length

      from = @offsets[chunk]
      return if @offsets[chunk + 1] - from < HEADER_BYTES

      effect_at(from)
    end

    # Effect +number+ played through the chip, or nil when this copy has none or it makes no sound.
    # Kept, because a build asks more than once and working one out takes a while.
    def recording(number)
      @recordings ||= {}
      return @recordings[number] if @recordings.key?(number)

      found = effect(number)
      pcm = found && Opl2.render(found)
      @recordings[number] = pcm && !pcm.empty? ? Recording.new(pcm: pcm, rate: Opl2::RENDER_RATE, priority: found.priority) : nil
    end

    private

    def effect_at(from)
      length, priority = @audio.byteslice(from, 6).unpack("Vv")
      bytes = @audio.byteslice(from + 6, 16).unpack("C*")
      Effect.new(priority: priority, instrument: instrument_from(bytes), block: @audio.getbyte(from + 22),
                 notes: @audio.byteslice(from + HEADER_BYTES, length).unpack("C*"))
    end

    # The bytes go in pairs, modulator then carrier, for each of the five registers.
    def instrument_from(bytes)
      modulator, carrier = [0, 1].map do |side|
        char, scale, attack, sustain, wave = (0...5).map { |register| bytes[(register * 2) + side] }
        Operator.new(char: char, scale: scale, attack: attack, sustain: sustain, wave: wave)
      end
      Instrument.new(modulator: modulator, carrier: carrier)
    end
  end
end
