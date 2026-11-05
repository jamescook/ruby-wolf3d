# frozen_string_literal: true

require_relative "test_helper"

# THE FOUR GHOSTS, read out of SpawnGhosts and T_Ghosts (wl_act2.cpp), and MoveObj (wl_state.cpp),
# which is where a ghost's touch is. The map codes are ScanInfoPlane's in wl_game.cpp.
class TestGhosts < Minitest::Test
  include Wolf3DTest

  Enemy = Wolf3D::Enemy
  Guards = Wolf3D::Guards
  Release = Wolf3D::Fixture::Release

  ONE = (1 << Fraction::DEFAULT_BITS).to_f
  ROW = 8
  NAMES = %i[blinky clyde pinky inky].freeze

  def test_each_ghost_answers_to_its_own_code
    assert_equal [224, 225, 226, 227], NAMES.map { |name| Enemy[name].standing }
    assert_empty Guards.overlapping_codes
  end

  def test_each_has_its_own_two_pictures
    assert_equal [288, 289], Enemy[:blinky].pictures
    assert_equal [290, 291], Enemy[:pinky].pictures
    assert_equal [292, 293], Enemy[:clyde].pictures
    assert_equal [294, 295], Enemy[:inky].pictures
  end

  def test_a_ghost_runs_at_a_dogs_pace
    assert_equal Enemy[:dog].speed, Enemy[:blinky].speed(chasing: true)
  end

  def test_a_ghost_comes_for_you_from_the_start
    run = played(frames: 100, ghost_at: 14)

    assert_operator x_of(run), :<, 14.0, "it needs nobody to see it or wake it"
  end

  # NOTHING A GUN CAN DO. A shot goes through a ghost as though it were not there, and with a guard
  # standing behind it the guard is who is hit (GunAttack asks for FL_SHOOTABLE).
  def test_a_shot_goes_through_a_ghost_to_the_man_behind_it
    run = played(frames: 90, ghost_at: 11, guards: [[12, ROW, :east]], keys: ->(f) { f.even? ? [:b] : [] })
    hurt = run.pool(:guard, :hp).compact

    assert_includes hurt, 0, "the ghost still holds its nothing"
    assert_operator hurt.max, :<, Guards::HIT_POINTS, "and the man behind it took the bullets"
  end

  def test_shooting_a_ghost_alone_does_nothing_to_it
    still = played(frames: 80, ghost_at: 12)
    shot = played(frames: 80, ghost_at: 12, keys: ->(f) { f.even? ? [:b] : [] })

    assert_equal x_of(still), x_of(shot), "no flinch"
    assert_equal 0, shot[:kills] - still[:kills]
  end

  # TakeDamage(tics*2) every time it would move onto you.
  def test_its_touch_hurts
    run = played(frames: 200, ghost_at: 7)

    assert_operator run[:health], :<, Wolf3D::FirstPerson::START_HEALTH
  end

  def test_it_will_not_stand_on_top_of_you
    run = played(frames: 200, ghost_at: 7)

    assert_operator (x_of(run) - (run[:px] / ONE)).abs, :>, 0.5
  end

  # EACH COUNTS AS A KILL ALREADY MADE, so a floor with ghosts can still reach a hundred per cent.
  def test_a_ghost_is_counted_as_killed_from_the_start
    run = started_again(frames: 8)

    assert_equal 1, run[:kill_total]
    assert_equal 1, run[:kills]
  end

  private

  def x_of(run) = run.pool(:guard, :x).compact.min / ONE

  def fixture = @fixture ||= Release.new(sprites: Enemy::ALL.flat_map(&:pictures).max + 21)

  def played(frames:, ghost_at:, guards: [], keys: nil)
    Reference.new.input_each_frame { |f| keys ? keys.call(f) : [] }
             .run(program(ghost_at, guards), frames: frames)
  end

  def started_again(frames:)
    Reference.new.run(program(12, [], start: true), frames: frames)
  end

  def program(ghost_at, guards, start: false)
    @programs ||= {}
    @programs[[ghost_at, guards, start]] ||=
      view_of(arena(side: 24, player: [3, ROW], guards: guards, things: { [ghost_at, ROW] => Enemy[:blinky].standing })) do |b, view, _|
        once = b.var :_test_started, 0
        b.game_loop do
          if start && once == 0
            once = 1
            view.playthrough.start(:new_game)
          end
          view.update
        end
      end
  end
end
