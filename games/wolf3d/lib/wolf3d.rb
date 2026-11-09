# frozen_string_literal: true

# Wolfenstein 3D, built with VBlank. Needs a copy of the game you own — see README.md.

# PUT THE BUNDLE ON THE LOAD PATH OURSELVES, so that plain `rake` and plain `ruby games/wolf3d/wolf3d.rb`
# work and nobody has to remember `bundle exec`. This is an application rather than a library
# — nothing else will ever require it from inside its own bundle — and every way into it goes
# through this file, so saying it once here covers the build script, the Rakefile and a test
# file run on its own.
require "bundler/setup"

# The framework, as any other game built on it would have it: a gem, resolved by the Gemfile
# beside this file. The public entry point only, never its internals.
require "vblank"

require "digest"
require "fileutils"

# The compressions every id Software game of the time keeps its data in, which know nothing about
# this one. They are the repository's own lib/, beside games/.
require_relative "../../../lib/id_software"
require_relative "wolf3d/game_data"
require_relative "wolf3d/vanilla"
require_relative "wolf3d/palette"
require_relative "wolf3d/level"
require_relative "wolf3d/maps"
# ...and the same planes unpacked by the game itself, for a shell's data pack.
VBlank.require_game_file "wolf3d/map_plane_format"
require_relative "wolf3d/vswap"
require_relative "wolf3d/adlib_sounds"
require_relative "wolf3d/opl2"
require_relative "wolf3d/adlib_music"
require_relative "wolf3d/opl2_track"
# ...and the pictures of the gun in your hands, which are the last twenty sprites of it. Up
# here with the reader rather than beside the other two atlases, because a release written for
# the tests has to know how many sprites it must hold to have them.
require_relative "wolf3d/weapon_atlas"
require_relative "wolf3d/vgagraph"
require_relative "wolf3d/doors"
require_relative "wolf3d/pushwalls"
require_relative "wolf3d/elevator"
# ...after the doors, whose panels are the only thing that joins one room to the next.
VBlank.require_game_file "wolf3d/rooms"
# WHAT THE FIVE KINDS OF ENEMY ARE, then how a cartridge lays their states out, then how a floor
# is read for them. Each needs the one before it.
require_relative "wolf3d/enemy"
require_relative "wolf3d/behaviour"
require_relative "wolf3d/guards"
require_relative "wolf3d/scenery"
# ...after all of them, because a floor is made of every one, and sized by what a build holds.
require_relative "wolf3d/holding"
require_relative "wolf3d/floors"
require_relative "wolf3d/fixture/release"
require_relative "wolf3d/wall_atlas"
require_relative "wolf3d/thing_atlas"
require_relative "wolf3d/bar_art"
require_relative "wolf3d/menu_art"
VBlank.require_game_file "wolf3d/status_bar"
# ...and before every part of the game that declares state a saved game holds.
VBlank.require_game_file "wolf3d/this_floor"
# ...and the same numbers worked out by the game itself, for a whole build's data pack.
VBlank.require_game_file "wolf3d/floor_unpacking"
# ...and VSWAP's pictures, the other part of that pack, which DataPack declares.
VBlank.require_game_file "wolf3d/picture_unpacking"
VBlank.require_game_file "wolf3d/vgagraph_unpacking"
VBlank.require_game_file "wolf3d/data_pack"
# ...and where its tables come from, baked or from that pack, after both.
VBlank.require_game_file "wolf3d/floor_tables"
require_relative "wolf3d/lasting_state"
require_relative "wolf3d/player"
VBlank.require_game_file "wolf3d/guard_pool"
# ...and two small things the rest of the game tells: the screen, about a hit or a pickup, and the
# score, about points.
VBlank.require_game_file "wolf3d/screen_flash"
VBlank.require_game_file "wolf3d/scoring"
VBlank.require_game_file "wolf3d/floor_records"
require_relative "wolf3d/floor_report"
VBlank.require_game_file "wolf3d/first_person"
# ...after the view, whose height is what the gun's square is scaled to.
VBlank.require_game_file "wolf3d/weapons"
# ...after the view, whose constants say how big the part of the screen that goes red is.
VBlank.require_game_file "wolf3d/fizzle"
VBlank.require_game_file "wolf3d/dying"
# ...and after dying, which is the only thing that ever spends one.
VBlank.require_game_file "wolf3d/lives"
# ...and its sibling, the other way a game can stop. After lives, whose new game it begins.
VBlank.require_game_file "wolf3d/victory"
VBlank.require_game_file "wolf3d/victory_march"
# ...and what starts play again after either of them, or at the bottom of a lift.
VBlank.require_game_file "wolf3d/playthrough"
# ...and the screen a lift arrives at, which hands on to the playthrough, and what it is written in.
VBlank.require_game_file "wolf3d/big_lettering"
VBlank.require_game_file "wolf3d/tally"
# ...and after the view, whose START_HEALTH and KEY_BITS say what a full player is and what a key
# is worth, and after lives, which a one-up on the floor hands another of.
VBlank.require_game_file "wolf3d/pickups"
VBlank.require_game_file "wolf3d/music"
VBlank.require_game_file "wolf3d/sounds"
# ...after the view, whose constants they share: the three agree about how wide the lens is, and
# where the middle of the screen falls is what a shot is aimed by.
VBlank.require_game_file "wolf3d/billboards"
# ...and the guards' mind after what it hands things to: what they throw, and how a boss's fall ends.
VBlank.require_game_file "wolf3d/thrown"
VBlank.require_game_file "wolf3d/death_cam"
VBlank.require_game_file "wolf3d/guard_mind"
require_relative "wolf3d/map_view"
require_relative "wolf3d/palette_view"
require_relative "wolf3d/art_view"
# ...after the view, which the menus put themselves in front of and hand a game back to.
VBlank.require_game_file "wolf3d/saved_games"
VBlank.require_game_file "wolf3d/small_letters"
VBlank.require_game_file "wolf3d/high_scores"
require_relative "wolf3d/end_article"
VBlank.require_game_file "wolf3d/episode_end"
VBlank.require_game_file "wolf3d/menus"
VBlank.require_game_file "wolf3d/title"
# Reads the screens, the weapons and the keys by the names those files give them. Not on the
# cartridge: it drives one from outside, for tools/play_shareware.rb.
require_relative "wolf3d/pilot"

