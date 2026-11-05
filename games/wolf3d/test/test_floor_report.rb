# frozen_string_literal: true

require_relative "test_helper"

# WHAT A FLOOR HOLDS AND THE WAY THROUGH IT, for a person or a script planning a run. The rooms here
# are small enough to check the answer by eye.
class TestFloorReport < Minitest::Test
  include Wolf3DTest

  Report = Wolf3D::FloorReport
  Elevator = Wolf3D::Elevator
  GOLD_DOOR = Wolf3D::Level::LOCKED_DOORS.first
  GOLD_KEY_CODE = Wolf3D::Scenery::FIRST_CODE + Wolf3D::Scenery::GOLD_KEY
  CROSS_CODE = Wolf3D::Scenery::FIRST_CODE + 29
  BARREL_CODE = Wolf3D::Scenery::FIRST_CODE + 1
  ROW = SIDE / 2

  # A room with a lever on its east wall.
  def room_with_a_lever(**) = arena(player: [2, ROW], cells: { [SIDE - 1, ROW] => Elevator::SWITCH }, **)

  # A wall down the middle with one door in it, and the lever on the far side.
  def door_between_rooms(door:, things: {})
    wall = (0...SIDE).map { |y| [7, y] } - [[7, ROW]]
    arena(player: [2, ROW], walls: wall, things: things,
          cells: { [7, ROW] => door, [SIDE - 1, ROW] => Elevator::SWITCH })
  end

  def test_the_route_runs_from_the_start_to_beside_the_lever
    route = Report.new(room_with_a_lever).route

    assert_equal [2, ROW], route.cells.first
    assert_equal [SIDE - 2, ROW], route.cells.last
    assert_equal :lever, route.ends_at
  end

  # Cmd_Use only takes a lever from the east or the west, so standing above one reaches nothing.
  def test_the_route_ends_east_or_west_of_a_lever
    level = arena(player: [2, 1], cells: { [8, 0] => Elevator::SWITCH })

    assert_nil Report.new(level).route, "the lever in the top wall can only be reached from above or below"
  end

  def test_the_route_steps_one_cell_at_a_time
    Report.new(room_with_a_lever).route.cells.each_cons(2) do |(ax, ay), (bx, by)|
      assert_equal 1, (ax - bx).abs + (ay - by).abs
    end
  end

  def test_the_route_goes_round_what_blocks_the_way
    route = Report.new(room_with_a_lever(things: { [5, ROW] => BARREL_CODE })).route

    refute_includes route.cells, [5, ROW]
  end

  def test_the_route_goes_through_a_plain_door
    route = Report.new(door_between_rooms(door: Wolf3D::Level::DOORS.first)).route

    assert_includes route.cells, [7, ROW]
  end

  def test_a_locked_door_with_no_key_on_the_floor_has_no_route
    assert_nil Report.new(door_between_rooms(door: GOLD_DOOR)).route
  end

  # The way through fetches the key first, however far that is off the straight line.
  def test_the_route_fetches_the_key_a_locked_door_wants
    level = door_between_rooms(door: GOLD_DOOR, things: { [2, 2] => GOLD_KEY_CODE })
    route = Report.new(level).route

    assert_operator route.cells.index([2, 2]), :<, route.cells.index([7, ROW])
  end

  # Two floors of the game end on an exit tile rather than a lever (Level::EXIT).
  def test_a_floor_with_an_exit_tile_ends_there
    route = Report.new(arena(player: [2, ROW], things: { [9, ROW] => Wolf3D::Level::EXIT })).route

    assert_equal [9, ROW], route.cells.last
    assert_equal :exit, route.ends_at
  end

  # Hans drops the gold key that opens the way out, so a floor with a boss has that key.
  def test_a_boss_counts_as_the_key_he_leaves
    boss = Wolf3D::Guards.codes_of(Wolf3D::Enemy[:hans]).first
    level = door_between_rooms(door: GOLD_DOOR, things: { [3, 3] => boss })

    refute_nil Report.new(level).route
  end

  def test_the_report_lists_what_a_floor_holds
    level = room_with_a_lever(guards: [[9, ROW, :west]], things: { [3, 3] => CROSS_CODE })
    report = Report.new(level)

    assert_equal [[3, 3, :treasure, 100]], report.pickups.map { |p| [p.x, p.y, *p.bonus] }
    assert_equal [[9, ROW, :guard]], report.guards(:baby).map { |g| [g.x, g.y, g.kind] }
  end

  # The real thing: every floor of the shareware can be finished.
  def test_every_floor_of_the_shareware_has_a_route
    maps = Wolf3D::Maps.from(real_shareware)

    maps.count.times { |n| refute_nil Report.new(maps[n]).route, "floor #{n + 1}" }
  end
end
