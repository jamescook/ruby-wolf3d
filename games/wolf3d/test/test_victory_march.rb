# frozen_string_literal: true

require_relative "test_helper"

# WALKING OUT OF THE EPISODE, read out of VictoryTile, SpawnBJVictory, T_BJRun and VictorySpin. The
# way out is the cell behind the player, so walking backwards one cell starts it.
class TestVictoryMarch < Minitest::Test
  include Wolf3DTest

  March = Wolf3D::VictoryMarch
  FP = Wolf3D::FirstPerson
  Release = Wolf3D::Fixture::Release

  STEPPED_OFF = 16 # passes of walking back, by which the way out has been reached

  def test_the_way_out_starts_the_march_rather_than_ending_the_episode
    run = played(STEPPED_OFF + 10)

    assert_equal 1, run[:_march_running]
    assert_equal 0, run[:episode_won], "the episode is over when he has finished"
  end

  def test_the_view_swings_to_face_south
    assert_equal FP::QUARTER, played(STEPPED_OFF + 200)[:view]
  end

  def test_the_view_backs_away_five_cells_and_a_bit
    start = played(STEPPED_OFF + 2)
    stopped = played(STEPPED_OFF + 300)

    assert_operator start[:py], :>, 15.5, "it starts from the cell you stood in"
    assert_in_delta 16 - March::CAMERA_TRAVEL, stopped[:py], 0.01
  end

  def test_he_runs_north_past_where_you_stood
    soon = played(STEPPED_OFF + 2)
    later = played(STEPPED_OFF + 60)

    assert_operator later[:_march_y], :<, soon[:_march_y]
  end

  def test_you_cannot_move_while_he_runs
    held = played(STEPPED_OFF + 60) { |f| f > STEPPED_OFF + 10 ? [:right] : [] }

    assert_equal played(STEPPED_OFF + 60)[:view], held[:view]
  end

  # HE STANDS IN THE ROOM, and the view with him in it differs from the empty field behind him.
  def test_he_is_on_the_screen
    run = played(STEPPED_OFF + 120)
    empty = ->(x) { run.screen.pixel(x, FP::HORIZON) == run.screen.pixel(0, FP::HORIZON) }

    assert_equal 1, run[:_march_running]
    refute((60...180).all?(&empty), "something stands in the middle of the view")
  end

  # RUN, JUMP AND THE LONG HOLD, and only then is the episode over (T_BJDone).
  def test_then_the_episode_is_over
    run = played(STEPPED_OFF + 900)

    assert_equal 0, run[:_march_running]
    assert_equal 1, run[:episode_won]
  end

  private

  def played(frames, &keys)
    Reference.new.input_each_frame { |f| f < STEPPED_OFF ? [:down] : (keys ? keys.call(f) : []) }
             .run(program, frames: frames)
  end

  def fixture = @fixture ||= Release.new(sprites: March::PICTURES.last + 21)

  def program = Ractor.current[:march_program] ||= view_of(arena(side: 24, player: [8, 16], guards: [[20, 3, :east]], things: { [7, 16] => Wolf3D::Level::EXIT }))
end
