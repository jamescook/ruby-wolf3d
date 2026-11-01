# frozen_string_literal: true

require_relative "test_helper"

# A LIFE FOR EVERY 40,000 POINTS, read out of wolf4sdl: GivePoints and GiveExtraMan at
# wl_agent.cpp:528-566, EXTRAPOINTS at wl_def.h:129, the threshold set at wl_main.cpp:322 in NewGame.
#
# The buttons of this cartridge pay points straight, because earning forty thousand by playing is a
# very long test of one comparison. What a payment does after that is the game's own.
class TestScoring < Minitest::Test
  include Wolf3DTest

  START = Wolf3D::Lives::START
  EVERY = Wolf3D::Scoring::EVERY

  def program
    Ractor.current[:scoring_program] ||= view_of(arena(guards: [[14, 14, :south]]), drawing: false) do |b, view, _|
      game_loop do
        view.scoring.pay(45_000) if pressed(:a)
        view.scoring.pay(100) if pressed(:b)
        view.playthrough.start(:another_life) if pressed(:l)
        view.playthrough.start(:new_game) if pressed(:r)
        view.play
      end
    end
  end

  def played(*keys)
    script = keys.each_with_index.to_h { |key, n| [2 + (n * 2), [key]] }
    Reference.new.input_each_frame { |f| script.fetch(f, []) }.run(program, frames: 3 + (keys.length * 2))
  end

  def test_the_first_threshold_is_forty_thousand
    assert_equal 40_000, EVERY
    assert_equal EVERY, played[:next_extra]
  end

  def test_points_below_it_buy_nothing
    run = played(:b)

    assert_equal 100, run[:score]
    assert_equal START, run[:lives]
  end

  def test_passing_it_gives_a_life_and_moves_it_on
    run = played(:a)

    assert_equal 45_000, run[:score]
    assert_equal START + 1, run[:lives]
    assert_equal EVERY * 2, run[:next_extra]
  end

  def test_the_next_one_comes_at_eighty_thousand
    assert_equal START + 1, played(:a, :b)[:lives], "45,100 is not 80,000"
    assert_equal START + 2, played(:a, :a)[:lives], "90,000 is"
  end

  # IT NEVER GOES ABOVE NINE. The bar keeps one figure for it.
  def test_it_stops_at_nine
    assert_equal Wolf3D::Lives::MOST, played(*([:a] * 10))[:lives]
  end

  # A DEATH TAKES THE FLOOR'S POINTS BACK AND LEAVES THE THRESHOLD WHERE IT IS (Died touches
  # gamestate.score and not nextextra), so points earned twice do not pay a life twice.
  def test_a_death_leaves_the_threshold_where_it_is
    run = played(:a, :l, :a)

    assert_equal EVERY * 2, run[:next_extra], "45,000 again is still short of it"
    assert_equal 45_000, run[:score]
    assert_equal START + 1, run[:lives]
  end

  def test_a_new_game_puts_it_back
    run = played(:a, :r)

    assert_equal EVERY, run[:next_extra]
    assert_equal START, run[:lives]
  end
end
