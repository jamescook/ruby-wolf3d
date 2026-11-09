# frozen_string_literal: true

require_relative "test_helper"

# WHAT A BUILD HOLDS (Holding): a cartridge only what its floors use, a computer build the whole
# game at the original's limits, so that a shell can be built before anybody's copy is read. The
# whole build holds more and must play the same.
class TestHolding < Minitest::Test
  include Wolf3DTest

  Holding = Wolf3D::Holding

  def test_a_computer_build_holds_the_whole_game
    assert_predicate Holding.for(nil, computer: true, dialled: false), :whole?
  end

  def test_a_cartridge_is_trimmed
    refute_predicate Holding.for(nil, computer: false, dialled: false), :whole?
  end

  # A dial picks floors to measure, and measuring a floor wants that floor's own shape.
  def test_a_computer_build_dialled_to_some_floors_is_trimmed
    refute_predicate Holding.for(nil, computer: true, dialled: true), :whole?
  end

  def test_the_setting_says_which_whatever_the_build
    assert_predicate Holding.for("whole", computer: false, dialled: true), :whole?
    refute_predicate Holding.for("trimmed", computer: true, dialled: false), :whole?
  end

  def test_a_word_it_cannot_read_says_what_to_give
    error = assert_raises(ArgumentError) { Holding.for("all", computer: true, dialled: false) }

    assert_includes error.message, "whole or trimmed"
  end

  # The room is the original's own (wl_def.h), and every floor of this copy fits in it.
  def test_a_whole_build_keeps_the_originals_room_for_every_floor
    real_copy
    floors = Wolf3D::Floors.from(Wolf3D.maps, Wolf3D.vswap, (0...Wolf3D.maps.count).to_a, holding: Holding.whole)

    assert_equal 64, floors.room_for(:doors), "MAXDOORS"
    assert_equal 149, floors.room_for(:guards), "MAXACTORS, less the player"
    assert_equal 400, floors.room_for(:pieces), "MAXSTATS"
  end

  # A floor that holds no dogs still ships the dogs, since the copy loaded later may have them.
  def test_a_whole_build_knows_every_kind_of_enemy
    release = Wolf3D::Fixture::Release.new
    maps = Wolf3D::Maps.new(maphead: release.files["MAPHEAD"], gamemaps: release.files["GAMEMAPS"])
    room = Wolf3D::Floors.from(maps, Wolf3D::Vswap.new(release.files["VSWAP"]), [0], holding: Holding.whole)

    assert_equal Wolf3D::Enemy::ALL.map(&:name), room.kinds
    refute room.no_floor_has?(:lifts), "and the code for everything"
  end

  # THE SHAREWARE'S PICTURES FILL A WHOLE BUILD'S ROWS, though its VSWAP lists pages it leaves
  # empty (the walls and things only the six episodes have): an empty page is drawn in the
  # palette's first colour, as a page past the end of the file is.
  def test_the_shareware_fills_a_whole_builds_pictures
    data = real_shareware
    vswap = Wolf3D::Vswap.from(data)
    palette = Wolf3D.palette
    walls = Wolf3D::WallAtlas.new(vswap, palette, Wolf3D::Maps.from(data)[0], holding: Holding.whole)
    things = Wolf3D::ThingAtlas.whole(vswap, palette)

    assert_equal walls.width * walls.height, walls.pixels.length, "every wall page, empty or not"
    assert_equal things.width * things.height, things.pixels.length, "every sprite, empty or not"
  end

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

  # A WHOLE BUILD DRAWS THE WALLS AND THINGS ITS PACK HOLDS, not pictures read from the copy while
  # building: handed the six episodes' pack, the first room looks as the trimmed build draws it;
  # handed the same pack with every wall place nought, the walls are the palette's first colour;
  # with every thing place nought, the piece the player stands facing is drawn in it too, and with
  # every gun place nought, the pistol in the player's hands.
  # ...AND ITS TITLE AND MENU PICTURES: handed the six episodes' pack, the title screen (shortened
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

  # ONE WHOLE BUILD OFFERS THE EPISODES ITS COPY HOLDS, read from the pack it is handed as it runs:
  # given the shareware's, the list steps over the five episodes the shareware lacks and A starts the
  # first; given the six episodes', down lands on the second, which starts at its own first floor.
  def test_a_whole_build_offers_the_episodes_its_pack_holds
    program = Wolf3D::GAME.checked_program(err: nil, settings: EpisodeScene::SETTINGS, pack_at_start: true)
    picked = [real_shareware, real_copy].map do |data|
      run = Reference.new.hand_file(whole_pack_of(data)).input_each_frame { |f| EpisodeScene.keys(f) }
                     .run(program, frames: EpisodeScene::FRAMES)
      [run[:screen], run[:_start_floor]]
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
    start = in_secret_car_facing_lever
    secret = %w[trimmed whole].map do |hold|
      settings = { floors: 1, screen: "playing", hold: hold, start: start }
      Reference.new.input_each_frame(&PUSH_KEYS).run(Wolf3D::GAME.program(settings: settings), frames: LEVER_FRAMES)[:lift_secret]
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
  # ...long enough after a lever is pulled to be read, before the floor ends.
  LEVER_FRAMES = 80
  # ...long enough for a patrol to walk a few cells and turn.
  PATROL_FRAMES = 600

  private

  def first_floor(hold:) = Wolf3D::GAME.program(settings: { floors: 1, screen: "playing", hold: hold })

  # THE DATA PACK A SHELL MAKES FROM +data+ (a GameData), the file a whole build left without its pack
  # is handed: FloorUnpacking's routine run over that copy. The pack names no copy's SHA-1, which
  # only a shell checks.
  def whole_pack_of(data) = pack_file_of(slots_unpacked_from(data))

  # Each slot's bytes as FloorUnpacking and the rest leave them, unpacked from +data+.
  def slots_unpacked_from(data)
    unpacking = Wolf3D::DataPack.declare(Builder.new, from: original_of(data)).unpacking
    slots_unpacked_by(unpacking)
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

  # WOLF3D_START's x,y,facing for the first floor's secret car (Elevator#secret_cars), facing a
  # lever beside it east or west: a lever is pulled only along the east-west axis
  # (FirstPerson#pull_the_lever, the original's Cmd_Use).
  def in_secret_car_facing_lever
    level = Wolf3D.maps[0]
    car = Wolf3D::Elevator.new(level).secret_cars.first
    x = car % level.width
    y = car / level.width
    facing = { [-1, 0] => :west, [1, 0] => :east }
    _, face = facing.find { |(dx, dy), _| level.wall_code(x + dx, y + dy) == Wolf3D::Elevator::SWITCH }
    "#{x},#{y},#{face}"
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
