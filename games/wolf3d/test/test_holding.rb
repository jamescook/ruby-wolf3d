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
end
