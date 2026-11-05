# frozen_string_literal: true

require_relative "test_helper"

# WINNING AN EPISODE, which is walking out of it: the world stops, and EPISODE COMPLETE and
# PRESS START sit over the last picture of the game until START begins another.
#
# Read off the screen the way a player would see it — how much of the words' ink is in the view —
# over a floor whose way out is the cell behind the player, so walking backwards one cell wins.
class TestVictory < Minitest::Test
  include Wolf3DTest

  FP = Wolf3D::FirstPerson
  INK = Wolf3D::Palette.game[Wolf3D::Victory::INK]

  # THE WORDS STAY, and stay whole: the same ink in the view a short while after winning and a
  # long while after. The episode is won partway through the walk.
  def test_the_words_stay_on_the_screen_until_start
    soon = ink_in_the_view(won_and_waited(passes: 2))
    later = ink_in_the_view(won_and_waited(passes: 40))

    assert_operator soon, :>, 100, "the words should be up once the episode is won"
    assert_equal soon, later, "and still all there forty passes later"
  end

  # ...AND START TAKES THEM DOWN, with the new game it begins.
  def test_start_takes_the_words_down
    run = Reference.new.input_each_frame do |f|
      next [:down] if f < WON_BY

      f == WON_BY + 10 ? [:start] : []
    end.run(a_floor_with_a_way_out, frames: WON_BY + 20)

    assert_equal 0, ink_in_the_view(run)
  end

  private

  WON_BY = 20 # passes of walking backwards, which is further than one cell

  # Walk backwards onto the way out, then do nothing for +passes+ more passes after the walk.
  def won_and_waited(passes:)
    Reference.new.input_each_frame { |f| f < WON_BY ? [:down] : [] }
             .run(a_floor_with_a_way_out, frames: WON_BY + passes)
  end

  def ink_in_the_view(run)
    (0...FP::ACROSS).to_a.product((0...FP::VIEW_H).to_a).count { |x, y| run.screen.pixel(x, y) == INK }
  end

  def a_floor_with_a_way_out = @a_floor_with_a_way_out ||= view_of(way_out_level)
end
