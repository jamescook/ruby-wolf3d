# frozen_string_literal: true

require_relative "test_helper"
require "digest"
require "tmpdir"

# THE FLOORS WORKED OUT BY THE GAME ITSELF (FloorUnpacking), into a whole build's data pack, held to
# what the Ruby readers work out while a trimmed build is made: Maps for the planes, and Doors,
# Pushwalls and Elevator for what each cell means to the walk. The made-up release has a door, a
# wall that moves and a key in one room; the real copy has every floor id Software shipped.
class TestFloorUnpacking < Minitest::Test
  include Wolf3DTest

  Unpacking = Wolf3D::FloorUnpacking
  ThisFloor = Wolf3D::ThisFloor
  CELLS = Unpacking::CELLS

  def test_the_made_up_release_unpacks_as_the_readers_read_it
    Dir.mktmpdir do |dir|
      release = Wolf3D::Fixture::Release.new(set: "WL6")
      release.write(dir)
      maps = Wolf3D::Maps.new(maphead: release.files["MAPHEAD"], gamemaps: release.files["GAMEMAPS"])
      pack = unpacked(made_up_original(dir))

      assert_unpacked_as_read maps, Wolf3D::Vswap.new(release.files["VSWAP"]), release.pictures, pack
    end
  end

  # A FLOOR WHOSE PLANE STARTS PAST THE END OF GAMEMAPS ENDS THE FLOORS, rather than unpacking
  # whatever file the copy holds after it. Here the made-up floor's walls are said to start beyond
  # the file, so the release has no floor the routine can read.
  def test_a_floor_whose_plane_lies_past_gamemaps_is_not_unpacked
    Dir.mktmpdir do |dir|
      Wolf3D::Fixture::Release.new(set: "WL6").write(dir)
      path = File.join(dir, "GAMEMAPS.WL6")
      maps = File.binread(path)
      level_at = File.binread(File.join(dir, "MAPHEAD.WL6"))[2, 4].unpack1("V")
      maps[level_at, 4] = [maps.bytesize + 100].pack("V")
      File.binwrite(path, maps)

      assert_equal 0, unpacked(made_up_original(dir)).fetch(:floor_count).getbyte(0)
    end
  end

  # ...and A WALL PAGE PLACED PAST THE END OF VSWAP is left at place nought, as a page the copy
  # does not have, rather than read from whatever follows.
  def test_a_wall_page_past_vswap_is_not_unpacked
    Dir.mktmpdir do |dir|
      Wolf3D::Fixture::Release.new(set: "WL6").write(dir)
      path = File.join(dir, "VSWAP.WL6")
      vswap = File.binread(path)
      vswap[Wolf3D::Vswap::HEADER_BYTES, 4] = [vswap.bytesize + 100].pack("V")
      File.binwrite(path, vswap)
      walls = unpacked(made_up_original(dir)).fetch(:wall_pictures)

      assert_equal [0], (0...SIDE).flat_map { |y| walls.byteslice(y * Wolf3D::Holding::WALL_PAGES * SIDE, SIDE).bytes }.uniq
    end
  end

  # ...and A VGAGRAPH CHUNK PLACED PAST THE END OF THE FILE unpacks to nothing: the picture table,
  # said by VGAHEAD to start beyond VGAGRAPH, gives a release of no pictures.
  def test_a_chunk_past_vgagraph_is_not_unpacked
    Dir.mktmpdir do |dir|
      Wolf3D::Fixture::Release.new(set: "WL6").write(dir)
      path = File.join(dir, "VGAHEAD.WL6")
      head = File.binread(path)
      past = File.size(File.join(dir, "VGAGRAPH.WL6")) + 100
      head[0, Wolf3D::Vgagraph::OFFSET_BYTES] = [past].pack("V")[0, Wolf3D::Vgagraph::OFFSET_BYTES]
      File.binwrite(path, head)
      pack = unpacked(made_up_original(dir))

      assert_equal 0, pack.fetch(:picture_count).unpack1("v")
      assert_equal [0], pack.fetch(:picture_sizes).unpack("v*").uniq
    end
  end

  def test_the_six_episodes_unpack_as_the_readers_read_them
    assert_unpacked_as_read Wolf3D.maps, Wolf3D.vswap, Wolf3D.vgagraph, unpacked(original_of(real_copy))
  end

  # The shareware's ten floors fill the same slots, and the pack says it has ten.
  def test_the_shareware_unpacks_as_the_readers_read_it
    data = real_shareware
    assert_unpacked_as_read Wolf3D::Maps.from(data), Wolf3D::Vswap.from(data), Wolf3D::Vgagraph.from(data),
                            unpacked(original_of(data))
  end

  private

  def assert_unpacked_as_read(maps, vswap, graph, pack)
    assert_equal maps.count, pack.fetch(:floor_count).getbyte(0)
    assert_same_world maps, pack
    assert_same_doors maps, vswap, pack
    assert_same_pushwalls maps, pack
    assert_same_lifts maps, pack
    assert_same_pieces maps, pack
    assert_same_footing maps, pack
    assert_same_guards maps, pack
    assert_same_rooms maps, pack
    assert_same_totals maps, pack
    assert_same_starts maps, pack
    assert_same_arrows maps, pack
    assert_same_walls vswap, pack
    assert_same_sprites vswap, pack
    assert_same_picture_table graph, pack
  end

  # VGAGRAPH'S PICTURE TABLE, Huffman-packed in its first chunk: how many pictures the release
  # has, and each one's width and height in turn, nought past the last.
  def assert_same_picture_table(graph, pack)
    most = Wolf3D::Holding::VGA_PICTURES
    assert_equal graph.picture_count, pack.fetch(:picture_count).unpack1("v"), "how many pictures"
    wanted = (0...most).flat_map { |n| n < graph.picture_count ? graph.size(n) : [0, 0] }
    assert_equal wanted, pack.fetch(:picture_sizes).unpack("v*"), "every picture's width and height"
  end

  # EVERY SPRITE, laid out as ThingAtlas.whole lays its row: row by row across every sprite of the
  # largest VSWAP, a pixel no post covers (or a sprite the copy lacks) the see-through place. And
  # each sprite's four edges as ThingAtlas reads them, nought for one the copy lacks.
  def assert_same_sprites(vswap, pack)
    sprites = Wolf3D::Holding::SPRITES
    across = sprites * SIDE
    got = pack.fetch(:sprite_pictures)
    assert_equal across * SIDE, got.bytesize, "every sprite of the largest VSWAP"
    clear = Wolf3D::PictureUnpacking::SEE_THROUGH
    sprites.times do |n|
      wanted = vswap.sprite?(n) ? vswap.sprite(n) : nil
      seen = (0...SIDE).flat_map { |y| got.byteslice((y * across) + (n * SIDE), SIDE).bytes }
      assert_equal (0...SIDE).flat_map { |y| (0...SIDE).map { |x| wanted&.[](x, y) || clear } }, seen, "sprite #{n}"
    end
    atlas = Wolf3D::ThingAtlas.whole(vswap, Wolf3D.palette)
    %i[first_column last_column first_row last_row].each do |edge|
      wanted = (0...sprites).map do |n|
        case edge
        when :first_column then atlas.first_column(n)
        when :last_column then atlas.last_column(n)
        when :first_row then atlas.first_row(n)
        when :last_row then atlas.last_row(n)
        end
      end
      assert_equal wanted, pack.fetch(:"sprite_#{edge}").bytes, "every sprite's #{edge}"
    end
  end

  # EVERY WALL PAGE, as places in the game's colours, laid out as WallAtlas lays its row of
  # pictures in a whole build: row by row across every page, a page the copy does not have (past
  # its walls, or left empty) all place nought.
  def assert_same_walls(vswap, pack)
    across = Wolf3D::Holding::WALL_PAGES * SIDE
    got = pack.fetch(:wall_pictures)
    assert_equal across * SIDE, got.bytesize, "every page of the largest VSWAP"
    Wolf3D::Holding::WALL_PAGES.times do |page|
      wanted = vswap.wall?(page) ? vswap.wall(page) : nil
      seen = (0...SIDE).flat_map { |y| got.byteslice((y * across) + (page * SIDE), SIDE).bytes }
      assert_equal (0...SIDE).flat_map { |y| (0...SIDE).map { |x| wanted ? wanted[x, y] : 0 } }, seen, "wall page #{page}"
    end
  end

  SIDE = Wolf3D::Vswap::Texture::SIDE

  # Each floor's turning points, laid out like the map: the way each sends a patrolling guard, or
  # nowhere (Guards#arrow_at).
  def assert_same_arrows(maps, pack)
    arrows = pack.fetch(:guard_arrow).bytes
    maps.count.times do |n|
      guards = Wolf3D::Guards.new(maps[n])
      wanted = maps[n].each_cell.map { |x, y| guards.arrow_at(x, y) || Wolf3D::Guards::NOWHERE }

      assert_equal wanted, arrows[CELLS * n, CELLS], "floor #{n}'s turning points"
    end
  end

  # Where the player starts each floor (Level#start): the cell, and the way they face as quarter
  # turns clockwise from east, which is how FirstPerson's angle runs (facing_angle).
  def assert_same_starts(maps, pack)
    turns = { east: 0, south: 1, west: 2, north: 3 }
    maps.count.times do |n|
      start = maps[n].start
      assert_equal [start.x, start.y, turns.fetch(start.facing)],
                   %i[start_x start_y start_quarter_turns].map { |slot| pack.fetch(slot).getbyte(n) }, "floor #{n}'s start"
    end
  end

  NOWHERE = Wolf3D::Rooms::NOWHERE

  # Each floor's rooms as Rooms reads them, from Level#area, counting from one: the room of every
  # cell; the two either side of each door, across its panel; the two a wall that moves stands
  # between, where it has exactly two round it; each piece's; and the run of exit tiles.
  def assert_same_rooms(maps, pack)
    room_of = pack.fetch(:room_of).bytes
    firsts = pack.fetch(:exit_first).unpack("v*")
    lasts = pack.fetch(:exit_last).unpack("v*")
    maps.count.times do |n|
      level = maps[n]
      room = ->(x, y) { (level.inside?(x, y) && level.area(x, y)&.+(1)) || NOWHERE }

      assert_equal level.each_cell.map { |x, y| room.call(x, y) }, room_of[CELLS * n, CELLS], "floor #{n}'s rooms"

      doors = Wolf3D::Doors.new(level, Struct.new(:wall_count).new(106)).doors
      sides = doors.map do |door|
        steps = door.across == Wolf3D::Doors::ACROSS_X ? [[-1, 0], [1, 0]] : [[0, -1], [0, 1]]
        steps.map { |dx, dy| room.call(door.x + dx, door.y + dy) }
      end
      at = Unpacking::DOORS_PER_FLOOR * n
      assert_equal sides, %i[door_side_a door_side_b].map { |slot| pack.fetch(slot).bytes[at, doors.length] }.transpose,
                   "floor #{n}'s door sides"

      walls = Wolf3D::Pushwalls.new(level).walls
      between = walls.map do |wall|
        round = [[1, 0], [-1, 0], [0, 1], [0, -1]].map { |dx, dy| room.call(wall.x + dx, wall.y + dy) }.uniq - [NOWHERE]
        round.length == 2 ? round : [NOWHERE, NOWHERE]
      end
      at = Unpacking::PUSHWALLS_PER_FLOOR * n
      assert_equal between, %i[push_room_a push_room_b].map { |slot| pack.fetch(slot).bytes[at, walls.length] }.transpose,
                   "floor #{n}'s rooms either side of a wall that moves"

      pieces = Wolf3D::Scenery.new(level).pieces
      assert_equal pieces.map { |piece| room.call(piece.x, piece.y) },
                   pack.fetch(:piece_room).bytes[Unpacking::PIECES_PER_FLOOR * n, pieces.length], "floor #{n}'s pieces' rooms"

      exits = level.exits.map { |x, y| (y * 64) + x }
      assert_equal [exits.min || 1, exits.max || 0], [firsts[n], lasts[n]], "floor #{n}'s way out"
    end
  end

  # What the screen between floors counts against: the men to kill at each of the four settings
  # (Guards#to_kill), and the treasure, which is every piece Pickups counts as one (a treasure or
  # a one-up). The secrets are the walls that move, counted already.
  def assert_same_totals(maps, pack)
    kills = pack.fetch(:kill_total).bytes
    treasures = pack.fetch(:treasure_total).unpack("v*")
    maps.count.times do |n|
      guards = Wolf3D::Guards.new(maps[n])
      settings = Wolf3D::Guards::SETTINGS
      worth = Wolf3D::Scenery.new(maps[n]).pieces.count { |piece| %i[treasure extra_life].include?(piece.bonus&.first) }

      assert_equal settings.map { |setting| guards.to_kill(setting) }, kills[settings.length * n, settings.length],
                   "floor #{n}'s men to kill"
      assert_equal worth, treasures[n], "floor #{n}'s treasure"
    end
  end

  # Each floor's guards, in a run of Unpacking::GUARDS_PER_FLOOR from the floor's start, as Guards reads
  # them: cell, kind (its place in Enemy::ALL), the way it faces as the original numbers
  # directions, whether it patrols, whether it lies in wait, and the easiest setting it turns up on.
  def assert_same_guards(maps, pack)
    maps.count.times do |n|
      guards = Wolf3D::Guards.new(maps[n]).guards
      run = (Unpacking::GUARDS_PER_FLOOR * n)...((Unpacking::GUARDS_PER_FLOOR * n) + guards.length)
      wanted = guards.map do |g|
        [g.x, g.y, Wolf3D::Enemy::ALL.index { |kind| kind.name == g.kind }, Wolf3D::Guards.direction_of(g.facing),
         g.patrolling ? 1 : 0, g.ambush ? 1 : 0, g.from]
      end

      assert_equal guards.length, pack.fetch(:guard_count).getbyte(n), "floor #{n}'s guards"
      assert_equal wanted, Unpacking::GUARD_SLOTS.map { |slot| pack.fetch(slot).bytes[run] }.transpose, "floor #{n}'s guards"
    end
  end

  # Each floor's scenery and pickups, in a run of Unpacking::PIECES_PER_FLOOR from the floor's start: the
  # readers' count, and for each piece its cell, which of Scenery's pieces it is and its picture.
  def assert_same_pieces(maps, pack)
    counts = pack.fetch(:piece_count).unpack("v*")
    maps.count.times do |n|
      pieces = Wolf3D::Scenery.new(maps[n]).pieces
      run = (Unpacking::PIECES_PER_FLOOR * n)...((Unpacking::PIECES_PER_FLOOR * n) + pieces.length)
      wanted = pieces.map do |piece|
        [piece.x, piece.y, maps[n].thing_code(piece.x, piece.y) - Wolf3D::Scenery::FIRST_CODE, piece.picture]
      end

      assert_equal pieces.length, counts[n], "floor #{n}'s pieces"
      assert_equal wanted, %i[piece_x piece_y piece_kind piece_picture].map { |slot| pack.fetch(slot).bytes[run] }.transpose,
                   "floor #{n}'s pieces"
    end
  end

  # Each floor's cells a foot cannot pass for what stands in them (Scenery#blocks?), and the
  # cells with something to pick up, as the piece's number in its floor counting from one
  # (Pickups' lying_at), both laid out like the map.
  def assert_same_footing(maps, pack)
    blocked = pack.fetch(:blocked).bytes
    lying = pack.fetch(:lying_at).unpack("v*")
    maps.count.times do |n|
      scenery = Wolf3D::Scenery.new(maps[n])
      want_lying = Array.new(CELLS, 0)
      scenery.pieces.each_with_index { |piece, at| want_lying[(piece.y * 64) + piece.x] = at + 1 if piece.bonus }

      assert_equal maps[n].each_cell.map { |x, y| scenery.blocks?(x, y) ? 1 : 0 }, blocked[CELLS * n, CELLS],
                   "floor #{n}'s blocked cells"
      assert_equal want_lying, lying[CELLS * n, CELLS], "floor #{n}'s things to pick up"
    end
  end

  # Each floor's walls that move, in a run of Unpacking::PUSHWALLS_PER_FLOOR from the floor's start: the
  # readers' count, and for each wall the cell it starts in and the page of its lit face in the
  # whole row of wall pictures (WallAtlas: a code's lit face is page (code - 1) * 2).
  def assert_same_pushwalls(maps, pack)
    homes = pack.fetch(:push_home).unpack("v*")
    maps.count.times do |n|
      walls = Wolf3D::Pushwalls.new(maps[n])
      at = Unpacking::PUSHWALLS_PER_FLOOR * n
      faces = walls.codes.map { |code| Wolf3D::WallAtlas.texture_index(code, Wolf3D::WallAtlas::LIT) }

      assert_equal walls.count, pack.fetch(:pushwall_count).getbyte(n), "floor #{n}'s walls that move"
      assert_equal walls.homes, homes[at, walls.count], "floor #{n}'s walls that move"
      assert_equal faces, pack.fetch(:push_face).bytes[at, walls.count], "floor #{n}'s walls that move"
    end
  end

  # Each floor's levers, and the cell that sends a lift to the secret floor, or minus one.
  def assert_same_lifts(maps, pack)
    cars = pack.fetch(:secret_car).unpack("s<*")
    maps.count.times do |n|
      lifts = Wolf3D::Elevator.new(maps[n])

      assert_equal lifts.count, pack.fetch(:lift_count).getbyte(n), "floor #{n}'s levers"
      assert_equal lifts.secret_cars.first || -1, cars[n], "floor #{n}'s secret lift"
    end
  end

  # Each floor's doors, in a run of Unpacking::DOORS_PER_FLOOR from the floor's start: the readers' count,
  # and for each door its picture's page, which way it runs and the key it wants.
  def assert_same_doors(maps, vswap, pack)
    maps.count.times do |n|
      doors = Wolf3D::Doors.new(maps[n], vswap)
      run = (Unpacking::DOORS_PER_FLOOR * n)...((Unpacking::DOORS_PER_FLOOR * n) + doors.count)
      wanted = doors.doors.map { |door| [doors.picture_for(door), door.across, Wolf3D::FirstPerson::KEY_BITS[door.lock] || 0] }

      assert_equal doors.count, pack.fetch(:door_count).getbyte(n), "floor #{n}'s doors"
      assert_equal wanted, %i[door_picture door_across door_lock].map { |slot| pack.fetch(slot).bytes[run] }.transpose,
                   "floor #{n}'s doors"
    end
  end

  def unpacked(original)
    # The pack a whole build declares, whose routine is run here on its own, not read back from
    # the packs kept between builds.
    unpacking = Wolf3D::DataPack.declare(VBlank::Builder.new, from: original).unpacking
    # The routine waits a frame every 256 bytes it writes (VBlank's progress bar), and writes each
    # byte of the pack about once, with a few frames more for each block it unpacks.
    unpacking.slot_bytes_in(unpacking.run_on(Reference.new, frames: (unpacking.byte_size / 256) + 400))
  end

  # Every floor's cells mean what the readers say, or the first floor and cell that do not.
  def assert_same_world(maps, pack)
    got = pack.fetch(:world).unpack("v*")
    maps.count.times do |n|
      want = world_of(maps[n])
      have = got[CELLS * n, CELLS]
      first = want.each_index.find { |cell| want[cell] != have[cell] }
      assert_nil first, "floor #{n}, cell #{first} (#{first.to_i % 64},#{first.to_i / 64}): " \
                        "wanted #{want[first.to_i]}, got #{have[first.to_i]}"
    end
  end

  # What each cell of +level+ means to the walk in a whole build, from the readers: ThisFloor's own
  # order of asking, with a wall's picture at its page in the whole row (WallAtlas, Holding).
  def world_of(level)
    doors = Wolf3D::Doors.new(level, Struct.new(:wall_count).new(106))
    pushwalls = Wolf3D::Pushwalls.new(level)
    levers = Wolf3D::Elevator.new(level)
    level.each_cell.map do |x, y|
      next ThisFloor::DOOR + doors.number_at(x, y) - 1 if doors.number_at(x, y)
      next ThisFloor::PUSH + pushwalls.number_at(x, y) - 1 if pushwalls.number_at(x, y)
      next ThisFloor::LIFT + levers.number_at(x, y) - 1 if levers.number_at(x, y)
      next 0 unless level.solid?(x, y)

      code = level.wall_code(x, y)
      code.between?(1, Wolf3D::Holding::WALL_PAGES / 2) ? ((code - 1) * 2) + 1 : 0
    end
  end

  def made_up_original(dir)
    files = Wolf3D::GameData::STEMS.to_h do |stem|
      path = File.join(dir, "#{stem}.WL6")
      ["#{stem}.WL6", { "sha1" => Digest::SHA1.file(path).hexdigest, "size" => File.size(path) }]
    end
    VBlank::Original::Game.new(title: "Wolfenstein 3D", setting: "WOLF3D_DATA", settings_file: "/dev/null",
                               env: { "WOLF3D_DATA" => dir }, key: "data", releases: { "WL6" => { "files" => files } },
                               platform: :pc)
  end
end
