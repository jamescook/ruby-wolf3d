# frozen_string_literal: true

require_relative "../test_helper"

# A WHOLE BUILD PLAYS AS A TRIMMED ONE (Holding): the same floors, doors, guards, pickups, menus and
# lettering, the whole build reading them from its data pack and the trimmed one from the copy.
# Each unpacks a whole real copy, the music with it, which is minutes, so this runs with
# `rake e2e`, not `rake test`; test_holding has what a build holds.
class TestWholeBuilds < Minitest::Test
  include Wolf3DTest

  Holding = Wolf3D::Holding

  # A WHOLE BUILD READS NO FLOOR OF THE COPY: it holds the original's sixty floors as numbers alone,
  # and plays the first from its data pack exactly as a trimmed build plays it from the copy.
  def test_a_whole_build_holds_sixty_floors_it_has_not_read
    real_copy
    floors = Wolf3D.floors((0...Holding::FLOORS).to_a, holding: Holding.whole)
    whole = Reference.new.run(Wolf3D::GAME.program(settings: { screen: "playing", hold: "whole" }), frames: STANDING_FRAMES)

    assert_equal Holding::FLOORS, floors.count
    assert(floors.all? { |floor| floor.level.nil? && floor.doors.nil? && floor.guards.nil? }, "no floor read")
    assert_equal 0, count_differing_pixels(whole.screen, Reference.new.run(first_floor(hold: "trimmed"), frames: STANDING_FRAMES).screen),
                 "the whole build's first floor"
  end

  # A WHOLE BUILD DRAWS THE TITLE AND MENU PICTURES ITS PACK HOLDS: handed the six episodes' pack, the title screen (shortened
  # by the unpacking as MenuArt shortens it) and the main menu look as the trimmed build draws
  # them; handed the same pack with VGAGRAPH's pictures and the shortened screens blanked, neither does.
  def test_a_whole_build_draws_the_menu_pictures_its_pack_holds
    slots = slots_unpacked_from(real_copy)
    blank = %i[vga_pictures screen_pictures].to_h { |slot| [slot, "\x00".b * slots.fetch(slot).bytesize] }
    MenuScene::SCREENS.each do |screen|
      program = Wolf3D::GAME.checked_program(err: nil, settings: { screen: screen, hold: "whole" }, pack_at_start: true)
      # Built for a computer too, which starts the music on and so changes what the SOUND row says.
      trimmed_program = Wolf3D::GAME.checked_program(err: nil, settings: { floors: 1, screen: screen, hold: "trimmed" })
      trimmed = Reference.new.run(trimmed_program, frames: MenuScene::FRAMES).screen
      seen = [{}, blank].map do |changed|
        Reference.new.hand_file(pack_file_of(slots.merge(changed))).run(program, frames: MenuScene::FRAMES).screen
      end

      assert_equal 0, count_differing_pixels(seen[0], trimmed), "the #{screen} screen from the pack"
      assert_operator count_differing_pixels(seen[1], trimmed), :>, 1000, "the #{screen} screen with its pictures blanked"
    end
  end

  # ...AND ITS LETTERING: handed the six episodes' pack, the screen between floors (in the big
  # letters, VGAGRAPH's named pictures), the table of high scores (its names in the small alphabet,
  # each letter widened to an even width by the unpacking) and the first page of the first episode's
  # end article (laid out by the unpacking) and the main menu's rows and the episode list's heading
  # (in Wolfenstein's two alphabets) look as the trimmed build draws them; handed the same pack with
  # the named pictures, the small letters, the article's pages or the alphabets blanked, none does.
  # A trimmed build needs two episodes, twenty floors, to have an episode list at all.
  def test_a_whole_build_draws_the_lettering_its_pack_holds
    slots = slots_unpacked_from(real_copy)
    shown = {
      { floors: 1, screen: "playing", start: LiftScene.start } => [:vga_pictures, LiftScene::TALLY_FRAMES,
                                                                   ->(frame) { LiftScene.keys(frame) }],
      { screen: "scores" } => [:small_letter_pictures, MenuScene::FRAMES, ->(_) { [] }],
      ArticleScene::SETTINGS => [:article_pages, ArticleScene::FRAMES, ->(frame) { ArticleScene.keys(frame) }],
      { screen: "menu" } => [:font_glyphs, MenuScene::FRAMES, ->(_) { [] }],
      { screen: "episodes", floors: 20 } => [:font_glyphs, MenuScene::FRAMES, ->(_) { [] }]
    }
    shown.each do |settings, (slot, frames, keys)|
      program = Wolf3D::GAME.checked_program(err: nil, settings: settings.merge(hold: "whole"), pack_at_start: true)
      trimmed_program = Wolf3D::GAME.checked_program(err: nil, settings: { floors: 1 }.merge(settings, hold: "trimmed"))
      trimmed = Reference.new.input_each_frame(&keys).run(trimmed_program, frames: frames).screen
      seen = [{}, { slot => "\x00".b * slots.fetch(slot).bytesize }].map do |changed|
        Reference.new.hand_file(pack_file_of(slots.merge(changed))).input_each_frame(&keys).run(program, frames: frames).screen
      end

      assert_equal 0, count_differing_pixels(seen[0], trimmed), "#{settings} from the pack"
      assert_operator count_differing_pixels(seen[1], trimmed), :>, 100, "#{settings} with #{slot} blanked"
    end
  end

  # A WHOLE BUILD DRAWS THE WALLS AND THINGS ITS PACK HOLDS, not pictures read from the copy while
  # building: handed the six episodes' pack, the first room looks as the trimmed build draws it;
  # handed the same pack with every wall place nought, the walls are the palette's first colour;
  # with every thing place nought, the piece the player stands facing is drawn in it too, and with
  # every gun place nought, the pistol in the player's hands.
  def test_a_whole_build_draws_the_pictures_its_pack_holds
    piece = first_piece_with_room_south(&:blocks)
    start = "#{piece.x},#{piece.y + 2},north"
    program = Wolf3D::GAME.checked_program(err: nil, settings: { floors: 1, screen: "playing", hold: "whole", start: start },
                                           pack_at_start: true)
    walls = Wolf3D::Holding::WALL_PAGES * Wolf3D::PictureUnpacking::PAGE_BYTES
    things = Wolf3D::Holding::SPRITES * Wolf3D::PictureUnpacking::PAGE_BYTES
    guns = Wolf3D::WeaponAtlas::COUNT * Wolf3D::PictureUnpacking::PAGE_BYTES
    slots = slots_unpacked_from(real_copy)
    changes = [{}, { wall_pictures: "\x00".b * walls }, { sprite_pictures: "\x00".b * things }, { gun_pictures: "\x00".b * guns },
               { bar_pictures: "\x00".b * Wolf3D::BarUnpacking.places }]
    seen = changes.map do |changed|
      Reference.new.hand_file(pack_file_of(slots.merge(changed))).run(program, frames: STANDING_FRAMES).screen
    end
    trimmed_settings = { floors: 1, screen: "playing", hold: "trimmed", start: start }
    trimmed = Reference.new.run(Wolf3D::GAME.program(settings: trimmed_settings), frames: STANDING_FRAMES).screen

    # A wall fills thousands of the view's pixels from this spot, and the piece and the gun each a
    # few hundred: enough over those floors that one changed picture shows.
    assert_equal 0, count_differing_pixels(seen[0], trimmed), "the pack's own pictures"
    assert_operator count_differing_pixels(seen[1], trimmed), :>, 1000, "walls of place nought"
    assert_operator count_differing_pixels(seen[2], trimmed), :>, 100, "things of place nought"
    assert_operator count_differing_pixels(seen[3], trimmed), :>, 100, "the gun of place nought"
    assert_operator count_differing_pixels(seen[4], trimmed), :>, 100, "the status bar of place nought"
  end

  # A WHOLE BUILD DRAWS THE DOORS ITS PACK HOLDS: walked up to the first floor's door, the door
  # handed the six episodes' pack looks as the trimmed build draws it, and with the door's pictures
  # (the last Doors::DOOR_PICTURES wall pages of the copy) place nought in the pack, it does not.
  def test_a_whole_build_draws_the_doors_its_pack_holds
    program = Wolf3D::GAME.checked_program(err: nil, settings: { floors: 1, screen: "playing", hold: "whole" },
                                           pack_at_start: true)
    slots = slots_unpacked_from(real_copy)
    seen = [slots, slots.merge(wall_pictures: without_door_pictures(slots.fetch(:wall_pictures)))].map do |held|
      Reference.new.hand_file(pack_file_of(held)).input_each_frame(&WALK_KEYS).run(program, frames: DOOR_FRAMES).screen
    end
    trimmed = Reference.new.input_each_frame(&WALK_KEYS).run(first_floor(hold: "trimmed"), frames: DOOR_FRAMES).screen

    assert_equal 0, count_differing_pixels(seen[0], trimmed), "the pack's own door"
    # The door fills most of the view from where the walk stops.
    assert_operator count_differing_pixels(seen[1], trimmed), :>, 1000, "a door of place nought"
  end

  # A WHOLE BUILD LAYS OUT ITS MENUS AND STATUS BAR WITHOUT OPENING VGAGRAPH: every size and place it
  # needs is a constant the code holds (Vgagraph::SIZES, BarArt::PLATE), so a shell built where there
  # is no copy has both. Built with any question to VGAGRAPH refused, its main menu, bar and all,
  # still looks as the trimmed build draws it.
  def test_a_whole_build_lays_out_its_screens_without_vgagraph
    program = with_copy_refused(:wolf3d_vgagraph, "VGAGRAPH") do
      Wolf3D::GAME.checked_program(err: nil, settings: { screen: "menu", hold: "whole" }, pack_at_start: true)
    end
    trimmed_program = Wolf3D::GAME.checked_program(err: nil, settings: { floors: 1, screen: "menu", hold: "trimmed" })
    trimmed = Reference.new.run(trimmed_program, frames: MenuScene::FRAMES).screen
    seen = Reference.new.hand_file(whole_pack_of(real_copy)).run(program, frames: MenuScene::FRAMES).screen

    assert_equal 0, count_differing_pixels(seen, trimmed)
  end

  # A WHOLE BUILD HOLDS EVERY FLOOR WITHOUT OPENING GAMEMAPS: its floors are the original's sixty
  # numbers (Holding::FLOORS), each read from the pack as it is played, so a shell built where there
  # is no copy still has the game. Built with any question to GAMEMAPS refused, its first floor looks
  # as the trimmed build draws it.
  def test_a_whole_build_holds_its_floors_without_gamemaps
    program = with_copy_refused(:wolf3d_maps, "GAMEMAPS") do
      Wolf3D::GAME.checked_program(err: nil, settings: { screen: "playing", hold: "whole" }, pack_at_start: true)
    end
    trimmed = Reference.new.run(first_floor(hold: "trimmed"), frames: STANDING_FRAMES).screen
    seen = Reference.new.hand_file(whole_pack_of(real_copy)).run(program, frames: STANDING_FRAMES).screen

    refute trimmed.pixel(120, 60).zero?, "the view should be drawn by frame #{STANDING_FRAMES}"
    assert_equal 0, count_differing_pixels(seen, trimmed)
  end

  # ONE WHOLE BUILD OFFERS THE EPISODES ITS COPY HOLDS, read from the pack it is handed as it runs:
  # given the shareware's, the list steps over the five episodes the shareware lacks and A starts the
  # first; given the six episodes', down lands on the second, which starts at its own first floor.
  def test_a_whole_build_offers_the_episodes_its_pack_holds
    program = Wolf3D::GAME.checked_program(err: nil, settings: EpisodeScene::SETTINGS, pack_at_start: true)
    picked = [real_shareware, real_copy].map do |data|
      run = Reference.new.hand_file(whole_pack_of(data)).input_each_frame { |f| EpisodeScene.keys(f) }
                     .run(program, frames: EpisodeScene::FRAMES)
      [run[:menus_screen], run[:menus_start_floor]]
    end

    assert_equal [[Wolf3D::Menus::DIFFICULTY, 0], [Wolf3D::Menus::DIFFICULTY, Wolf3D::Floors::PER_EPISODE]], picked
  end

  # THE SAME FLOOR LOOKS THE SAME held either way: the walls, the guards and the gun come from the
  # whole row of pictures in place of the trimmed one, and the whole build reads its map from the
  # data pack (FloorTables), and nothing on the screen moves. Looked at twice: standing in the first
  # room, where the blue walls are, and after walking up to its door, which wears a picture of its
  # own. The two blue stones differ only a little, so a wall read as its neighbour shows in a few
  # hundred pixels of the first look, and in none of the second.
  def test_the_first_floor_looks_the_same_held_whole
    real_copy
    trimmed = first_floor(hold: "trimmed")
    whole = first_floor(hold: "whole")

    [STANDING_FRAMES, DOOR_FRAMES].each do |frames|
      seen = [trimmed, whole].map { |program| Reference.new.input_each_frame(&WALK_KEYS).run(program, frames: frames).screen }

      refute seen.first.pixel(120, 60).zero?, "the view should be drawn by frame #{frames}"
      assert_equal 0, count_differing_pixels(*seen), "pixels that differ at frame #{frames}"
    end
  end

  # A BUILD STARTED FURTHER IN reads the floor it starts on from the pack, which holds every floor
  # at its own number: the second floor's map, not the first's, under the second floor's doors.
  def test_a_later_floor_looks_the_same_held_whole
    real_copy
    seen = %w[trimmed whole].map do |hold|
      program = Wolf3D::GAME.program(settings: { floors: 1, from: 1, screen: "playing", hold: hold })
      Reference.new.run(program, frames: STANDING_FRAMES).screen
    end

    refute seen.first.pixel(120, 60).zero?, "the view should be drawn by frame #{STANDING_FRAMES}"
    assert_equal 0, count_differing_pixels(*seen), "pixels that differ"
  end

  # SOMETHING THAT STANDS IN THE WAY STOPS YOU held either way: the whole build reads which cells
  # are blocked from the data pack. The player is put down two cells south of the first floor's
  # first blocking piece with open floor between, facing it, and walks north until it stops them.
  def test_a_piece_in_the_way_stops_the_player_held_whole
    real_copy
    piece = first_piece_with_room_south(&:blocks)
    stopped = play_both(start: "#{piece.x},#{piece.y + 2},north", keys: WALK_NORTH_KEYS).map { |run| run[:py] }

    assert_operator stopped.first, :>, piece.y + 1, "the trimmed build stops the player short of the piece's cell"
    assert_equal stopped.first, stopped.last, "where the player stopped"
  end

  # SOMETHING LYING ON THE FLOOR IS PICKED UP held either way: the whole build reads where it lies
  # and what it gives from the data pack. The player walks north onto the first floor's first
  # clip or treasure with open floor south of it (food heals nothing at full health).
  def test_a_pickup_gives_the_same_held_whole
    real_copy
    piece = first_piece_with_room_south { |p| %i[ammunition treasure].include?(p.bonus&.first) }
    given = play_both(start: "#{piece.x},#{piece.y + 2},north", keys: WALK_NORTH_KEYS).map do |run|
      %i[ammo score health].map { |name| run[name] }
    end

    refute_equal [Wolf3D::FirstPerson::START_AMMO, 0, Wolf3D::FirstPerson::START_HEALTH], given.first,
                 "the trimmed build gives something for #{piece.bonus.inspect}"
    assert_equal given.first, given.last, "ammunition, score and health"
  end

  # A GUARD STANDS, SEES YOU AND FALLS held either way: the whole build reads where each guard
  # stands and how from the data pack, and what he starts as from his kind. The player is put down
  # two cells south of the first floor's first guard with open floor between, facing him, and
  # fires until the gun is empty.
  def test_a_guard_is_shot_held_whole
    real_copy
    guard = first_guard_with_room_south
    played = play_both(start: "#{guard.x},#{guard.y + 2},north", keys: FIRE_KEYS)
    seen = played.map { |run| [run[:kills], run[:health], run[:ammo]] }

    assert_operator seen.first.first, :>, 0, "the trimmed build kills the guard at #{guard.x},#{guard.y}"
    assert_equal seen.first, seen.last, "kills, health and ammunition"
    assert_equal 0, count_differing_pixels(*played.map(&:screen)), "pixels that differ"
  end

  # HOW MUCH THERE IS TO FIND IS THE SAME held either way: the men to kill, the walls that move
  # and the treasure the screen between floors counts against, which a whole build reads from the
  # data pack (FirstPerson#declare_what_there_is_to_find), on the first floor and the second.
  def test_the_floor_totals_are_the_same_held_whole
    real_copy
    [0, 1].each do |from|
      totals = %w[trimmed whole].map do |hold|
        settings = { floors: 1, from: from, screen: "playing", hold: hold }
        run = Reference.new.run(Wolf3D::GAME.program(settings: settings), frames: STANDING_FRAMES)
        %i[kill_total secret_total treasure_total].map { |name| run[name] }
      end

      assert_operator totals.first.sum, :>, 0, "floor #{from + 1} has something to find"
      assert_equal totals.first, totals.last, "floor #{from + 1}'s men to kill, secrets and treasure"
    end
  end

  # THE SECRET LIFT IS KNOWN held either way: the whole build reads the cell of a floor's secret
  # lift from the data pack. The player is put down in the first floor's secret car, facing one of
  # its levers, and pulls it.
  def test_the_secret_lift_is_known_held_whole
    real_copy
    start = LiftScene.start
    secret = %w[trimmed whole].map do |hold|
      settings = { floors: 1, screen: "playing", hold: hold, start: start }
      Reference.new.input_each_frame { |frame| LiftScene.keys(frame) }
               .run(Wolf3D::GAME.program(settings: settings), frames: LiftScene::PULLED_FRAMES)[:lift_secret]
    end

    assert_equal [1, 1], secret, "the lift pulled from #{start} is the secret one"
  end

  # A PATROL WALKS ITS BEAT held either way: the whole build reads each floor's turning points from
  # the data pack. The player is put down in the room of the first floor's first patrolling guard,
  # three cells behind him so he walks away unseeing, and waits while he patrols.
  def test_a_patrol_turns_where_the_map_says_held_whole
    real_copy
    start = behind_first_patrol
    places = %w[trimmed whole].map do |hold|
      settings = { floors: 1, screen: "playing", hold: hold, start: start }
      run = Reference.new.run(Wolf3D::GAME.program(settings: settings), frames: PATROL_FRAMES)
      # Only the slots in use: a whole build's pool has room for the original's most.
      %i[x y dir].map { |field| run.pool(:guard, field).compact }
    end
    at_start = Reference.new.run(Wolf3D::GAME.program(settings: { floors: 1, screen: "playing", hold: "trimmed", start: start }),
                                 frames: STANDING_FRAMES)

    refute_equal at_start.pool(:guard, :x).compact.zip(at_start.pool(:guard, :y).compact), places.first.first(2).transpose,
                 "a guard on the trimmed build has moved, from #{start}"
    assert_equal places.first, places.last, "where every guard is and which way he faces"
  end

  # A SECRET WALL MOVES held either way: the whole build reads where each starts and the floor's
  # count from the data pack. The player is put down beside the first floor's first wall that
  # moves, facing it, and pushes.
  def test_a_secret_wall_is_found_held_whole
    real_copy
    start = beside_first_secret_wall
    found = play_both(start: start, keys: PUSH_KEYS).map { |run| run[:secrets] }

    assert_equal 1, found.first, "the trimmed build counts the wall pushed from #{start}"
    assert_equal found.first, found.last, "secrets found"
  end

  # A DOOR OPENS held either way: the whole build reads the floor's doors and their count from the
  # data pack. From the first floor's start, facing east, the player walks up to its door, opens
  # it and walks on.
  def test_a_door_opens_held_whole
    real_copy
    walked = play_both(keys: THROUGH_THE_DOOR_KEYS).map { |run| run[:px] }
    at_the_door = Reference.new.input_each_frame(&WALK_KEYS).run(first_floor(hold: "trimmed"), frames: DOOR_FRAMES)[:px]

    assert_operator walked.first, :>, at_the_door + 1, "the trimmed build walks on through the door"
    assert_equal walked.first, walked.last, "where the player got to"
  end

  # A DOOR JOINS TWO ROOMS held either way, on a floor after the first: the whole build reads which
  # rooms each door joins from the data pack, at that floor's own run. The player is put down
  # beside the second floor's first door between two rooms, opens it, and walks through into the
  # room beyond, whose guards and things are drawn only once the door has joined it to the
  # player's.
  def test_a_door_joins_two_rooms_on_a_later_floor_held_whole
    real_copy
    start = beside_first_door_between_rooms(Wolf3D.maps[1])
    seen = %w[trimmed whole].map do |hold|
      settings = { floors: 1, from: 1, screen: "playing", hold: hold, start: start }
      Reference.new.input_each_frame(&OPEN_AND_WALK_KEYS).run(Wolf3D::GAME.program(settings: settings), frames: PLAYING_FRAMES)
    end

    refute seen.first.screen.pixel(120, 60).zero?, "the view should be drawn"
    assert_equal 0, count_differing_pixels(*seen.map(&:screen)), "pixels that differ in the room beyond the door"
  end

  # A WHOLE BUILD SOUNDS AS A TRIMMED ONE, its recordings read from its pack: built with VSWAP and
  # AUDIOT refused, handed the pack of either copy, the first floor's first guard shot (the gun, his
  # shout, his scream, rolled among the screams that copy has) over the floor's song mixes the same
  # samples, frame for frame, as the trimmed build made from that copy.
  def test_a_whole_build_sounds_as_a_trimmed_one
    real_copy
    settings = ShotGuardScene.settings(Wolf3D.maps[0])
    whole = without_sound_files do
      Wolf3D::GAME.checked_program(err: nil, settings: settings.merge(hold: "whole"), pack_at_start: true)
    end
    [real_copy, real_shareware].each do |data|
      trimmed = with_copy(data) { Wolf3D::GAME.checked_program(err: nil, settings: settings.merge(hold: "trimmed")) }
      heard = [Reference.new, Reference.new.hand_file(whole_pack_of(data))].zip([trimmed, whole]).map do |player, program|
        run = player.input_each_frame { |frame| ShotGuardScene.keys(frame) }.run(program, frames: ShotGuardScene::FRAMES)
        assert_operator run[:kills], :>, 0, "the guard falls, from #{data.dir}"
        run.mixed_sound
      end

      assert(heard.first.any? { |frame| frame.any? { |sample| sample != 0 } }, "the trimmed build is heard")
      differing = heard.first.zip(heard.last).count { |ours, theirs| ours != theirs }
      assert_equal 0, differing, "frames of sound that differ, from #{data.dir}"
    end
  end

  # The player stands still, then walks up to the first room's door.
  WALK_KEYS = ->(frame) { frame.between?(60, 100) ? [:up] : [] }
  STANDING_FRAMES = 59
  DOOR_FRAMES = 140
  # ...or opens that door and walks through it.
  THROUGH_THE_DOOR_KEYS = ->(frame) { frame == 110 ? [:a] : WALK_KEYS.call(frame) + (frame.between?(150, 200) ? [:up] : []) }
  # ...or walks north for long enough to cross two cells and be stopped.
  WALK_NORTH_KEYS = ->(frame) { frame > STANDING_FRAMES ? [:up] : [] }
  # ...or pushes what is in front of it, then waits while it slides.
  PUSH_KEYS = ->(frame) { frame == 70 ? [:a] : [] }
  # ...or fires, a press every few frames.
  FIRE_KEYS = ->(frame) { frame > STANDING_FRAMES && (frame % 12).zero? ? [:b] : [] }
  # ...or opens the door in front of it, waits for it to open, and walks through.
  OPEN_AND_WALK_KEYS = ->(frame) { frame == 70 ? [:a] : (frame.between?(110, 150) ? [:up] : []) }
  PLAYING_FRAMES = 220
  # ...long enough for a patrol to walk a few cells and turn.
  PATROL_FRAMES = 600

  private

  def first_floor(hold:) = Wolf3D::GAME.program(settings: { floors: 1, screen: "playing", hold: hold })

  # ONE OF THE COPY'S FILES ANSWERING NOTHING, standing in for one no machine has. +called+ names it
  # in the error.
  class RefusedFile < BasicObject
    def initialize(called)
      @called = called
    end

    def method_missing(name, *) = ::Kernel.raise(::RuntimeError, "the build asked #{@called} for #{name}")
    def respond_to_missing?(*) = true
  end

  # The block's builds with one of the copy's files refused. Wolf3D keeps each file it reads for this
  # worker under a key of its own (:wolf3d_vgagraph for Wolf3D.vgagraph, :wolf3d_maps for
  # Wolf3D.maps), and a test may not swap those methods, so the stand-in goes under +key+ and what
  # was there comes back after.
  def with_copy_refused(key, called)
    kept = Ractor.current[key]
    Ractor.current[key] = RefusedFile.new(called)
    yield
  ensure
    Ractor.current[key] = kept
  end

  # The block's builds with every file the sounds and music are read from refused.
  def without_sound_files(&)
    with_copy_refused(:wolf3d_vswap, "VSWAP") do
      with_copy_refused(:wolf3d_adlib, "AUDIOT's effects") { with_copy_refused(:wolf3d_adlib_music, "AUDIOT's music", &) }
    end
  end

  # THE BLOCK'S BUILDS MADE FROM +data+ (a GameData), as a trimmed build made where that is the copy
  # set: everything Wolf3D reads from the copy for this worker is read from it, and what was read
  # before comes back after.
  COPY_KEYS = %i[wolf3d_data wolf3d_maps wolf3d_vswap wolf3d_adlib wolf3d_adlib_music wolf3d_vgagraph wolf3d_gun_art].freeze

  def with_copy(data)
    kept = COPY_KEYS.to_h { |key| [key, Ractor.current[key]] }
    COPY_KEYS.each { |key| Ractor.current[key] = nil }
    Ractor.current[:wolf3d_data] = data
    yield
  ensure
    kept.each { |key, value| Ractor.current[key] = value }
  end

  # THE DATA PACK A SHELL MAKES FROM +data+ (a GameData), the file a whole build left without its pack
  # is handed: FloorUnpacking's routine run over that copy. The pack names no copy's SHA-1, which
  # only a shell checks.
  def whole_pack_of(data) = pack_file_of(slots_unpacked_from(data))

  # Each slot's bytes as FloorUnpacking and the rest leave them, unpacked from +data+.
  def slots_unpacked_from(data)
    slots_unpacked_by(Wolf3D::DataPack.declare(Builder.new, from: original_of(data)))
  end

  # The pack's wall_pictures, +walls+, with the six episodes' door pages place nought: the row holds
  # every page side by side, a page's row of SIDE places at page * SIDE along each of its rows.
  def without_door_pictures(walls)
    side = Wolf3D::Vswap::Texture::SIDE
    across = Wolf3D::Holding::WALL_PAGES * side
    first_door = Wolf3D.vswap.wall_count - Wolf3D::Doors::DOOR_PICTURES
    walls.dup.tap do |blanked|
      side.times do |y|
        blanked[(y * across) + (first_door * side), Wolf3D::Doors::DOOR_PICTURES * side] =
          "\x00".b * (Wolf3D::Doors::DOOR_PICTURES * side)
      end
    end
  end

  # The pack file holding +slots+.
  def pack_file_of(slots)
    VBlank::Original::Pack.holding(slots, sha1: "0" * 40, build_version: Wolf3D::DataPack::VERSION).to_bytes
  end

  # The same keys on the first floor held trimmed, then whole, each run for PLAYING_FRAMES.
  def play_both(keys:, start: nil)
    %w[trimmed whole].map do |hold|
      settings = { floors: 1, screen: "playing", hold: hold, start: start }.compact
      Reference.new.input_each_frame(&keys).run(Wolf3D::GAME.program(settings: settings), frames: PLAYING_FRAMES)
    end
  end

  # The first floor's first piece the block picks, with two empty cells south of it, so the
  # player can be put down two cells south facing it.
  def first_piece_with_room_south
    level = Wolf3D.maps[0]
    Wolf3D::Scenery.new(level).pieces.find do |p|
      yield(p) && [1, 2].all? { |down| empty_floor?(level, p.x, p.y + down) }
    end
  end

  # The first floor's first guard standing on every setting, with two empty cells south of him.
  def first_guard_with_room_south
    level = Wolf3D.maps[0]
    Wolf3D::Guards.new(level).at(:baby).find do |g|
      g.kind == :guard && [1, 2].all? { |down| empty_floor?(level, g.x, g.y + down) }
    end
  end

  # WOLF3D_START's x,y,facing for an empty cell beside the first floor's first wall that moves,
  # facing it.
  def beside_first_secret_wall
    level = Wolf3D.maps[0]
    facing = { [0, 1] => :north, [0, -1] => :south, [1, 0] => :west, [-1, 0] => :east }
    Wolf3D::Pushwalls.new(level).walls.each do |wall|
      facing.each do |(dx, dy), face|
        x = wall.x + dx
        y = wall.y + dy
        return "#{x},#{y},#{face}" if empty_floor?(level, x, y)
      end
    end
  end

  # WOLF3D_START's x,y,facing for an empty cell beside +level+'s first door with a different room
  # on each side, across its panel (Rooms#joins), facing it.
  def beside_first_door_between_rooms(level)
    doors = Wolf3D::Doors.new(level, Struct.new(:wall_count).new(Wolf3D::Holding::WALL_PAGES)).doors
    doors.each do |door|
      sides = door.across == Wolf3D::Doors::ACROSS_X ? [[-1, 0, :east], [1, 0, :west]] : [[0, -1, :south], [0, 1, :north]]
      rooms = sides.map { |dx, dy, _| level.area(door.x + dx, door.y + dy) }
      next if rooms.include?(nil) || rooms.uniq.length == 1

      sides.each do |dx, dy, face|
        return "#{door.x + dx},#{door.y + dy},#{face}" if empty_floor?(level, door.x + dx, door.y + dy)
      end
    end
  end

  # WOLF3D_START's x,y,facing for an empty cell three behind the first floor's first patrolling
  # guard, in his room, facing the way he does.
  def behind_first_patrol
    level = Wolf3D.maps[0]
    steps = { east: [1, 0], west: [-1, 0], north: [0, -1], south: [0, 1] }
    Wolf3D::Guards.new(level).at(:baby).each do |g|
      next unless g.patrolling && g.facing

      dx, dy = steps.fetch(g.facing)
      x = g.x - (3 * dx)
      y = g.y - (3 * dy)
      return "#{x},#{y},#{g.facing}" if empty_floor?(level, x, y) && level.area(x, y) == level.area(g.x, g.y)
    end
  end

  # Floor with nothing on it: no piece, no guard, no start (Level#starting_at refuses the rest).
  def empty_floor?(level, x, y) = !level.solid?(x, y) && level.thing_code(x, y).zero?

  def count_differing_pixels(one, other)
    (0...160).sum { |y| (0...240).count { |x| one.pixel(x, y) != other.pixel(x, y) } }
  end

end
