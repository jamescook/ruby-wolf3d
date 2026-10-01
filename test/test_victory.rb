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

  START_X = 4
  ROW = 4
  SIDE = 16
  WON_BY = 20 # passes of walking backwards, which is further than one cell

  # Walk backwards onto the way out, then do nothing for +passes+ more passes after the walk.
  def won_and_waited(passes:)
    Reference.new.input_each_frame { |f| f < WON_BY ? [:down] : [] }
             .run(a_floor_with_a_way_out, frames: WON_BY + passes)
  end

  def ink_in_the_view(run)
    (0...FP::ACROSS).to_a.product((0...FP::VIEW_H).to_a).count { |x, y| run.screen.pixel(x, y) == INK }
  end

  def fixture = @fixture ||= Wolf3D::Fixture::Release.new
  def vswap = @vswap ||= Wolf3D::Vswap.new(fixture.files["VSWAP"])

  # A room with the way out behind the player, who faces east, and a guard shut in a room of his
  # own below it. The guard is there because a game needs something that can kill you before it
  # counts lives at all, and it is the count of lives that answers START.
  def a_floor_with_a_way_out
    @a_floor_with_a_way_out ||= program_of(way_out_level)
  end

  def way_out_level
    cells = Array.new(SIDE * SIDE, Wolf3D::Level::FLOOR)
    things = Array.new(SIDE * SIDE, 0)
    SIDE.times do |y|
      SIDE.times do |x|
        wall = x.zero? || y.zero? || x == SIDE - 1 || y == SIDE - 1 || y == SIDE / 2
        cells[(y * SIDE) + x] = Wolf3D::Fixture::Release::WALL if wall
      end
    end
    things[(ROW * SIDE) + START_X] = Wolf3D::Level::FACINGS.key(:east)
    things[(ROW * SIDE) + START_X - 1] = Wolf3D::Level::EXIT
    things[(12 * SIDE) + 10] = Wolf3D::Guards::STANDING + Wolf3D::Guards::FACINGS.index(:south)
    Wolf3D::Level.new(name: "Way out", width: SIDE, height: SIDE, walls: cells, things: things)
  end

  def program_of(level)
    doors = Wolf3D::Doors.new(level, vswap)
    guards = Wolf3D::Guards.new(level)
    scenery = Wolf3D::Scenery.new(level)
    atlas = Wolf3D::WallAtlas.new(vswap, Wolf3D::Palette.game, level, doors: doors)
    things = Wolf3D::ThingAtlas.new(vswap, Wolf3D::Palette.game,
                                    (guards.pictures + scenery.pictures).uniq.sort)
    RubyGBA.game("WON") do
      screen :bitmap, tear_free: true
      view = FP.new(build: self, level: level, atlas: atlas, doors: doors,
                    pushwalls: Wolf3D::Pushwalls.new(level), guards: guards, things: things,
                    scenery: scenery)
      game_loop { view.update }
    end.program
  end
end