module Wolf3D
  # The name people see, and the only thing this cartridge says about itself. The four-character
  # CODE beside it in the header is the framework's to work out: an emulator reads that code to
  # decide which cartridge it has and what save hardware to give it, so one written by hand lands
  # on a real cartridge — as the one written here did, which was the 2002 release's own.
  TITLE = "WOLF3D"

  # This game's own directory, which is where wolf3d.yml is looked for.
  def self.home = File.expand_path("..", __dir__)

  # Nil until someone points the build at their copy. The game still builds without it, so the
  # cartridge can say what is missing instead of the build dying.
  #
  # KEPT PER RACTOR, not on the module. A build on another core may not write to a module, and
  # what is read out of your copy is not frozen, so it cannot be shared either: each Ractor that
  # asks reads the files for itself, once. `||=` on Ractor-local storage is safe to nest, which
  # maps asking for data does.
  #
  # WHERE your copy is comes from WOLF3D_DATA or wolf3d.yml, and is not one of the build's
  # settings below: it is a fact about this machine, the same for every build made on it.
  #
  # A COPY THAT WAS NAMED AND WILL NOT DO STOPS THE BUILD HERE, whether the trouble is the copy or
  # the place it was said to be (VBlank::Original::WrongCopy, see Vanilla's releases). Nothing named at all is
  # not trouble: it is the holding screen.
  def self.data = Ractor.current[:wolf3d_data] ||= GameData.locate_if_set

  def self.maps = Ractor.current[:wolf3d_maps] ||= data && Maps.from(data)

  # THE DIALS, as the environment spells them and as the build is told them. A build is handed
  # its settings (`GAME.program(settings: { floors: 1 })`, `vblank build games/wolf3d/wolf3d.rb --set
  # floors=1`); the environment is read only where a cartridge is built from the command line —
  # wolf3d.rb's last line — so a test building one floor never changes what another build sees.
  DIALS = { episodes: "WOLF3D_EPISODES", from: "WOLF3D_FROM", floors: "WOLF3D_FLOORS",
            start: "WOLF3D_START", armed: "WOLF3D_ARMED", ammo: "WOLF3D_AMMO",
            screen: "WOLF3D_SCREEN", seed: "WOLF3D_SEED", music: "WOLF3D_MUSIC", hold: "WOLF3D_HOLD" }.freeze

  # The settings the environment asks for — only the dials it actually sets, so an unset one
  # takes the game's own default.
  def self.settings_from(env)
    DIALS.filter_map { |name, var| [name, env[var]] unless env[var].to_s.strip.empty? }.to_h
  end

  # WHERE THE RANDOM NUMBERS START. Every roll in the game is a guard's: whether he hits, how hard,
  # which way he dodges. The cartridge starts them in one place on every boot and they advance only
  # when something rolls, so the same presses already play the same game. This moves that place, to
  # see a run go differently or to find one that plays well for a recording:
  #
  #   WOLF3D_SEED=7 rake build
  #
  # The original starts its table of random bytes at a place taken from the clock instead
  # (US_InitRndT, id_us_1.cpp).
  def self.seed_random_numbers(build, asked)
    return if asked.nil?

    build.seed Integer(asked.to_s, 10)
  rescue ArgumentError
    raise ArgumentError, "WOLF3D_SEED cannot read #{asked.inspect}. Give a whole number, like 7."
  end

  # WHICH EPISODES THE CARTRIDGE HOLDS. Every one your copy has, unless you say otherwise —
  # and it is said in EPISODES because that is how the game is divided, how its own menu asks
  # you to choose, and the only unit anybody playing it thinks in.
  #
  #   WOLF3D_EPISODES=1      just the first
  #   WOLF3D_EPISODES=1,3    the first and the third
  #   WOLF3D_EPISODES=2-4    the second to the fourth
  #
  # WHAT IT COSTS IS ROM AND BUILD TIME AND NOTHING IN THE FRAME. Each floor adds its map, its
  # blocking, its doors, its walls that move, its guards and everything lying on it, and none
  # of that is work the game does while somebody is playing. Measured on the registered
  # release: all six episodes is an 8MB cartridge and about a minute to build, against 4MB and
  # eight seconds for one. So the whole game is the default and trimming it is for when you are
  # building over and over.
  def self.which_episodes(asked = nil)
    asked = asked.to_s.strip
    return (1..maps.episodes).to_a if asked.empty?

    episodes_named(asked)
  end

  # A number, a list of them, or a range — "1", "1,3", "2-4", or any of those joined by commas.
  def self.episodes_named(asked)
    wanted = asked.split(",").flat_map { |part| an_episode_range(part) }.uniq.sort
    outside = wanted.reject { |n| (1..maps.episodes).cover?(n) }
    return wanted if outside.empty?

    raise ArgumentError,
          "WOLF3D_EPISODES asks for episode #{outside.join(' and ')}. This copy of the game " \
          "holds #{maps.episodes}. Give a number from 1 to #{maps.episodes}, a list like 1,3, " \
          "or a range like 2-4."
  end

  def self.an_episode_range(part)
    first, last = part.split("-", 2).map { |n| Integer(n.strip) }
    (first..(last || first)).to_a
  rescue ArgumentError
    raise ArgumentError,
          "WOLF3D_EPISODES cannot read #{part.strip.inspect}. Give a number like 1, a list " \
          "like 1,3, or a range like 2-4."
  end

  # ...AND WHICH FLOORS OF THOSE, which is a measuring tool rather than a way to play. A
  # cartridge boots on the first floor it holds, so the only way to read what a LATER floor
  # costs is to build one that begins there:
  #
  #   bundle exec vblank profile games/wolf3d/wolf3d.rb --set from=1 --set floors=1
  #
  # Floors differ enormously in what stands on them — the second floor of the first episode
  # carries three times the guards and three times the scenery of the first — so "what does a
  # frame cost" has no single answer for a game, only one per floor. WOLF3D_FLOORS on its own
  # is also the fastest build there is, which is what you want while changing something else.
  def self.which_floors(episodes: nil, from: 0, floors: nil)
    picked = which_episodes(episodes).flat_map { |episode| maps.floors_of(episode) }
    picked = picked.drop(Integer(from))
    floors ? picked.first(Integer(floors)) : picked
  end
  # ...AND WHERE ON THE FIRST FLOOR YOU START, which is the same kind of dial and exists for the
  # same reason: the moments worth looking at are the far ones, and every one of them is a long
  # walk from where the map puts you.
  #
  #   WOLF3D_FROM=8 WOLF3D_FLOORS=1 WOLF3D_START=34,17 ruby games/wolf3d/wolf3d.rb
  #
  # puts you three cells from Hans Grosse on the boss floor of the first episode, facing him.
  # Add `,north` (or east, south, west) to say which way you are looking; without it you face
  # whichever way the map had you facing.
  def self.where_to_start(asked)
    asked = asked.to_s.strip
    return nil if asked.empty?

    x, y, facing = asked.split(",").map(&:strip)
    [Integer(x), Integer(y), facing&.downcase&.to_sym]
  rescue ArgumentError, TypeError
    raise ArgumentError,
          "WOLF3D_START cannot read #{asked.inspect}. Give a cell as x,y — or x,y,facing, " \
          "where facing is north, east, south or west."
  end

  # The floors this cartridge holds, with the first one's start moved if it was asked for.
  # +holding+ is what the build holds (Holding).
  #
  # A WHOLE BUILD READS NONE OF THEM: its floors are numbers alone, and every floor is read from its
  # data pack after it is built (Floors.unread). Only a start moved by WOLF3D_START is read here.
  def self.floors(which, start: nil, holding: Holding.trimmed)
    where = where_to_start(start)
    moved = where && moved_start(which.first, where)
    return Floors.unread(which, holding: holding, start: moved) if holding.whole?
    return Floors.from(maps, vswap, which, holding: holding) unless moved

    Floors.from(SwappedFirstFloor.new(maps, moved, which.first), vswap, which, holding: holding, start_moved: true)
  end

  # The first floor's Level with the player put down at +where+ (x, y, facing).
  def self.moved_start(index, where)
    x, y, facing = where
    maps[index].starting_at(x, y, **(facing ? { facing: facing } : {}))
  end

  # A GAMEMAPS with one floor read differently, so that moving the start needs no new path
  # through the floor building — everything downstream asks the maps for a level and gets the
  # moved one exactly where it would have got the original.
  SwappedFirstFloor = Struct.new(:maps, :level, :which) do
    def [](index) = index == which ? level : maps[index]
    def episodes_of_ten? = maps.episodes_of_ten?
  end

  # ...AND WHAT IS IN YOUR HANDS WHEN IT BOOTS, which is the last dial of the same family and
  # exists because the other two are not quite enough on their own: standing next to a boss with
  # the pistol a new game gives you is standing next to a boss you cannot kill.
  #
  #   WOLF3D_ARMED=chain_gun WOLF3D_AMMO=99
  #
  # The four are knife, pistol, machine_gun and chain_gun. Left unsaid you get what the game
  # gives you, which is the pistol and eight rounds.
  def self.armed_with(asked)
    asked = asked.to_s.strip
    return nil if asked.empty?

    Weapons::NUMBERS.fetch(asked.downcase.to_sym) do
      raise ArgumentError,
            "WOLF3D_ARMED does not know #{asked.inspect}. The four weapons are " \
            "#{Weapons::NUMBERS.keys.join(', ')}."
    end
  end

  def self.starting_ammo(asked)
    asked = asked.to_s.strip
    asked.empty? ? nil : Integer(asked)
  end

  # WHICH SCREEN THE CARTRIDGE BOOTS ON, which is a measuring tool rather than a way to play —
  # the same kind of dial as WOLF3D_FROM above. The attract loop takes a quarter of a minute to
  # come round, and the episode list only exists on a cartridge carrying more than one episode,
  # so a cartridge that boots straight to the screen you want to look at saves a lot of waiting:
  #
  #   WOLF3D_SCREEN=credits ruby games/wolf3d/wolf3d.rb
  #
  # The screens are: notice, title, credits, menu, episodes, difficulty, playing, load, scores, won.
  def self.which_screen(asked) = Menus.screen_named(asked&.to_s)

  def self.vswap = Ractor.current[:wolf3d_vswap] ||= data && Vswap.from(data)
  def self.adlib = Ractor.current[:wolf3d_adlib] ||= data && AdlibSounds.from(data)
  def self.adlib_music = Ractor.current[:wolf3d_adlib_music] ||= data && AdlibMusic.from(data)

  def self.vgagraph = Ractor.current[:wolf3d_vgagraph] ||= data && Vgagraph.from(data)

  # The pictures of the gun in your hands, or nil for a copy of the game that does not hold
  # them — in which case the four weapons still work and you simply cannot see the one you have.
  def self.gun_art
    Ractor.current[:wolf3d_gun_art] ||= WeaponAtlas.in?(vswap) ? WeaponAtlas.new(vswap, palette) : nil
  end

  def self.palette = Palette.game

  # Say what the cartridge was built from, or how to fix it not knowing.
  def self.report(err = $stderr)
    return err.puts(data.describe) if data

    GameData.locate
  rescue VBlank::Original::NotSet => e
    err.puts e.message
  end

  GAME = VBlank.game(TITLE, consoles: %i[gba]) do
    # Drawn on the tear-free screen, and it has to be. A first-person view repaints every
    # pixel every frame, and this one costs more than a frame holds — so on a screen the
    # display reads while the game is still drawing it, the player watches the picture
    # arrive, half a corridor at a time. Here the frame is drawn out of sight and shown
    # whole, so a frame that takes too long shows the previous one again rather than a
    # torn one.
    screen :bitmap, tear_free: true

    # THE BUILD'S SETTINGS, every one asked here at the top: the framework treats a setting the
    # game never asks for as a misspelling, and a build with no copy of the game to read would
    # otherwise ask for none of them. See DIALS for what each one means.
    episodes = setting :episodes, nil
    from = setting :from, 0
    how_many = setting :floors, nil
    start = setting :start, nil
    armed = setting :armed, nil
    ammo = setting :ammo, nil
    boot_screen = setting :screen, nil
    # MUSIC STARTS ON WHERE IT COSTS NOTHING A PLAYER CAN SEE, and off on the console, where a frame
    # is short. `--set music=on` starts a cartridge with it on, to measure that.
    music_on = setting(:music, nil) == "on" || built_for_computer?
    Wolf3D.seed_random_numbers(self, setting(:seed, nil))
    # WHOLE ON A COMPUTER, TRIMMED ON A CARTRIDGE (Holding), unless `hold` says, or a dial picked
    # floors to measure.
    floors_picked = !episodes.nil? || !how_many.nil? || !start.nil? || from.to_i != 0
    holding = Wolf3D::Holding.for(setting(:hold, nil), computer: built_for_computer?, dialled: floors_picked)

    if Wolf3D.maps
      # A WHOLE BUILD HOLDS EVERY FLOOR THE ORIGINAL CAN HAVE, whichever copy it is made from; a dial
      # picks some of the copy's floors to measure.
      which = if holding.whole? && !floors_picked
                (0...Wolf3D::Holding::FLOORS).to_a
              else
                Wolf3D.which_floors(episodes: episodes, from: from, floors: how_many)
              end
      floors = Wolf3D.floors(which, start: start, holding: holding)
      atlas = Wolf3D::WallAtlas.new(Wolf3D.vswap, Wolf3D.palette, floors.map(&:level),
                                    doors: floors.map(&:doors), lifts: floors.map(&:lifts), holding: holding)
      things = if holding.whole?
                 Wolf3D::ThingAtlas.whole(Wolf3D.vswap, Wolf3D.palette)
               else
                 Wolf3D::ThingAtlas.new(Wolf3D.vswap, Wolf3D.palette,
                                        floors.flat_map { |f|
                                          f.guards.pictures + f.scenery.pictures +
                                            Wolf3D::Pickups.pictures(f.guards)
                                        }.then { |seen| seen + Wolf3D::VictoryMarch.pictures(floors, Wolf3D.vswap) }.uniq.sort)
               end
      # WOLFENSTEIN'S OWN MENU ART, or nil for a release whose pictures we cannot name — and
      # then the cartridge boots straight into the game, because there is nothing to write a
      # menu with. The same pictures hold the lettering of the screen between floors.
      menu_art = Wolf3D::MenuArt.of(Wolf3D.vgagraph)
      # A WHOLE BUILD READS ITS FLOORS FROM A DATA PACK, which FloorUnpacking fills from the copy:
      # here as the build is made, in a shell at LOAD ROM. A trimmed one bakes them (FloorTables).
      pack = holding.whole? ? Wolf3D::DataPack.declare(self, from: Wolf3D::GameData.original) : nil
      # WHAT THE SOUND ROW IS SET TO, which every one of the game's sounds and songs is played
      # under. Declared here rather than inside either of them because both need it and neither
      # owns it.
      sound_setting = menu_art && var(:sound_setting, music_on ? Wolf3D::Music::EFFECTS_AND_MUSIC : Wolf3D::Music::EFFECTS_ONLY)
      # `gun_art` is the pictures of the gun in your hands, and it is asked of the CARTRIDGE
      # rather than of the level: every floor is played holding the same four weapons, where the
      # walls and the things standing in the rooms differ from one floor to the next.
      view = Wolf3D::FirstPerson.new(build: self, floors: floors, atlas: atlas, things: things,
                                     vswap: Wolf3D.vswap,
                                     adlib: Wolf3D.adlib,
                                     bar_art: Wolf3D::BarArt.of(Wolf3D.vgagraph),
                                     gun_art: Wolf3D.gun_art,
                                     lettering: menu_art,
                                     sound_setting: sound_setting,
                                     armed_with: Wolf3D.armed_with(armed),
                                     ammo: Wolf3D.starting_ammo(ammo),
                                     pack: pack)
      if menu_art
        music = Wolf3D::Music.new(build: self, tracks: Wolf3D.adlib_music, floors: floors, setting: sound_setting,
                                  holding: holding)
        menus = Wolf3D::Menus.new(build: self, view: view, art: menu_art,
                                  palette: Wolf3D.palette, sound_setting: sound_setting, music: music,
                                  starting_on: Wolf3D.which_screen(boot_screen))
        game_loop { menus.update }
      else
        game_loop { view.update }
      end
    else
      title = Title.new(self)
      game_loop { title.update }
    end
  end

  def self.program = GAME.program
  def self.build_rom(**) = GAME.build_rom(**)
end
