# frozen_string_literal: true

module Wolf3D
  # WHICH COPIES OF THE GAME THIS BUILDS FROM: version 1.4 of the registered six episodes, in the
  # edition GOG sells, and version 1.4 of the shareware episode.
  #
  # Files with the right names are not enough. Much of what this game knows about the files is not
  # in the files: it is a number read off one release, like which picture is the status bar, where
  # the first guard starts, which recording is a scream, and all 256 colours. Spear of Destiny has
  # the same eight files with four more sprites before its first guard, which puts a marble pillar
  # where this game expects him. So a copy is asked first.
  #
  # THE SHAREWARE SHARES NEARLY ALL OF THIS WITH THE SIX EPISODES: the same walls, sprites, sounds
  # and colours, and fewer floors. What differs is its pictures, because Apogee's list has twelve
  # more help screens early in VGAGRAPH, so every number after those moves. Compare gfxv_apo.h with
  # gfxv_wl6.h in the original's source; version.h and wl_def.h say which build reads which.
  #
  # APOGEE'S SIX-EPISODE COPIES ARE REFUSED, though they may well read the same list. There is no
  # such copy to check that against, and a promise this game cannot test is not one it makes.
  #
  # IT PROBES RATHER THAN CHECKSUMS. These are the counts the numbers depend on, and the sizes of a
  # few pictures found by number, which a shuffled file gets wrong. A person's edited copy that keeps
  # every one of them passes, and may well work.
  #
  # A copy it refuses raises the framework's VBlank::Original::WrongCopy, which is how every game
  # made from an original says a copy will not do. It is GameData's probe, so the framework asks it
  # of every copy it finds.
  class Vanilla
    # WHAT A COPY OF EACH RELEASE HOLDS that the others do not. The walls, sprites and sounds below
    # are the same in all of them, which is what lets one game read them.
    Release = Data.define(:floors, :pictures)
    RELEASES = Ractor.make_shareable({ "WL6" => Release.new(60, 132), "WL1" => Release.new(10, 144) })

    # The extensions this game takes, for a message that has to name them.
    SETS = Ractor.make_shareable(RELEASES.keys.join(" or "))

    # What to get, for every message that has to say so.
    NEEDED = Ractor.make_shareable(
      "This game can use only two releases of Wolfenstein 3D, both version 1.4. " \
      "One is the registered six episodes (WL6), which GOG sells. " \
      "The other is the shareware episode (WL1), which is a free download."
    )

    # WHERE THE OTHER GAME'S FILES USUALLY ARE IN RELATION TO THESE, for a copy that has both.
    NEARBY = Ractor.make_shareable(
      { "SOD" => "In the GOG release, the WL6 files are one directory above the Spear of Destiny files." }
    )

    # One thing to ask of a copy: the file that holds the answer, what it is asked in words, the
    # answer, and where to read what this copy says.
    Probe = Data.define(:file, :asked, :wanted, :found)

    # THE FILES IN +game_data+, read here so that a file cut short is a refusal like any other. What
    # goes wrong inside a reader is whatever a bad byte happened to reach, so it is not asked which.
    def self.check_files!(game_data)
      check!(set: game_data.set, dir: game_data.dir, maps: Maps.from(game_data),
             vswap: Vswap.from(game_data), vgagraph: Vgagraph.from(game_data))
    rescue VBlank::Original::WrongCopy
      raise
    rescue StandardError
      raise VBlank::Original::WrongCopy, unreadable(game_data.set, game_data.dir)
    end

    # Says nothing about a copy this game can use. WrongCopy says why about any other. +maps+, +vswap+
    # and +vgagraph+ are the copy's files as read, and +dir+ is where they came from.
    def self.check!(set:, dir:, maps:, vswap:, vgagraph:)
      release = RELEASES.fetch(set) { raise VBlank::Original::WrongCopy, other_release(set, dir) }

      probes(release, maps, vswap, vgagraph).each do |probe|
        got = probe.found.call
        raise VBlank::Original::WrongCopy, changed_copy(set, dir, probe, got) unless got == probe.wanted
      end
      nil
    end

    # In this order, so a picture is asked for by number only once there are the right number of them.
    def self.probes(release, maps, vswap, vgagraph)
      [Probe.new("GAMEMAPS", "the number of floors", release.floors, -> { maps.count }),
       Probe.new("VSWAP", "the number of walls", 106, -> { vswap.wall_count }),
       Probe.new("VSWAP", "the number of sprites", 436, -> { vswap.sprite_count }),
       Probe.new("VSWAP", "the number of sounds", 46, -> { vswap.sound_count }),
       Probe.new("VGAGRAPH", "the number of pictures", release.pictures, -> { vgagraph.picture_count }),
       Probe.new("VGAGRAPH", "the size of the status bar", "320x40", -> { size_of(vgagraph, :status_bar) }),
       Probe.new("VGAGRAPH", "the size of the first face", "24x32", -> { size_of(vgagraph, :face_1a) }),
       Probe.new("VGAGRAPH", "the size of the first numeral", "8x16", -> { size_of(vgagraph, :digit_0) })]
    end
    private_class_method :probes

    def self.size_of(vgagraph, name) = vgagraph.size(name).join("x")
    private_class_method :size_of

    def self.other_release(set, dir)
      <<~TEXT
        The files in #{dir} are #{GameData::SETS.fetch(set, set)} (#{set}).

        #{NEEDED}
        To fix this, set #{GameData::ENV_VAR} or #{GameData::CONFIG_FILE} to the directory that has the #{SETS} files.
        #{NEARBY[set]}
      TEXT
    end
    private_class_method :other_release

    def self.changed_copy(set, dir, probe, got)
      <<~TEXT
        The #{set} files in #{dir} are not files this game can use.

        In #{probe.file}, #{probe.asked} must be #{probe.wanted}. In this copy it is #{got}.

        #{NEEDED} Apogee's six episodes and changed files do not work.
        To fix this, set #{GameData::ENV_VAR} or #{GameData::CONFIG_FILE} to the directory that has those files.
      TEXT
    end
    private_class_method :changed_copy

    def self.unreadable(set, dir)
      <<~TEXT
        This game cannot read the #{set} files in #{dir}. They are damaged or changed.

        #{NEEDED}
        To fix this, set #{GameData::ENV_VAR} or #{GameData::CONFIG_FILE} to the directory that has those files.
      TEXT
    end
    private_class_method :unreadable
  end
end
