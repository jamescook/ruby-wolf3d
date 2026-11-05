# frozen_string_literal: true

require_relative "test_helper"

# THE SAME PRESSES PLAY THE SAME GAME. A recorded run needs every roll to come out the same: what a
# guard rolls to hit, how much a shot takes, which way one dodges. The original starts its table of
# random bytes at a place taken from the clock (US_InitRndT), and this game does not: it starts in
# one place, and the dial moves that place.
class TestRandomSeed < Minitest::Test
  include Wolf3DTest

  ROW = SIDE / 2
  PASSES = 2000

  # A few rolls in a row, from whichever place +seed+ names.
  def rolls_from(seed)
    program = VBlank.game("ROLLS", consoles: %i[gba]) do
      Wolf3D.seed_random_numbers(self, seed)
      first = var :first, 0
      second = var :second, 0
      game_loop do
        first = rand(0..9999)
        second = rand(0..9999)
      end
    end.program
    run = Reference.new.run(program, frames: 3)
    [run[:first], run[:second]]
  end

  def test_one_seed_rolls_the_same_numbers_every_time
    assert_equal rolls_from("7"), rolls_from("7")
  end

  def test_two_seeds_roll_different_numbers
    refute_equal rolls_from("7"), rolls_from("8")
  end

  def test_no_seed_rolls_what_the_game_has_always_rolled
    assert_equal rolls_from(nil), rolls_from(nil)
    refute_equal rolls_from(nil), rolls_from("7")
  end

  def test_a_seed_that_is_not_a_whole_number_is_a_friendly_error
    error = assert_raises(ArgumentError) { rolls_from("seven") }

    assert_includes error.message, "WOLF3D_SEED"
  end

  # --- the whole game ---

  def a_guard_shooting_at_you
    Ractor.current[:guard_shooting_at_you] ||=
      view_of(arena(player: [4, ROW], guards: [[6, ROW - 1, :west], [6, ROW, :west], [6, ROW + 1, :west]]),
              drawing: false)
  end

  def what_the_fight_left(run) = [run[:health], run[:score], run[:px], run[:py]]

  def test_one_tape_plays_the_same_game_twice
    tape = ->(f) { (f / 40).even? ? [:b] : [:left] }
    first = Reference.new.input_each_frame(&tape).run(a_guard_shooting_at_you, frames: PASSES)
    second = Reference.new.input_each_frame(&tape).run(a_guard_shooting_at_you, frames: PASSES)

    assert_operator first[:health], :<, Wolf3D::FirstPerson::START_HEALTH, "the guard has hit you, so a roll landed"
    assert_equal what_the_fight_left(first), what_the_fight_left(second)
  end

  # What a roll decides must not rest on how long a pass took to draw, or a tape would play out
  # differently the day a floor gets quicker.
  def test_a_pass_running_late_rolls_the_same_numbers
    prompt = Reference.new.run(a_guard_shooting_at_you, frames: PASSES)
    late = Reference.new.frames_each_pass { 2 }.run(a_guard_shooting_at_you, frames: PASSES)

    assert_equal what_the_fight_left(prompt), what_the_fight_left(late)
  end

  def test_the_dial_reaches_the_game
    Wolf3D::GAME.program(settings: { seed: "7", floors: 1 })
  end
end
