# frozen_string_literal: true

require_relative "test_helper"

# AN ENEMY WITH A CLEAR LINE AT YOU DOES NOT WALK STRAIGHT AT YOU, read out of SelectDodgeDir
# (wl_state.cpp) and who calls it (T_Chase, T_DogChase, T_Schabb, T_Fake in wl_act2.cpp).
class TestSidestepping < Minitest::Test
  include Wolf3DTest

  Enemy = Wolf3D::Enemy
  Release = Wolf3D::Fixture::Release

  ONE = (1 << Fraction::DEFAULT_BITS).to_f
  ROW = 8.5
  WATCHING = (20..200).step(20).to_a

  def test_a_guard_with_a_clear_line_leaves_the_row_you_are_on
    assert(rows_of(arena(player: [3, 8], guards: [[13, 8, :west]])).any? { |y| y != ROW },
           "he comes on at a slant rather than straight down the row")
  end

  # T_Chase asks CheckLine first and only then dodges, so with a wall between you he comes the
  # plain way: along the longer axis, which is the row he is already on.
  def test_a_guard_with_no_clear_line_comes_the_plain_way
    wall = (5..11).map { |y| [7, y] }
    shot = lambda { |f| f == 1 ? [:b] : [] }

    assert(rows_of(arena(player: [3, 8], walls: wall, guards: [[13, 8, :west]]), &shot).all? { |y| y == ROW },
           "the noise brought him and he cannot see you")
  end

  # TryWalk tests the two cells beside a diagonal as well as the one it ends in, so a man cannot
  # cut a corner. Walls north and south of him leave only the way along the row.
  def test_a_sidestep_does_not_cut_a_corner
    level = arena(player: [3, 8], walls: [[6, 7], [6, 9]], guards: [[6, 8, :west]])
    still_there = WATCHING.map { |frames| where(level, frames) }.take_while { |x, _| x > 5.6 }

    assert_equal([ROW], still_there.map(&:last).uniq, "he goes out by the row")
  end

  # TURNING ROUND IS ONLY ALLOWED THE FIRST TIME AFTER HE NOTICES YOU (FL_FIRSTATTACK). Facing away
  # in a slot with the way behind him open, that first choice is what lets him come back at you.
  def test_the_first_sidestep_may_turn_him_round
    level = arena(player: [3, 8], walls: [[10, 7], [10, 9]], guards: [[10, 8, :east]])
    columns = WATCHING.map { |frames| where(level, frames) { |f| f == 1 ? [:b] : [] }.first }

    assert_operator columns.min, :<, 10.5, "he came back toward you"
    assert_operator columns.max, :<=, 10.5, "and never went further away"
  end

  # A blocked way on the longer axis leaves the other one (SelectChaseDir, d[2]).
  def test_a_guard_blocked_on_the_long_axis_takes_the_short_one
    wall = (5..11).map { |y| [7, y] } + [[12, 8], [12, 9], [12, 10]]
    level = arena(player: [3, 7], walls: wall, guards: [[13, 8, :west]])

    assert(rows_of(level) { |f| f == 1 ? [:b] : [] }.any? { |y| y < ROW }, "he goes round the wall in his way")
  end

  # T_DogChase never looks along a line: a dog dodges all the way in.
  def test_a_dog_always_sidesteps
    level = arena(player: [3, 8], things: { [13, 8] => Enemy[:dog].patrolling + 2 })

    assert(rows_of(level).any? { |y| y != ROW }, "it weaves as it comes")
  end

  # T_Fake calls nothing else.
  def test_a_fake_hitler_only_ever_sidesteps
    level = arena(side: 24, player: [3, 8], things: { [20, 8] => Enemy[:fake].standing })

    assert(rows_of(level).any? { |y| y != ROW }, "he has never come straight on")
  end

  # Outside four cells T_Schabb dodges as a guard does. Inside them it runs, which has its own test.
  def test_a_thrower_far_off_sidesteps
    level = arena(side: 24, player: [3, 8], things: { [20, 8] => Enemy[:schabbs].standing })

    assert(rows_of(level).any? { |y| y != ROW }, "he comes on at a slant")
  end

  private

  def fixture = @fixture ||= Release.new(sprites: Enemy::ALL.flat_map(&:pictures).max + 21)

  def where(level, frames, &keys)
    run = Reference.new.input_each_frame(&(keys || ->(_) { [] })).run(program(level), frames: frames)
    [run.pool(:guard, :x).compact.first / ONE, run.pool(:guard, :y).compact.first / ONE]
  end

  def rows_of(level, &keys) = WATCHING.map { |frames| where(level, frames, &keys).last }

  def program(level)
    @programs ||= {}
    @programs[level.object_id] ||= view_of(level, drawing: false)
  end
end
