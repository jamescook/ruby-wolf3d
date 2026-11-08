# frozen_string_literal: true

require_relative "test_helper"

# YOU CANNOT WALK THROUGH A MAN. TryMove (wl_agent.cpp) refuses a step that would bring the player
# within MINACTORDIST of anything shootable, on both axes at once: a square a whole cell either side
# of him. ClipMove tries the two axes apart, so you slide along him as you slide along a wall.
class TestWalkingIntoEnemies < Minitest::Test
  include Wolf3DTest

  FAR_ENOUGH = 200
  MINACTORDIST = 1.0

  # He has his back to you, so he stands where he was put and only the walking is being asked about.
  GUARD = [12, 8].freeze
  GUARD_MIDDLE = 12.5

  def test_the_player_stops_a_cell_short_of_a_man
    walked = Reference.new.hold(:up).run(view_of(arena(guards: [[*GUARD, :east]]), drawing: false), frames: FAR_ENOUGH)

    assert_operator walked[:px], :<=, GUARD_MIDDLE - MINACTORDIST, "he is in the way"
    assert_operator walked[:px], :>, GUARD_MIDDLE - MINACTORDIST - 0.2, "and you get right up to him"
  end

  def test_the_player_walks_on_past_where_a_man_is_not
    walked = Reference.new.hold(:up).run(view_of(arena, drawing: false), frames: FAR_ENOUGH)

    assert_operator walked[:px], :>, GUARD_MIDDLE + MINACTORDIST, "an empty field stops nobody"
  end

  # Turned a little off a straight line, the blocked axis stops and the other one carries on.
  def test_the_player_slides_along_a_man_as_along_a_wall
    pressed = Reference.new.input_each_frame { |frame| frame < 4 ? [:right] : [:up] }
                       .run(view_of(arena(guards: [[*GUARD, :east]]), drawing: false), frames: FAR_ENOUGH)

    assert_operator pressed[:py], :>, 9.5, "he slides round the man"
    assert_operator pressed[:px], :>, GUARD_MIDDLE, "and goes on once he is clear"
  end

  # The original can trap you against a man who has walked up to you, because it asks only where the
  # step ends. A step that takes you further from him is always allowed here.
  def test_a_step_away_from_a_man_is_never_refused
    next_to_him = arena(player: [11, 8], facing: :west, guards: [[*GUARD, :east]])
    walked = Reference.new.hold(:up).run(view_of(next_to_him, drawing: false), frames: 40)

    assert_operator walked[:px], :<, 11.0, "he can walk away"
  end
end
