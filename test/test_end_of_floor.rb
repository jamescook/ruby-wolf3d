# frozen_string_literal: true

require_relative "test_helper"

# WHAT A FINISHED FLOOR WAS WORTH: the three percentages and the bonus, read out of LevelCompleted
# in the original (wl_inter.cpp). How the lift gets you to this screen, and how the screen hands
# you on, is in test_floors.rb, which has the lift.
#
# A CARTRIDGE OF ITS OWN, because what these ask about is arithmetic: a floor with every guard
# dead and every wall shoved takes a long time to play and proves nothing more. L stands in for
# the lift arriving, with whatever counts the test names.
class TestEndOfFloor < Minitest::Test
  include Wolf3DTest

  Tally = Wolf3D::Tally
  World = Wolf3DTest::StepCountingWorld

  LIFT_ARRIVES = 2

  def one_empty_floor
    empty = Wolf3D::Level.new(name: "empty", width: 4, height: 4,
                              walls: Array.new(16, Wolf3D::Level::FLOOR), things: Array.new(16, 0))
    Wolf3D::Floors.of(level: empty, doors: nil, pushwalls: nil)
  end

  def tally_cartridge(kills:, kill_total:, secrets:, secret_total:, treasures:, treasure_total:,
                      score:, keys:)
    floors = one_empty_floor
    VBlank.game("TALLY", consoles: %i[gba]) do
      screen :bitmap, tear_free: true
      player = Wolf3D::Player.declare(build: self, x: 8.5, y: 8.5, angle: 0)
      playthrough = Wolf3D::Playthrough.new(build: self, floors: floors, score: player.score,
                                            world: World.new(self))
      tally = Tally.new(build: self, player: player, floors: floors, floor: playthrough.floor,
                        playthrough: playthrough, secret_lift: var(:secret_lift, 0),
                        totals: { kill: var(:kill_total, kill_total),
                                  secret: var(:secret_total, secret_total),
                                  treasure: var(:treasure_total, treasure_total) })
      game_loop do
        if pressed(:l)
          player.kills = kills
          player.secrets = secrets
          player.treasures = treasures
          player.score = score
          player.keys = keys
          tally.floor_finished
        elsif tally.showing == 1
          tally.wait_for_a_press
        end
      end
    end.program
  end

  # The floor finished with those counts, and then +pressing+ as the screen sits there.
  def finish_floor(pressing: ->(_) { [] }, frames: 8, kills: 0, kill_total: 0, secrets: 0, secret_total: 0,
                   treasures: 0, treasure_total: 0, score: 0, keys: 0)
    program = tally_cartridge(kills:, kill_total:, secrets:, secret_total:, treasures:, treasure_total:,
                              score:, keys:)
    Reference.new.input_each_frame { |f| pressing.call(f) + (f == LIFT_ARRIVES ? [:l] : []) }
             .run(program, frames: frames)
  end

  # --- the percentages ---

  def test_each_percentage_is_what_was_found_of_what_there_was
    run = finish_floor(kills: 1, kill_total: 4, secrets: 1, secret_total: 2, treasures: 3, treasure_total: 4)

    assert_equal 25, run[:_kill_ratio]
    assert_equal 50, run[:_secret_ratio]
    assert_equal 75, run[:_treasure_ratio]
  end

  # kr = (killcount * 100) / killtotal, on whole numbers: two out of three is 66, not 67.
  def test_a_percentage_is_rounded_down
    assert_equal 66, finish_floor(kills: 2, kill_total: 3)[:_kill_ratio]
  end

  # The original tests each total before it divides, and that is what a floor with no secrets on
  # it reads: nought per cent, not a hundred. So it earns no bonus either.
  def test_a_floor_with_nothing_to_find_is_nought_per_cent
    run = finish_floor

    assert_equal [0, 0, 0], run.then { [_1[:_kill_ratio], _1[:_secret_ratio], _1[:_treasure_ratio]] }
    assert_equal 0, run[:_tally_bonus]
  end

  # --- the bonus ---

  # PERCENT100AMT, once for each of the three that reached a hundred.
  def test_ten_thousand_points_for_each_hundred_per_cent
    one = finish_floor(kills: 3, kill_total: 3, treasures: 1, treasure_total: 2)
    all = finish_floor(kills: 3, kill_total: 3, secrets: 2, secret_total: 2, treasures: 2, treasure_total: 2)

    assert_equal 10_000, one[:_tally_bonus]
    assert_equal 30_000, all[:_tally_bonus]
  end

  def test_ninety_nine_per_cent_earns_nothing
    assert_equal 0, finish_floor(treasures: 99, treasure_total: 100)[:_tally_bonus]
  end

  # GivePoints, in LevelCompleted: the bonus is score like any other.
  def test_the_bonus_goes_on_the_score
    assert_equal 12_345, finish_floor(score: 2_345, kills: 1, kill_total: 1)[:score]
  end

  # --- what the screen does ---

  # GameLoop's ex_completed branch clears them before LevelCompleted, so the bar is already empty.
  def test_the_keys_are_gone_by_the_time_the_screen_shows
    assert_equal 0, finish_floor(keys: 3)[:keys]
  end

  def test_the_screen_waits
    run = finish_floor(frames: 200)

    assert_equal 1, run[:_tally_showing]
    assert_equal 0, run[:trail], "and the next floor has not been asked for"
  end

  # The original's IN_CheckAck takes anything at all. Here it is the two buttons a player's thumb
  # is on, because START already means the menu while a game is on.
  def test_a_or_b_moves_on
    %i[a b].each do |button|
      run = finish_floor(pressing: ->(f) { f == 5 ? [button] : [] })

      assert_equal 0, run[:_tally_showing], "#{button} leaves the screen"
      assert_equal 345, run[:trail], "and the next floor starts, once"
    end
  end

  # IN_StartAck: a button already down as the screen starts does not count, or a player with a
  # finger on fire would never see the screen at all.
  def test_a_button_held_from_before_does_not_move_on
    run = finish_floor(pressing: ->(_) { [:b] })

    assert_equal 1, run[:_tally_showing]
  end

  # gamestate.oldscore = gamestate.score comes AFTER LevelCompleted, so the bonus is safe: dying
  # on the next floor puts the score back to what you arrived with, and that includes it.
  def test_the_bonus_is_kept_by_a_death_on_the_next_floor
    run = finish_floor(pressing: ->(f) { f == 5 ? [:a] : [] }, kills: 1, kill_total: 1)

    assert_equal 10_000, run[:floor_score]
  end
end
