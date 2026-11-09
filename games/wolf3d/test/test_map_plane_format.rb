# frozen_string_literal: true

require_relative "test_helper"
require "digest"
require "tmpdir"

# A FLOOR'S PLANES UNPACKED BY THE GAME ITSELF (MapPlaneFormat), held to what Maps reads in Ruby:
# the same cells, the same order. The made-up release says exactly which bytes are read; the real
# copy says the format holds for every floor id Software shipped.
class TestMapPlaneFormat < Minitest::Test
  include Wolf3DTest

  CELLS = 64 * 64

  def test_the_made_up_floor_unpacks_to_the_cells_maps_reads
    Dir.mktmpdir do |dir|
      Wolf3D::Fixture::Release.new(set: "WL6").write(dir)
      maps = Wolf3D::Maps.new(maphead: File.binread(File.join(dir, "MAPHEAD.WL6")),
                              gamemaps: File.binread(File.join(dir, "GAMEMAPS.WL6")))

      assert_same_cells planes_of(maps[0]), unpacked(made_up_original(dir), floors: 1)
    end
  end

  # Every floor of this machine's copy, the first plane of each: Carmack's far copies and RLEW's
  # long runs both turn up in them, which a one-room floor never makes.
  def test_every_floor_of_the_real_copy_unpacks_to_the_cells_maps_reads
    data = real_copy
    original = VBlank::Original::Game.new(title: "Wolfenstein 3D", setting: "WOLF3D_DATA", settings_file: "/dev/null",
                                          env: { "WOLF3D_DATA" => data.dir }, key: "data",
                                          releases: Wolf3D::Vanilla::RELEASES, platform: :pc)
    maps = Wolf3D.maps

    assert_same_cells (0...maps.count).flat_map { |n| planes_of(maps[n]) }, unpacked(original, floors: maps.count)
  end

  private

  # Each floor's cells the same, or the first floor and cell that differ, with both numbers.
  def assert_same_cells(wanted, got)
    assert_equal wanted.length, got.length, "floors unpacked"
    wanted.zip(got).each_with_index do |(want, have), floor|
      cells = [want.unpack("v*"), have.unpack("v*")]
      first = cells[0].each_index.find { |n| cells[0][n] != cells[1][n] }
      assert_nil first, "floor #{floor}, cell #{first}: wanted #{cells[0][first.to_i]}, got #{cells[1][first.to_i]}"
    end
  end

  def planes_of(level)
    [(0...level.height).flat_map { |y| (0...level.width).map { |x| level.wall_code(x, y) } }.pack("v*")]
  end

  # The walls plane of the first +floors+ floors, unpacked on the interpreter, one string a floor.
  def unpacked(original, floors:)
    unpacking = VBlank::Builder.new.data_pack(from: original, version: "1", formats: [Wolf3D::MapPlaneFormat]) do |slots|
      slots.numbers :walls, count: CELLS * floors, width: :half, signed: false, layout: :gba
      slots.fill_from_copy do |copy, pack, release|
        head = copy.file("MAPHEAD.#{release}")
        maps = copy.file("GAMEMAPS.#{release}")
        floors.times do |n|
          maps.unpack_map_plane at: maps.word(head.word(2 + (4 * n))), into: pack[:walls], start: CELLS * 2 * n,
                                tag: head.half(0)
        end
      end
    end.unpacking
    # A floor is 8192 bytes, and the routine waits a frame every 256 it writes (VBlank's progress
    # bar): 32 frames a floor, and one more for each block.
    run = unpacking.run_on(Reference.new, frames: (34 * floors) + 4)

    unpacking.slot_bytes_in(run).fetch(:walls).b.scan(/.{#{CELLS * 2}}/mo)
  end

  # The made-up release in +dir+, named by its files as Vanilla names the real ones.
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
