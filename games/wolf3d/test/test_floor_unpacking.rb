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

  def test_the_made_up_floor_means_what_the_readers_say
    Dir.mktmpdir do |dir|
      release = Wolf3D::Fixture::Release.new(set: "WL6")
      release.write(dir)
      maps = Wolf3D::Maps.new(maphead: release.files["MAPHEAD"], gamemaps: release.files["GAMEMAPS"])
      pack = unpacked(made_up_original(dir))

      assert_equal maps.count, pack.fetch(:floor_count).getbyte(0)
      assert_same_world maps, pack
      assert_same_pushwalls maps, pack
      assert_same_lifts maps, pack
    end
  end

  def test_every_floor_of_the_real_copy_means_what_the_readers_say
    data = real_copy
    pack = unpacked(VBlank::Original::Game.new(title: "Wolfenstein 3D", setting: "WOLF3D_DATA", settings_file: "/dev/null",
                                               env: { "WOLF3D_DATA" => data.dir }, key: "data",
                                               releases: Wolf3D::Vanilla::RELEASES, platform: :pc))

    assert_equal Wolf3D.maps.count, pack.fetch(:floor_count).getbyte(0)
    assert_same_world Wolf3D.maps, pack
    assert_same_doors Wolf3D.maps, Wolf3D.vswap, pack
    assert_same_pushwalls Wolf3D.maps, pack
    assert_same_lifts Wolf3D.maps, pack
  end

  private

  # Each floor's walls that move, in a run of Unpacking::PUSHWALLS from the floor's start: the
  # readers' count, and for each wall the cell it starts in and the page of its lit face in the
  # whole row of wall pictures (WallAtlas: a code's lit face is page (code - 1) * 2).
  def assert_same_pushwalls(maps, pack)
    homes = pack.fetch(:push_home).unpack("v*")
    maps.count.times do |n|
      walls = Wolf3D::Pushwalls.new(maps[n])
      at = Unpacking::PUSHWALLS * n
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

  # Each floor's doors, in a run of Unpacking::DOORS from the floor's start: the readers' count,
  # and for each door its picture's page, which way it runs and the key it wants.
  def assert_same_doors(maps, vswap, pack)
    maps.count.times do |n|
      doors = Wolf3D::Doors.new(maps[n], vswap)
      run = (Unpacking::DOORS * n)...((Unpacking::DOORS * n) + doors.count)
      wanted = doors.doors.map { |door| [doors.picture_for(door), door.across, Wolf3D::FirstPerson::KEY_BITS[door.lock] || 0] }

      assert_equal doors.count, pack.fetch(:door_count).getbyte(n), "floor #{n}'s doors"
      assert_equal wanted, %i[door_picture door_across door_lock].map { |slot| pack.fetch(slot).bytes[run] }.transpose,
                   "floor #{n}'s doors"
    end
  end

  def unpacked(original)
    unpacking = VBlank::Builder.new.data_pack(from: original, version: "1", formats: [Wolf3D::MapPlaneFormat]) do |slots|
      Unpacking.declare(slots)
      slots.fill_from_copy { |copy, pack, release| Unpacking.new(self, copy, pack, release).fill }
    end.unpacking
    # The routine waits a frame every 256 bytes it writes (VBlank's progress bar), and writes each
    # byte of the pack about once, with a few frames more for each block it unpacks.
    unpacking.slot_bytes_in(Reference.new.run(unpacking.program, frames: (unpacking.byte_size / 256) + 400))
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
