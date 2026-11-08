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
    piece, start = blocking_piece_with_room_south
    stopped = %w[trimmed whole].map do |hold|
      program = Wolf3D::GAME.program(settings: { floors: 1, screen: "playing", hold: hold, start: start })
      Reference.new.input_each_frame { |frame| frame > STANDING_FRAMES ? [:up] : [] }.run(program, frames: WALKING_FRAMES)[:py]
    end

    assert_operator stopped.first, :>, piece.y + 1, "the trimmed build stops the player short of the piece's cell"
    assert_equal stopped.first, stopped.last, "where the player stopped"
  end

  # The player stands still, then walks up to the first room's door.
  WALK_KEYS = ->(frame) { frame.between?(60, 100) ? [:up] : [] }
  STANDING_FRAMES = 59
  DOOR_FRAMES = 140
  # ...or walks north for long enough to cross two cells and be stopped.
  WALKING_FRAMES = 200

  private

  def first_floor(hold:) = Wolf3D::GAME.program(settings: { floors: 1, screen: "playing", hold: hold })

  def count_differing_pixels(one, other)
    (0...160).sum { |y| (0...240).count { |x| one.pixel(x, y) != other.pixel(x, y) } }
  end

  # The first floor's first piece that blocks, with two open cells south of it holding nothing,
  # and where to start (WOLF3D_START's x,y,facing) two cells south facing it.
  def blocking_piece_with_room_south
    level = Wolf3D.maps[0]
    scenery = Wolf3D::Scenery.new(level)
    piece = scenery.pieces.find do |p|
      p.blocks && [1, 2].all? { |down| !level.solid?(p.x, p.y + down) && scenery.index_at(p.x, p.y + down).nil? }
    end
    [piece, "#{piece.x},#{piece.y + 2},north"]
  end
end
