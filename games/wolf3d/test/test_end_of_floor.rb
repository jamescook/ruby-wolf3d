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

  # What the counting world's trail reads once the next floor has been started: its third, fourth
  # and fifth steps, which are all the lift asks for.
  NEXT_FLOOR_STEPS = 345

  # Far more frames than any count takes.
  COUNTED = 400

  # A pass of the floor clock is a tic, and there are seventy of those in the original's second.
  SECONDS = 70

  # +index+ is which floor of the whole game this is, ten to an episode.
  def one_empty_floor(index)
    empty = Wolf3D::Level.new(name: "empty", width: 4, height: 4,
                              walls: Array.new(16, Wolf3D::Level::FLOOR), things: Array.new(16, 0))
    floor = Wolf3D::Floors::Floor.new(index:, level: empty, doors: nil, pushwalls: nil, lifts: nil, guards: nil,
                                      scenery: nil)
    Wolf3D::Floors.new([floor])
  end

  def tally_cartridge(kills:, kill_total:, secrets:, secret_total:, treasures:, treasure_total:,
                      score:, keys:, index:, played:)
    floors = one_empty_floor(index)
    VBlank.game("TALLY", consoles: %i[gba]) do
      screen :bitmap, tear_free: true
      player = Wolf3D::Player.declare(build: self, x: 8.5, y: 8.5, angle: 0)
      playthrough = Wolf3D::Playthrough.new(build: self, floors: floors, score: player.score,
                                            world: World.new(self))
      scoring = Wolf3D::Scoring.new(build: self, player: player, lives: Wolf3D::Lives.new(build: self, playthrough: playthrough),
                                    lasting: Wolf3D::LastingState.new(build: self))
      records = Wolf3D::FloorRecords.new(build: self, lasting: Wolf3D::LastingState.new(build: self))
      tally = Tally.new(build: self, player: player, scoring: scoring, floors: floors, floor: playthrough.floor,
                        records: records, playthrough: playthrough, secret_lift: var(:secret_lift, 0),
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
          repeat(played) { records.tick }
          tally.floor_finished
        elsif tally.showing == 1
          tally.update
        end
      end
    end.program
  end

  # The floor finished with those counts after +played+ passes on the clock, and then +pressing+
  # as the screen sits there. The clock starts over par unless a test says otherwise, so the
  # figures that count are only the ones a test names.
  def finish_floor(pressing: ->(_) { [] }, frames: COUNTED, kills: 0, kill_total: 0, secrets: 0, secret_total: 0,
                   treasures: 0, treasure_total: 0, score: 0, keys: 0, index: 0, played: 90 * SECONDS)
    program = tally_cartridge(kills:, kill_total:, secrets:, secret_total:, treasures:, treasure_total:,
                              score:, keys:, index:, played:)
    Reference.new.input_each_frame { |f| pressing.call(f) + (f == LIFT_ARRIVES ? [:l] : []) }
             .run(program, frames: frames)
  end

  # A button down on just these frames, so each is a press of its own.
  def press_on(*frames, button: :a) = ->(f) { frames.include?(f) ? [button] : [] }

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
    assert_equal 0, run[:tally_bonus]
  end

  # --- the bonus ---

  # PERCENT100AMT, once for each of the three that reached a hundred.
  def test_ten_thousand_points_for_each_hundred_per_cent
    one = finish_floor(kills: 3, kill_total: 3, treasures: 1, treasure_total: 2)
    all = finish_floor(kills: 3, kill_total: 3, secrets: 2, secret_total: 2, treasures: 2, treasure_total: 2)

    assert_equal 10_000, one[:tally_bonus]
    assert_equal 30_000, all[:tally_bonus]
  end

  def test_ninety_nine_per_cent_earns_nothing
    assert_equal 0, finish_floor(treasures: 99, treasure_total: 100)[:tally_bonus]
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

    assert_equal 1, run[:tally_showing]
    assert_equal 0, run[:trail], "and the next floor has not been asked for"
  end

  # The original's IN_CheckAck takes anything at all. Here it is the two buttons a player's thumb
  # is on, because START already means the menu while a game is on.
  def test_a_or_b_moves_on_once_the_figures_have_finished
    %i[a b].each do |button|
      run = finish_floor(pressing: press_on(COUNTED - 2, button: button))

      assert_equal 0, run[:tally_showing], "#{button} leaves the screen"
      assert_equal NEXT_FLOOR_STEPS, run[:trail], "and the next floor starts, once"
    end
  end

  # --- the figures count up ---

  # Every figure starts from nothing and they go in the original's order: the par bonus, then
  # kills, secrets and treasure, one at a time.
  def test_the_figures_count_up_one_at_a_time
    floor = { kills: 1, kill_total: 2, secrets: 1, secret_total: 2, played: 30 * SECONDS }

    early = finish_floor(frames: LIFT_ARRIVES + 3, **floor)
    done = finish_floor(**floor)

    assert_operator early[:tally_shown_bonus], :>, 0, "the par bonus is climbing first"
    assert_operator early[:tally_shown_bonus], :<, 30_000
    assert_equal 0, early[:_kill_shown], "and the kills wait their turn"
    assert_equal 30_000, done[:tally_shown_bonus]
    assert_equal [50, 50], [done[:_kill_shown], done[:_secret_shown]]
  end

  # Each hundred per cent lands on the bonus as its figure finishes (wl_inter.cpp), not before.
  def test_a_hundred_per_cent_lands_on_the_bonus_as_its_figure_finishes
    floor = { kills: 1, kill_total: 1 }

    assert_equal 0, finish_floor(frames: LIFT_ARRIVES + 5, **floor)[:tally_shown_bonus]
    assert_equal 10_000, finish_floor(**floor)[:tally_shown_bonus]
  end

  # GivePoints comes after every figure, so the score does not move while they climb.
  def test_the_score_is_paid_when_the_figures_finish
    floor = { score: 2_345, kills: 1, kill_total: 1 }

    assert_equal 2_345, finish_floor(frames: LIFT_ARRIVES + 5, **floor)[:score]
    assert_equal 12_345, finish_floor(**floor)[:score]
  end

  # The `goto done` in each loop of LevelCompleted: a press finishes the count, and a SECOND press
  # is what leaves. So tapping fire does not throw the screen away unread.
  def test_a_press_during_the_count_finishes_it_and_stays
    run = finish_floor(pressing: press_on(LIFT_ARRIVES + 2), frames: LIFT_ARRIVES + 5, kills: 1, kill_total: 1)

    assert_equal 1, run[:tally_showing], "the screen is still up"
    assert_equal 100, run[:_kill_shown], "with every figure at its end"
    assert_equal 10_000, run[:tally_shown_bonus]
    assert_equal 10_000, run[:score], "and paid, as if it had counted all the way"
  end

  def test_a_second_press_leaves
    run = finish_floor(pressing: press_on(LIFT_ARRIVES + 2, LIFT_ARRIVES + 4), frames: LIFT_ARRIVES + 7)

    assert_equal 0, run[:tally_showing]
    assert_equal NEXT_FLOOR_STEPS, run[:trail]
  end

  # The figures keep real time however long a pass takes, so a repaint that runs late does not make
  # the count drag: the same number of passes, each two frames long, climbs at least twice as far.
  def test_the_count_keeps_real_time_when_a_pass_runs_late
    program = tally_cartridge(kills: 1, kill_total: 1, secrets: 0, secret_total: 0, treasures: 0, treasure_total: 0,
                              score: 0, keys: 0, index: 0, played: 90 * SECONDS)
    lift = ->(f) { f == LIFT_ARRIVES ? [:l] : [] }
    prompt = Reference.new.input_each_frame(&lift).run(program, frames: 7)
    late = Reference.new.input_each_frame(&lift).frames_each_pass { 2 }.run(program, frames: 7)

    assert_operator late[:_kill_shown], :>=, 2 * prompt[:_kill_shown]
  end

  # --- the clock and par ---

  # timeleft * PAR_AMOUNT, and par on the first floor of the first episode is a minute and a half.
  def test_the_seconds_left_of_par_are_worth_five_hundred_points_each
    run = finish_floor(played: 60 * SECONDS)

    assert_equal 30, run[:tally_time_left]
    assert_equal 15_000, run[:tally_bonus]
    assert_equal 15_000, run[:score]
  end

  # `TimeCount < par` is what the original tests, so par itself earns nothing and the last part of
  # a second is rounded away from what you took: a whole second is left until par has arrived.
  def test_par_itself_earns_nothing_and_a_tic_under_it_earns_a_second
    assert_equal 0, finish_floor(played: 90 * SECONDS)[:tally_time_left]
    assert_equal 1, finish_floor(played: (90 * SECONDS) - 1)[:tally_time_left]
  end

  def test_a_slow_floor_earns_nothing_and_takes_nothing_away
    run = finish_floor(played: 200 * SECONDS, kills: 1, kill_total: 1)

    assert_equal 10_000, run[:tally_bonus]
  end

  # parTimes, in wl_inter.cpp, by episode and floor: the first floor with a par, the last and
  # longest, the shortest, and one from the middle.
  def test_par_is_the_originals_for_each_floor
    { 0 => 90, 15 => 360, 33 => 60, 57 => 510 }.each do |index, par|
      assert_equal 1, finish_floor(index: index, played: (par * SECONDS) - 1)[:tally_time_left], "floor #{index}"
    end
  end

  # The bonus and the score are the same sum, and the worst case for its width: every second of
  # the longest par left, with all three at a hundred.
  def test_the_largest_bonus_there_is_fits
    run = finish_floor(index: 57, played: 0, kills: 1, kill_total: 1, secrets: 1, secret_total: 1,
                       treasures: 1, treasure_total: 1)

    assert_equal 285_000, run[:tally_bonus]
    assert_equal 285_000, run[:tally_shown_bonus]
  end

  # sec > 99 * 60 is held there. The time shown and the record that goes to the screen at the end
  # of the episode both come from that held number.
  def test_the_clock_stops_at_ninety_nine_minutes
    run = finish_floor(played: 40_000)

    assert_equal 9, run[:tally_minutes], "forty thousand seventieths is nine minutes thirty-one"
    assert_equal 31, run[:tally_seconds]

    capped = finish_floor(played: 100 * 60 * SECONDS, frames: LIFT_ARRIVES + 2)
    assert_equal 99, capped[:tally_minutes]
    assert_equal 0, capped[:tally_seconds]
  end

  # --- a floor from the ninth on has no figures ---

  def test_a_secret_floor_pays_at_once_with_nothing_to_count
    run = finish_floor(index: 9, frames: LIFT_ARRIVES + 2)

    assert_equal 15_000, run[:score]
    assert_equal 15_000, run[:tally_shown_bonus]
  end

  def test_one_press_leaves_a_secret_floor
    run = finish_floor(index: 9, pressing: press_on(LIFT_ARRIVES + 2), frames: LIFT_ARRIVES + 5)

    assert_equal 0, run[:tally_showing]
  end

  # IN_StartAck: a button already down as the screen starts does not count, or a player with a
  # finger on fire would never see the screen at all.
  def test_a_button_held_from_before_does_not_move_on
    run = finish_floor(pressing: ->(_) { [:b] })

    assert_equal 1, run[:tally_showing]
  end

  # gamestate.oldscore = gamestate.score comes AFTER LevelCompleted, so the bonus is safe: dying
  # on the next floor puts the score back to what you arrived with, and that includes it.
  def test_the_bonus_is_kept_by_a_death_on_the_next_floor
    run = finish_floor(pressing: press_on(5, 8), frames: 12, kills: 1, kill_total: 1)

    assert_equal 10_000, run[:floor_score]
  end

  # --- in the game's own numerals ---

  # THE PAR TIME IS WRITTEN IN THE GAME'S OWN NUMERALS, read back by matching each place of the
  # clock against VGAGRAPH's ten numeral pictures. The first floor's par is a minute and a half,
  # which the original writes 01:30 (wolf4sdl: wl_inter.cpp, parTimes), so all four places show,
  # the leading nought too. The lift is ridden on the real first floor (LiftScene).
  def test_the_par_time_is_written_in_the_games_own_numerals
    program = Wolf3D::GAME.checked_program(err: nil, settings: { floors: 1, screen: "playing", start: LiftScene.start })
    screen = Reference.new.input_each_frame { |frame| LiftScene.keys(frame) }
                      .run(program, frames: LiftScene::TALLY_FRAMES).screen
    places = [0, 1, 3, 4].map { |place| numeral_at(screen, Tally::CLOCK_X + (place * Wolf3D::BigLettering::LETTER), Tally::PAR_Y) }

    assert_equal [0, 1, 3, 0], places
  end

  private

  # Which of the ten numeral pictures is drawn with its corner at +x+, +y+, or nil for none.
  def numeral_at(screen, x, y)
    side = Wolf3D::BigLettering::LETTER
    drawn = (0...side).flat_map { |row| (0...side).map { |col| screen.pixel(x + col, y + row) } }
    (0..9).find { |digit| numeral_picture(digit) == drawn }
  end

  def numeral_picture(digit)
    (Ractor.current[:tally_numerals] ||= Wolf3D::MenuArt.of(Wolf3D.vgagraph).then do |art|
      (0..9).map { |n| art.picture(:"tally_#{n}", Wolf3D::Palette.game)[:data] }
    end)[digit]
  end
end
