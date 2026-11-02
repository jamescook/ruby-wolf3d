# frozen_string_literal: true

require_relative "test_helper"

# HOW OFTEN AN ENEMY FIRES, AND HOW HARD IT HITS, read from T_Chase and T_Shoot (wl_act2.cpp).
class TestGuardShots < Minitest::Test
  include Wolf3DTest

  Enemy = Wolf3D::Enemy
  BARREL = Wolf3D::Scenery::FIRST_CODE + 2
  WEST = Wolf3D::Guards::FACINGS.index(:west)
  HEALTH = Wolf3D::FirstPerson::START_HEALTH
  SPRITES = 300

  def fixture = @fixture ||= Wolf3D::Fixture::Release.new(sprites: SPRITES)

  # The most a shot from two cells away can take: a byte shifted down three times.
  MOST_AT_TWO_CELLS = 255 >> 3

  # Sixty of the original's units from raising the gun to lowering it, and the first think of his
  # chase raises it again. A pass is one unit and a man thinks on every other pass.
  GAP_BETWEEN_SHOTS_FRAMES = 60 + 4

  # Each of the eight cells round him holds a barrel, which stops a man and not a bullet.
  def hemmed_in(x, y) = [-1, 0, 1].product([-1, 0, 1]).reject { |pair| pair == [0, 0] }.to_h { |dx, dy| [[x + dx, y + dy], BARREL] }

  def worst_wound(kind)
    level = arena(player: [9, 8], things: hemmed_in(11, 8).merge([11, 8] => Enemy[kind].standing + WEST))
    healths = [HEALTH]
    run = Reference.new
    run.input_each_frame do
      healths << run[:health]
      []
    end
    run.run(view_of(level, drawing: false), frames: 1500)
    healths.each_cons(2).map { |before, after| before - after }.max
  end

  # dist*2/3 for ssobj and bossobj, which also moves him into the nearer band of damage. T_Shoot
  # calls them better shots.
  def test_an_ss_man_two_cells_away_hits_as_one_beside_you
    assert_operator worst_wound(:ss), :>, MOST_AT_TWO_CELLS
  end

  def test_a_guard_two_cells_away_does_not
    assert_operator worst_wound(:guard), :<=, MOST_AT_TWO_CELLS
  end

  # A man inside one and a quarter cells on both axes does not roll: chance is 300, past any byte.
  def test_a_guard_beside_you_fires_on_every_chance_he_gets
    run = Reference.new
    frame = 0
    shots = []
    was = nil
    run.input_each_frame do
      frame += 1
      state = run.pool(:guard, :state).first
      shots << frame if state != was && Enemy::GUARD.states[state.to_i]&.name == :shoot1
      was = state
      []
    end
    run.run(view_of(arena(player: [9, 8], guards: [[10, 8, :west]]), drawing: false), frames: 400)

    gaps = shots.each_cons(2).map { |first, second| second - first }
    assert_operator gaps.length, :>=, 2
    assert_operator gaps.max, :<=, GAP_BETWEEN_SHOTS_FRAMES
  end
end
