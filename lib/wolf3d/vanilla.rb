# frozen_string_literal: true

module Wolf3D
  # WHICH COPY OF THE GAME THIS BUILDS FROM: the registered six episodes, version 1.4, in the edition
  # GOG sells, and only that.
  #
  # Files with the right names are not enough. Much of what this game knows about the files is not
  # in the files: it is a number read off one release, like which picture is the status bar, where
  # the first guard starts, which recording is a scream, and all 256 colours. Spear of Destiny has
  # the same eight files with four more sprites before its first guard, which puts a marble pillar
  # where this game expects him. So a copy is asked first.
  #
  # APOGEE'S SIX-EPISODE COPIES ARE REFUSED TOO, and that is not fussiness. Theirs is a different
  # list of pictures, with help screens early in VGAGRAPH, so every number after those is wrong
  # here. Compare gfxv_apo.h with gfxv_wl6.h in the original's source; version.h and wl_def.h say
  # which build reads which. This game knows the second list only.
  #
  # IT PROBES RATHER THAN CHECKSUMS. These are the counts the numbers depend on, and the sizes of a
  # few pictures found by number, which a shuffled file gets wrong. A person's edited copy that keeps
  # every one of them passes, and may well work.
  class Vanilla
    class Refused < GameData::NotFound; end

    SET = "WL6"

    # What to get, for every message that has to say so.
    NEEDED = Ractor.make_shareable("the registered six episodes of Wolfenstein 3D, version 1.4 (#{SET}), which GOG sells")

    # WHERE THE OTHER GAME'S FILES USUALLY ARE IN RELATION TO THESE, for a copy that has both.
    NEARBY = Ractor.make_shareable(
      { "SOD" => "In the GOG release, the #{SET} files are one directory above the Spear of Destiny files." }
    )

    # One thing to ask of a copy: the file that holds the answer, what it is asked in words, the
    # answer, and where to read what this copy says.
    Probe = Data.define(:file, :asked, :wanted, :found)

    # THE FILES IN +game_data+, read here so that a file cut short is a refusal like any other. What
    # goes wrong inside a reader is whatever a bad byte happened to reach, so it is not asked which.
    def self.check_files!(game_data)
      check!(set: game_data.set, dir: game_data.dir, maps: Maps.from(game_data),
             vswap: Vswap.from(game_data), vgagraph: Vgagraph.from(game_data))
    rescue Refused
      raise
    rescue StandardError
      raise Refused, unreadable(game_data.set, game_data.dir)
    end

    # Says nothing about a copy this game can use. Refused says why about any other. +maps+, +vswap+
    # and +vgagraph+ are the copy's files as read, and +dir+ is where they came from.
    def self.check!(set:, dir:, maps:, vswap:, vgagraph:)
      raise Refused, other_release(set, dir) unless set == SET

      probes(maps, vswap, vgagraph).each do |probe|
        got = probe.found.call
        raise Refused, changed_copy(dir, probe, got) unless got == probe.wanted
      end
      nil
    end

    # In this order, so a picture is asked for by number only once there are the right number of them.
    def self.probes(maps, vswap, vgagraph)
      [Probe.new("GAMEMAPS", "the number of floors", 60, -> { maps.count }),
       Probe.new("VSWAP", "the number of walls", 106, -> { vswap.wall_count }),
       Probe.new("VSWAP", "the number of sprites", 436, -> { vswap.sprite_count }),
       Probe.new("VSWAP", "the number of sounds", 46, -> { vswap.sound_count }),
       Probe.new("VGAGRAPH", "the number of pictures", 132, -> { vgagraph.picture_count }),
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

        This game can only use #{NEEDED}.
        To fix this, set #{GameData::ENV_VAR} or #{GameData::CONFIG_FILE} to the directory that has the #{SET} files.
        #{NEARBY[set]}
      TEXT
    end
    private_class_method :other_release

    def self.changed_copy(dir, probe, got)
      <<~TEXT
        The #{SET} files in #{dir} are not files this game can use.

        In #{probe.file}, #{probe.asked} must be #{probe.wanted}. In this copy it is #{got}.

        This game can only use #{NEEDED}. Apogee's versions and changed files do not work.
        To fix this, set #{GameData::ENV_VAR} or #{GameData::CONFIG_FILE} to the directory that has those files.
      TEXT
    end
    private_class_method :changed_copy

    def self.unreadable(set, dir)
      <<~TEXT
        This game cannot read the #{set} files in #{dir}. They are damaged or changed.

        This game can only use #{NEEDED}.
        To fix this, set #{GameData::ENV_VAR} or #{GameData::CONFIG_FILE} to the directory that has those files.
      TEXT
    end
    private_class_method :unreadable
  end
end
