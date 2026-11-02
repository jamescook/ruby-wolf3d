# frozen_string_literal: true

require_relative "test_helper"

# A MAN WHO CANNOT COME STRAIGHT AT YOU, read out of SelectChaseDir and SelectRunDir (wl_state.cpp).
# A chase is not pathfinding, but it does not give up either: a blocked man tries the rest of a short
# list of ways before he stops.
class TestChasing < Minitest::Test
  include Wolf3DTest

  ONE = (1 << Fraction::DEFAULT_BITS).to_f
  ROW = SIDE / 2
  WALL_X = 10

  def fixture = @fixture ||= Wolf3D::Fixture::Release.new(sprites: Wolf3D::Enemy::ALL.flat_map(&:pictures).max + 21)
  def fire_once = ->(f) { f == 2 ? [:b] : [] }

  def played(level, frames:, &keys)
    keys ||= fire_once
    Reference.new.input_each_frame(&keys).run(view_of(level, drawing: false), frames: frames)
  end

  def x_of(run, slot = 0) = run.pool(:guard, :x)[slot] / ONE
  def y_of(run, slot = 0) = run.pool(:guard, :y)[slot] / ONE

  # A short wall straight between him and you. East is the only way toward you, and the way he was
  # going, and both stop at the wall, so what moves him is the search.
  def a_wall_between
    arena(player: [13, ROW], guards: [[8, ROW, :east]], walls: [[WALL_X, ROW - 1], [WALL_X, ROW], [WALL_X, ROW + 1]])
  end

  def test_a_blocked_man_finds_his_way_round_a_wall
    assert_operator x_of(played(a_wall_between, frames: 900)), :>, WALL_X + 1
  end

  # A corridor one cell wide, a man lying in wait in it who a gunshot does not bring, and behind him
  # one it does. CHECKSIDE refuses a cell with a shootable man in it.
  STANDING_X = 7

  def a_man_in_the_way
    walls = (1..14).to_a.product([ROW - 1, ROW + 1])
    arena(player: [3, ROW], walls: walls, cells: { [STANDING_X, ROW] => Wolf3D::Level::AMBUSH },
          guards: [[STANDING_X, ROW, :east], [12, ROW, :west]])
  end

  def test_a_man_will_not_walk_into_another
    [200, 300].each do |frames|
      xs = played(a_man_in_the_way, frames: frames).pool(:guard, :x).compact.map { |x| x / ONE }.minmax

      assert_operator xs.first, :>=, STANDING_X, "nobody has got past at frame #{frames}"
      assert_operator xs.last, :>=, STANDING_X + 1, "nor in beside him"
    end
  end

  # --- a shut door ---

  # A man on his beat with a shut door ahead of him, in the room you are in, walking away from you.
  DOOR_X = 7

  def a_door_ahead_of(kind: :guard, door: Wolf3D::Level::DOORS.first)
    beat = Wolf3D::Guards::PATROLLING - Wolf3D::Guards::STANDING + Wolf3D::Guards::FACINGS.index(:west)
    level = two_rooms(player: [13, ROW], door: [DOOR_X, ROW], things: { [10, ROW] => Wolf3D::Enemy[kind].standing + beat })
    walls = Array.new(SIDE * SIDE) { |at| level.wall_code(at % SIDE, at / SIDE) }
    walls[(ROW * SIDE) + DOOR_X] = door
    things = Array.new(SIDE * SIDE) { |at| level.thing_code(at % SIDE, at / SIDE) }
    Wolf3D::Level.new(name: "A door", width: SIDE, height: SIDE, walls: walls, things: things)
  end

  def quietly(level, frames:) = played(level, frames: frames) { [] }

  # TryWalk's CHECKSIDE: he calls OpenDoor and then waits at it, and walks on when it is all the way
  # open.
  def test_a_man_opens_a_shut_door_and_walks_through
    assert_operator x_of(quietly(a_door_ahead_of, frames: 600)), :<, DOOR_X
  end

  def test_a_man_waits_for_the_door_to_open_all_the_way
    run = (20..500).step(20).lazy.map { |frames| quietly(a_door_ahead_of, frames: frames) }
                   .find { |played| played.list(:door_open)[0].positive? }

    assert_operator run.list(:door_open)[0] / ONE, :<, Wolf3D::FirstPerson::DOOR_WIDE, "he has it opening"
    assert_operator x_of(run), :>=, DOOR_X + 1, "and has not gone in yet"
  end

  # OpenDoor asks nothing about keys: only the player's own OperateDoor does. A man walks through a
  # door you cannot.
  def test_a_man_opens_a_locked_door
    locked = a_door_ahead_of(door: Wolf3D::Level::LOCKED_DOORS.first)

    assert_operator x_of(quietly(locked, frames: 600)), :<, DOOR_X
  end

  # Dogs, fakes and ghosts walk by CHECKDIAG, which stops at a door.
  def test_a_dog_cannot_open_a_door
    run = quietly(a_door_ahead_of(kind: :dog), frames: 500)

    assert_equal 0, run.list(:door_open)[0]
    assert_operator x_of(run), :>=, DOOR_X + 1
  end

  # TryWalk returns at a shut door before it moves him on the map, so a man waiting there still
  # holds his own cell, and the man behind him cannot step into it.
  def test_a_man_waiting_at_a_door_still_holds_his_cell
    level = two_rooms(player: [13, ROW], door: [DOOR_X, ROW], patrols: [[DOOR_X + 1, ROW, :west], [DOOR_X + 2, ROW, :west]])
    (6..60).step(6).each do |frames|
      xs = quietly(level, frames: frames).pool(:guard, :x).compact.map { |x| x / ONE }.minmax
      next unless xs.first >= DOOR_X + 1

      assert_operator xs.last, :>=, DOOR_X + 2, "the second man stays out at frame #{frames}"
    end
  end

  # A body is no obstacle: the same corridor, with the man in the way already dead, lets him by.
  def test_a_man_walks_over_a_body
    corpse = ->(f) { f < 88 && (f / 16).even? ? [:b] : [] }
    level = arena(player: [5, ROW], guards: [[STANDING_X, ROW, :west], [12, ROW, :west]],
                  walls: (1..14).to_a.product([ROW - 1, ROW + 1]))
    run = Reference.new.input_each_frame(&corpse).run(view_of(level, drawing: true), frames: 720)

    alive = run.pool(:guard, :hp).compact.zip(run.pool(:guard, :x).compact).select { |hp, _| hp.positive? }

    assert_equal 1, alive.length, "the first man is down"
    assert_operator alive.first.last / ONE, :<, STANDING_X, "and the second has walked over him"
  end
end
