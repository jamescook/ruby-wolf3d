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

    LENGTH_BYTES = 2
    WRITE_BYTES = 4

    # (audiowl6.h) LASTMUSIC: how many tracks the original names.
    TRACKS = 27

    # EACH TRACK'S TWO NUMBERS, by its number, counted off the six episodes and the shareware with
    # tools/count_music.rb (the original's source says neither; both releases keep the same tracks,
    # the shareware fewer of them). TICKS is how long it runs, which a data pack sizes its room by;
    # LOUDEST how far from nought its loudest step goes, which a recording is scaled by
    # (Opl2Track.loudest). They are the chip's as it is: a change to what Opl2::Operator or Opl2Track
    # plays is counted again.
    TICKS = [42_893, 46_443, 47_777, 56_026, 41_853, 45_921, 57_410, 40_400, 40_474, 45_593, 7568, 45_997, 80_421,
             45_774, 49_609, 38_633, 14_095, 56_288, 50_705, 55_779, 57_728, 48_472, 80_381, 13_248, 14_153, 46_344,
             60_425].freeze
    LOUDEST = [2324, 3739, 13_483, 4096, 4645, 1424, 5068, 2699, 2041, 3183, 5940, 5799, 4816, 1714, 4510, 6086, 5247,
               5459, 3477, 5399, 7158, 4709, 2934, 3945, 3425, 6908, 4405].freeze

    # Where a recording is kept once made, under the game's own folder.
    RECORDINGS_DIR = "tmp/music"

    def self.from(game_data) = new(head: game_data.read("AUDIOHED"), audio: game_data.read("AUDIOT"))

    def initialize(head:, audio:)
      @offsets = head.unpack("V*")
      @audio = audio
    end

    # Track +number+ as [register, value, ticks to wait] writes, empty when this copy has none. A log
    # running past the end of AUDIOT, which only a damaged copy has, is cut to the writes there.
    def writes(number)
      from = @offsets[FIRST_CHUNK + number]
      return [] if from.nil? || FIRST_CHUNK + number + 1 >= @offsets.length || from + LENGTH_BYTES > @audio.bytesize

      count = [@audio.byteslice(from, LENGTH_BYTES).unpack1("v"), @audio.bytesize - from - LENGTH_BYTES].min / WRITE_BYTES
      @audio.byteslice(from + LENGTH_BYTES, count * WRITE_BYTES).unpack("CCv" * count).each_slice(3).to_a
    end

    # Track +number+ played through the chip at +rate+ samples a second, as a byte String of signed
    # samples. Kept on disk, named for the writes, the rate and the code that plays them, so a change
    # to any of them makes it again. It is written to one side and moved in, so builds running at
    # once never read half of one.
    def recording(number, rate:)
      path = File.join(Wolf3D.home, RECORDINGS_DIR, "#{Digest::SHA256.hexdigest(fingerprint(number, rate))}.pcm")
      return File.binread(path) if File.exist?(path)

      pcm = Opl2Track.render(writes(number), rate: rate, loudest: LOUDEST[number]).pack("c*")
      FileUtils.mkdir_p(File.dirname(path))
      unfinished = "#{path}.#{Process.pid}.#{Ractor.current.object_id}"
      File.binwrite(unfinished, pcm)
      File.rename(unfinished, path)
      pcm
    end

    private

    def fingerprint(number, rate)
      code = %w[opl2 opl2_track adlib_music].map { |file| File.read(File.join(__dir__, "#{file}.rb")) }
      [writes(number).inspect, rate, *code].join
    end
  end
end
