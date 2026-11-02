# frozen_string_literal: true

require_relative "test_helper"

# THE RUN BUTTON. Holding A moves the player at RUNMOVE (70) where a walk is BASEMOVE (35), read
# from WL_DEF.H. A press of A still opens a door, so a person can run at one and open it on the way.
class TestRunning < Minitest::Test
  include Wolf3DTest

  ONE = 1 << VBlank::DSL::Fraction::DEFAULT_BITS
  RUNMOVE = 70
  BASEMOVE = 35
  FRAMES = 30

  def walked(*buttons, level: arena(player: [2, 8]), frames: FRAMES)
    Reference.new.input_each_frame { buttons }.run(view_of(level, drawing: false), frames: frames)
  end

  def distance(run) = (run[:px] / ONE.to_f) - 2.5

  def test_running_covers_twice_the_ground_of_walking
    assert_in_delta RUNMOVE.to_f / BASEMOVE, distance(walked(:up, :a)) / distance(walked(:up)), 0.02
  end

  def test_a_run_does_not_pass_through_a_wall
    wall_ahead = arena(player: [2, 8], walls: (1..14).map { |y| [6, y] })

    assert_operator walked(:up, :a, level: wall_ahead, frames: 120)[:px] / ONE.to_f, :<, 6.0
  end

  def test_a_run_does_not_pass_through_a_man
    assert_operator walked(:up, :a, level: arena(player: [2, 8], guards: [[6, 8, :east]]), frames: 120)[:px] / ONE.to_f, :<=, 5.5
  end

  def test_holding_the_button_still_with_no_step_is_not_running
    assert_equal 0, walked(:a)[:_running]
  end

  # T_Shoot asks whether thrustspeed reached RUNSPEED, and a walk alone falls short of it.
  def test_a_walk_is_not_a_run
    assert_equal 0, walked(:up)[:_running]
  end

  def test_a_run_is_a_run
    assert_equal 1, walked(:up, :a)[:_running]
  end

  # Thrust adds up, so a walk with a sidestep is past RUNSPEED too.
  def test_a_walk_and_a_sidestep_together_count_as_running
    assert_equal 1, walked(:up, :l)[:_running]
  end

  def test_a_press_of_the_run_button_still_opens_a_door
    level = two_rooms(player: [6, 8])
    opened = Reference.new.input_each_frame { |frame| frame == 3 ? [:a] : [] }.run(view_of(level, drawing: false), frames: 30)

    assert_operator opened.list(:door_open).first, :>, 0
  end
end
