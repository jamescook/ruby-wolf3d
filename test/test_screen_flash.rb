# frozen_string_literal: true

require_relative "test_helper"

# THE SCREEN GOES RED WHEN YOU ARE HIT AND GOLD WHEN YOU PICK SOMETHING UP.
#
# None of this is in any source tree, because the routines were left out of the released WL_PLAY.C.
# Every number here is read out of the shipped WOLF3D.EXE, at the addresses WOLF3D.MAP gives:
#
#   StartBonusFlash      0x10889  mov word [bonuscount], 18
#   StartDamageFlash     0x10894  add [damagecount], ax
#   UpdatePaletteShifts  0x108A0  bonus / 6 + 1, at most 3; damage / 10 + 1, at most 6; red wins
#   InitRedShifts        0x1070C  red: i of 8 toward (64, 0, 0); gold: i of 20 toward (64, 62, 0)
class TestScreenFlash < Minitest::Test
  include Wolf3DTest

  Flash = Wolf3D::ScreenFlash

  # Two buttons wired straight to the two flashes, over a grey screen.
  GROUND = 0x4210
  HURT = 25

  def program
    Ractor.current[:flash_program] ||= VBlank.game("FLASH", consoles: %i[gba]) do
      screen :bitmap
      flash = Wolf3D::ScreenFlash.new(build: self)
      game_loop do
        clear_screen 0x4210
        flash.hurt(25) if pressed(:a)
        flash.bonus if pressed(:b)
        flash.update
      end
    end.program
  end

  def played(frames, &keys) = Reference.new.input_each_frame(&keys).run(program, frames: frames)

  def test_nothing_is_showing_to_begin_with
    assert_equal 0, played(5) { [] }[:_flash_shown]
  end

  # A hit of 25 is 25 / 10 + 1, the third red.
  def test_a_hit_shows_a_red_by_how_hard_it_was
    assert_equal 3, played(4) { |f| f == 2 ? [:a] : [] }[:_flash_shown]
  end

  # 0x10894 ADDS, so a second hit stacks on the first, and six is as far as it goes.
  def test_hits_stack_and_stop_at_the_sixth_red
    assert_equal 6, played(8) { |f| [2, 4, 6].include?(f) ? [:a] : [] }[:_flash_shown]
  end

  # 18 / 6 + 1 is four, which is held to the third gold, numbered after the six reds.
  def test_a_pickup_shows_the_third_gold
    assert_equal Flash::REDS.length + 3, played(4) { |f| f == 2 ? [:b] : [] }[:_flash_shown]
  end

  # 0x10889 SETS, so a second pickup restarts the count rather than lengthening it.
  def test_a_second_pickup_restarts_the_flash_rather_than_adding_to_it
    one = played(6) { |f| f == 2 ? [:b] : [] }
    two = played(6) { |f| [2, 4].include?(f) ? [:b] : [] }

    assert_equal Flash::BONUS_COUNT - (Flash::PER_PASS * 3), two[:_flash_bonus], "three passes since the second"
    assert_operator two[:_flash_bonus], :>, one[:_flash_bonus]
  end

  # A MENU OPENS OVER A CLEAN PICTURE, and it opens with one of these still running.
  def test_the_flash_is_put_away_at_once
    run = Reference.new.input_each_frame { |f| f == 2 ? [:a] : (f == 4 ? [:start] : []) }.run(finishing, frames: 6)

    assert_equal 0, run[:_flash_shown]
  end

  def finishing
    Ractor.current[:flash_finishing] ||= VBlank.game("FLASH", consoles: %i[gba]) do
      screen :bitmap
      flash = Wolf3D::ScreenFlash.new(build: self)
      game_loop do
        clear_screen 0x4210
        flash.hurt(25) if pressed(:a)
        flash.finish if pressed(:start)
        flash.update
      end
    end.program
  end

  def test_red_wins_when_both_are_running
    assert_operator played(5) { |f| f == 2 ? %i[a b] : [] }[:_flash_shown], :<=, Flash::REDS.length
  end

  def test_a_flash_runs_out_and_the_screen_comes_back
    run = played(60) { |f| f == 2 ? [:a] : [] }

    assert_equal 0, run[:_flash_shown]
    assert_equal GROUND, run.screen.pixel(4, 4)
  end

  def test_the_picture_moves_toward_red
    run = played(4) { |f| f == 2 ? [:a] : [] }
    colour = run.screen.pixel(4, 4)

    assert_operator colour & 31, :>, GROUND & 31, "more red"
    assert_operator (colour >> 10) & 31, :<, (GROUND >> 10) & 31, "and less blue"
  end

  # THE SIX REDS AND THREE GOLDS, from InitRedShifts: the original's steps of eight and of twenty.
  def test_how_far_each_step_goes
    assert_equal [12, 25, 37, 50, 62, 75], Flash::REDS
    assert_equal [5, 10, 15], Flash::GOLDS
  end

  # --- in the game ----------------------------------------------------------------------------

  def test_a_shot_that_lands_flashes_red
    run = Reference.new.run(view_of(arena(guards: [[11, 8, :west]]), drawing: false), frames: 250)

    assert_operator run[:health], :<, Wolf3D::FirstPerson::START_HEALTH, "he should have hit you by then"
    assert_operator run[:_flash_hits], :>, 0
  end

  def test_walking_onto_a_key_flashes_gold
    run = Reference.new.input_each_frame { [:up] }
                    .run(view_of(arena(things: { [9, 8] => Wolf3D::Level::KEYS.key(:gold), [13, 3] => a_guard(:south) }),
                                 drawing: false), frames: 20)

    assert_operator run[:_flash_bonus], :>, 0
  end
end
