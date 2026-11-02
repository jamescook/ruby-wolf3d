# frozen_string_literal: true

module Wolf3D
  # THE MUSIC, read from AUDIOT. A track is not a recording. It is a log of what the game wrote to
  # the AdLib card: which register, what value, and how many ticks to wait before the next write. So
  # it is a good deal closer to a MIDI file than to sound, and Opl2Track plays it through the chip.
  #
  # AFTER THE THREE RUNS OF SOUND EFFECTS, which is what AdlibSounds reads, come the tracks. Each is
  # two bytes saying how long the log is, the log at four bytes a write, and then a few dozen bytes
  # of its composer's name and notes that nothing reads. The shareware keeps the slots of the tracks
  # it left out, each holding only those last bytes.
  class AdlibMusic
    # (audiowl6.h) STARTMUSIC is three times the number of sounds, and these are musicnames.
    FIRST_CHUNK = 3 * AdlibSounds::FIRST_CHUNK

    WRITE_BYTES = 4

    # Where a recording is kept once made, under the game's own folder.
    KEPT_IN = "tmp/music"

    def self.from(game_data) = new(head: game_data.read("AUDIOHED"), audio: game_data.read("AUDIOT"))

    def initialize(head:, audio:)
      @offsets = head.unpack("V*")
      @audio = audio
    end

    # Track +number+ as [register, value, ticks to wait] writes, empty when this copy has none.
    def writes(number)
      from = @offsets[FIRST_CHUNK + number]
      return [] if from.nil? || FIRST_CHUNK + number + 1 >= @offsets.length

      length = @audio.byteslice(from, 2).unpack1("v")
      @audio.byteslice(from + 2, length).unpack("CCv" * (length / WRITE_BYTES)).each_slice(3).to_a
    end

    # Track +number+ played through the chip, as a byte String of signed samples. Kept on disk,
    # named for the writes and for the code that plays them, so a change to either makes it again.
    # It is written to one side and moved in, so builds running at once never read half of one.
    def recording(number, renderer: Opl2Track)
      path = File.join(Wolf3D.home, KEPT_IN, "#{Digest::SHA256.hexdigest(fingerprint(number))}.pcm")
      return File.binread(path) if File.exist?(path)

      pcm = renderer.render(writes(number)).pack("c*")
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite("#{path}.#{Process.pid}.#{Ractor.current.object_id}", pcm)
      File.rename("#{path}.#{Process.pid}.#{Ractor.current.object_id}", path)
      pcm
    end

    private

    def fingerprint(number)
      code = %w[opl2 opl2_track].map { |file| File.read(File.join(__dir__, "#{file}.rb")) }
      [writes(number).inspect, *code].join
    end
  end
end
