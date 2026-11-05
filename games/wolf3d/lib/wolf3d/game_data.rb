# frozen_string_literal: true

require "vblank/original/game"

module Wolf3D
  # YOUR COPY OF WOLFENSTEIN 3D: the folder its files are in, and which release they are.
  #
  # Nothing here is redistributable, so the build reads files you already own. Point at them with
  # WOLF3D_DATA, or with a wolf3d.yml beside this game. Finding the folder those name, and refusing
  # it in words a person can act on, is the framework's (VBlank::Original::Game, made by
  # .original); what is Wolfenstein's is here and in Vanilla: what the folder must hold, and which
  # release it is.
  class GameData
    ENV_VAR = "WOLF3D_DATA"
    CONFIG_FILE = "wolf3d.yml"
    COPY_VAR = "WOLF3D_COPY"
    COPY_KEYS = %w[data shareware].freeze

    # A release is told apart by the extension its files carry. Finding one is not the same as being
    # able to use it: the build takes only the first two of these. See Vanilla.
    SETS = {
      "WL6" => "the registered six episodes",
      "WL1" => "the shareware episode",
      "SOD" => "Spear of Destiny",
      "SDM" => "the Spear of Destiny demo"
    }.freeze

    STEMS = %w[VSWAP GAMEMAPS MAPHEAD VGAGRAPH VGADICT VGAHEAD AUDIOT AUDIOHED].freeze

    attr_reader :dir, :set

    # WHERE YOUR COPY IS AND WHETHER IT WILL DO, asked the way every game made from an original asks
    # it. The setting wins over the file, and a relative path in the file is read from this game's
    # folder. A copy is accepted by what it holds: the files of one release, which Vanilla then
    # checks are the release this game was written against.
    #
    # +env+ is where the settings are looked up: the process's environment unless somebody hands
    # over their own, which is how a test points at a folder without changing it for everyone.
    # WOLF3D_COPY=shareware there reads the shareware line of the file in place of the data line.
    def self.original(home: Wolf3D.home, env: ENV)
      VBlank::Original::Game.new(
        title: "Wolfenstein 3D", setting: ENV_VAR, settings_file: File.join(home, CONFIG_FILE),
        key: copy_key(env), env: env, not_set_help: not_set_help,
        probe: ->(dir) { at(dir).tap { |data| Vanilla.check_files!(data) }.set }
      )
    end

    # The copy the settings name, checked. VBlank::Original::NotSet when nothing names one, and
    # VBlank::Original::WrongCopy when the one named will not do.
    def self.locate(home: Wolf3D.home, env: ENV)
      copy = original(home: home, env: env).copy
      new(dir: copy.path, set: copy.release)
    end

    # The same, or nil when nothing names a copy: what makes the holding screen.
    def self.locate_if_set(home: Wolf3D.home, env: ENV)
      locate(home: home, env: env)
    rescue VBlank::Original::NotSet
      nil
    end

    # The release in +dir+, as it is, without asking whether this game can use it: for a folder a
    # test wrote, or one the settings named, before Vanilla is asked.
    def self.at(dir)
      raise VBlank::Original::WrongCopy, "#{dir} is a file. Name the folder that holds your copy's files." unless File.directory?(dir)

      sets = complete_sets(dir)
      raise VBlank::Original::WrongCopy, no_files_message(dir) if sets.empty?
      raise VBlank::Original::WrongCopy, ambiguous_message(dir, sets) if sets.length > 1

      new(dir: dir, set: sets.first)
    end

    def initialize(dir:, set: nil)
      @dir = dir
      @set = set || self.class.at(dir).set
    end

    # The file for a stem, e.g. path("VSWAP"). Case is whatever the disk uses.
    def path(stem)
      found = self.class.file_in(@dir, stem, @set)
      raise VBlank::Original::WrongCopy, "#{stem}.#{@set} is not in #{@dir}." if found.nil?

      found
    end

    def read(stem) = File.binread(path(stem))

    def label = "#{SETS.fetch(@set, @set)} (#{@set})"

    def describe = "Found #{label} in #{@dir}."

    # Every file of +set+ that is in +dir+, matched without regard to case — the files are
    # upper-case on the original disks and often lower-case after a copy through another system.
    def self.file_in(dir, stem, set)
      Dir.children(dir).find { |name| name.casecmp?("#{stem}.#{set}") }
                       &.then { |name| File.join(dir, name) }
    rescue SystemCallError
      nil
    end

    def self.complete_sets(dir)
      SETS.keys.select { |set| STEMS.all? { |stem| file_in(dir, stem, set) } }
    end

    # WHICH LINE OF THE CONFIG FILE NAMES THE COPY. Two copies can sit there side by side, and
    # WOLF3D_COPY=shareware builds from the second.
    def self.copy_key(env)
      asked = env.fetch(COPY_VAR, nil).to_s
      return "data" if asked.empty?
      return asked if COPY_KEYS.include?(asked)

      raise VBlank::Original::WrongCopy, "#{COPY_VAR} is #{asked}. Set it to one of these: #{COPY_KEYS.join(', ')}."
    end

    # What the framework's message about a copy nobody named adds: what the folder must hold.
    def self.not_set_help
      "The folder must hold these files: #{STEMS.join(', ')}. Each one must end in #{Vanilla::SETS}. #{Vanilla::NEEDED}"
    end

    def self.no_files_message(dir)
      present = begin
        Dir.children(dir).sort.first(12)
      rescue SystemCallError
        []
      end
      <<~TEXT
        #{dir} holds no Wolfenstein 3D data.

        A complete release has all of these files: #{STEMS.join(', ')}.
        Each one ends in #{Vanilla::SETS} — for example VSWAP.WL6.

        #{present.empty? ? 'The folder is empty.' : "The folder holds: #{present.join(', ')}"}
      TEXT
    end

    def self.ambiguous_message(dir, sets)
      named = sets.map { |s| "#{s} (#{SETS.fetch(s, s)})" }.join(" and ")
      <<~TEXT
        #{dir} holds more than one release: #{named}.

        Point at one release. Put each in a folder of its own, or set #{ENV_VAR} to the
        folder that holds only the release you want.
      TEXT
    end
  end
end
