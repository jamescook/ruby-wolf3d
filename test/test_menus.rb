# frozen_string_literal: true

require "set"
require_relative "test_helper"

# EVERYTHING YOU MEET BEFORE YOU PLAY, walked with scripted input and read back off the screen.
#
# THE FIXTURE'S PICTURES NAME THEMSELVES, which is what makes this readable without a copy of
# the game. Every pixel of a fixture picture holds its own picture's NUMBER plus how far into
# the picture it is, so the first pixel of one IS its number — and a test can therefore say
# "the gun is here" or "this is the third portrait" rather than only "something was drawn".
# That is a stronger reading than real art would give: real art has no such signature.
class TestMenus < Minitest::Test
  include Wolf3DTest

  Menus = Wolf3D::Menus
  FirstPerson = Wolf3D::FirstPerson
  Release = Wolf3D::Fixture::Release
  Floors = Wolf3D::Floors
  Names = Wolf3D::Vgagraph::WL6_NAMES

  ROW = Menus::ROW_STEP

  # Where the main menu's own pictures can be, which is under its heading plate: the plate is
  # painted from the same numbers the gun is, so a search over the whole screen would find the
  # gun's colours in it.
  UNDER_THE_HEADING = 56

  # --- WHERE THE CARTRIDGE BOOTS -------------------------------------------------------------

  def test_the_cartridge_boots_on_the_rating_box
    run = play(frames: 2)

    assert_equal Menus::NOTICE, run[:screen]
    assert showing?(run, :notice), "the rating box should be the first thing on screen"
  end

  # LEFT ALONE, THE STILL SCREENS FOLLOW ONE ANOTHER FOR EVER. The rating box is shown once and
  # never again; from there it is the title and the credits, round and round.
  def test_the_still_screens_follow_one_another_and_come_round_again
    title = play(frames: Menus::NOTICE_FRAMES + 1)

    assert_equal Menus::TITLE, title[:screen]
    assert showing?(title, :title), "the title screen should follow the rating box"

    credits = play(frames: Menus::NOTICE_FRAMES + Menus::TITLE_FRAMES + 1)

    assert_equal Menus::CREDITS, credits[:screen]
    assert showing?(credits, :credits), "the credits should follow the title screen"

    round = play(frames: Menus::NOTICE_FRAMES + Menus::TITLE_FRAMES + Menus::CREDITS_FRAMES + Menus::SCORES_FRAMES + 1)

    assert_equal Menus::TITLE, round[:screen], "and then round to the title again"
  end

  # ANY BUTTON AT ALL OPENS THE MENU, which is the only way into Wolfenstein. Every one of the
  # console's ten is tried, because "any" is the whole promise.
  BUTTONS = %i[a b start select left right up down l r].freeze

  def test_any_button_at_all_opens_the_menu
    BUTTONS.each do |button|
      run = play(frames: 4) { |f| f >= 2 ? [button] : [] }

      assert_equal Menus::MENU, run[:screen], "#{button} should have opened the menu"
    end
  end

  # A press on the very frame a screen's time runs out means the menu, not the next screen.
  def test_a_press_as_the_time_runs_out_opens_the_menu_rather_than_moving_on
    run = play(frames: Menus::NOTICE_FRAMES) { |f| f == Menus::NOTICE_FRAMES ? [:a] : [] }

    assert_equal Menus::MENU, run[:screen]
  end

  # --- THE MENU ITSELF -----------------------------------------------------------------------

  def test_the_gun_points_at_the_row_you_are_on
    run = at_the_menu

    assert_equal 0, run[:__menu_main], "the cursor starts on the first row"
    refute_nil gun_row(run), "the gun should be beside it"
  end

  # A ROW THAT CANNOT BE PICKED IS STEPPED OVER, not landed on. SAVE GAME is that row until a game
  # is on, so the press down from LOAD GAME moves the gun TWO rows.
  def test_the_row_that_cannot_be_picked_is_stepped_over
    before = at_the_menu { |f| f == 4 ? [:down] : [] }
    after = at_the_menu(frames: 10) { |f| [4, 8].include?(f) ? [:down] : [] }

    assert_equal 3, after[:__menu_main], "the third row cannot be picked, so this is the fourth"
    assert_equal (2 * ROW), gun_row(after) - gun_row(before), "and the gun moved two rows with it"
  end

  # THE SELECTOR IS A GUN AND IT BLINKS: itself for a second, then the same gun with its muzzle
  # flashing. A steady cursor is the wrong look, and this is what says which picture is up.
  def test_the_gun_blinks
    steady = at_the_menu

    assert showing?(steady, :menu_gun, from: UNDER_THE_HEADING), "the gun starts unfired"

    flashing = at_the_menu(frames: Menus::BLINK_ON + 3)

    assert showing?(flashing, :menu_gun_firing, from: UNDER_THE_HEADING),
           "and flashes its muzzle a second in"

    round = at_the_menu(frames: Menus::BLINK_ON + Menus::BLINK_OFF + 3)

    assert showing?(round, :menu_gun, from: UNDER_THE_HEADING), "and then goes back"
  end

  # PICKING A ROW FADES THE SCREEN AWAY FIRST, and the screen behind it is not shown until the
  # fade has arrived — which is what makes a change of screen one movement rather than a cut.
  def test_picking_a_row_fades_before_it_moves
    fading = at_the_menu(frames: 8) { |f| f == 4 ? [:a] : [] }

    assert_equal Menus::MENU, fading[:screen], "still on the menu while the screen goes"
    assert_equal Menus::DIFFICULTY, fading[:_screen_going_to], "with the next one waiting"

    arrived = at_the_menu(frames: 40) { |f| f == 4 ? [:a] : [] }

    assert_equal Menus::DIFFICULTY, arrived[:screen], "and shown once the fade has arrived"
    assert_equal(-1, arrived[:_screen_going_to], "with nothing left waiting")
  end

  # ONE ROW FOR ALL OF SOUND, which is the whole of what the original's twelve-row sound menu means
  # on hardware that is none of the three sound cards it offered. It goes round three settings.
  def test_the_sound_row_goes_round_its_three_settings
    both = at_the_menu(frames: 30) { |f| [4, 8].include?(f) ? [:down] : (f == 20 ? [:a] : []) }

    assert_equal 3, both[:__menu_main], "the fourth row is SOUND"
    assert_equal Wolf3D::Music::EFFECTS_AND_MUSIC, both[:sound_on], "from effects only, one press adds the music"

    off = at_the_menu(frames: 40) do |f|
      next [:down] if [4, 8].include?(f)

      [20, 30].include?(f) ? [:a] : []
    end

    assert_equal Wolf3D::Music::OFF, off[:sound_on], "a second press turns everything off"

    only = at_the_menu(frames: 50) do |f|
      next [:down] if [4, 8].include?(f)

      [20, 30, 40].include?(f) ? [:a] : []
    end

    assert_equal Wolf3D::Music::EFFECTS_ONLY, only[:sound_on], "and a third comes back round"
  end

  # THE SETTING OUTLIVES THE POWER, as it does in the original's config file.
  def test_the_sound_setting_survives_the_power_going_off
    image = SaveImage.new
    presses = ->(f) { { 2 => [:a], 4 => [:down], 8 => [:down], 20 => [:a] }.fetch(f, []) }
    Reference.new(save: image).input_each_frame(&presses).run(self.class.program, frames: 30)
    again = Reference.new(save: image).run(self.class.program, frames: 2)

    assert_equal Wolf3D::Music::EFFECTS_AND_MUSIC, again[:sound_on]
  end

  # --- THE DIFFICULTY SCREEN -----------------------------------------------------------------

  # THE PORTRAIT BESIDE THE ROWS IS THE POINT OF THIS SCREEN: BJ gets grimmer as you move down
  # it, so the picture answers the question the rows are asking.
  # ONE TAP PER ROW, on frames far enough apart that each is its own press. A held button walks
  # the list on its own clock, which is a different thing and is the menu verb's to test.
  def taps_from(frame, count) = (1..count).map { |n| frame + (n * 4) }

  def test_the_portrait_changes_as_you_move_down_the_difficulties
    Menus::DIFFICULTIES.each_with_index do |(_, _, portrait), n|
      taps = taps_from(40, n)
      run = at_the_difficulty(frames: 44 + (n * 4)) { |f| taps.include?(f) ? [:down] : [] }

      assert_equal n, run[:__menu_difficulty], "the cursor should be on row #{n}"
      assert showing?(run, portrait), "row #{n} should show #{portrait}"
    end
  end

  # PICKING ONE STARTS THE GAME, on the setting that row names. What the game then DOES with the
  # setting — which guards a floor stands up, what a shot takes off you — is held to its own
  # tests in test_difficulty.rb; this is the screen's half of it, that the right number is
  # written by the right row.
  def test_picking_a_difficulty_starts_the_game_on_that_setting
    run = at_the_difficulty(frames: 90) { |f| f == 44 ? [:a] : [] }

    assert_equal Menus::PLAYING, run[:screen], "picking a difficulty leaves you in the game"
    assert_equal 1, run[:_in_game]
    assert_equal Wolf3D::Guards.number_of(:baby), run[:difficulty],
                 "the cursor starts on the first row, so that is the setting written"
  end

  # ...and each of the four rows writes its own setting rather than its position. Walking down
  # the list and pressing A is the only way to say that from the outside.
  def test_each_row_writes_the_setting_it_names
    Wolf3D::Guards::SETTINGS.each_with_index do |how, n|
      taps = taps_from(40, n)
      picking = 44 + (n * 4)
      run = at_the_difficulty(frames: picking + 46) do |f|
        taps.include?(f) ? [:down] : (f == picking ? [:a] : [])
      end

      assert_equal Wolf3D::Guards.number_of(how), run[:difficulty],
                   "row #{n} should start a #{how} game"
    end
  end

  def test_a_game_begins_with_a_fresh_player
    run = at_the_difficulty(frames: 90) { |f| f == 44 ? [:a] : [] }

    assert_equal Wolf3D::FirstPerson::START_HEALTH, run[:health]
    assert_equal Wolf3D::Lives::START, run[:lives]
    assert_equal 0, run[:score]
  end

  # --- THE PAUSE MENU, WHICH IS THE MAIN MENU AGAIN ------------------------------------------

  def test_start_pauses_the_game_into_the_same_menu
    run = playing(frames: 100) { |f| f == 95 ? [:start] : [] }

    assert_equal Menus::MENU, run[:screen], "START opens the menu over the game"
    assert_equal 1, run[:_in_game], "and the menu knows there is a game behind it"
  end

  # The lever on frame 2, and by this frame the lift is in and the screen between floors is up.
  LIFT_IN = 2 + Wolf3D::FirstPerson::LIFT_WAIT + 4

  # THE SCREEN AT THE BOTTOM OF A LIFT IS NOT A PAUSE. Ending the game from a menu opened over it
  # would leave it up, with nothing to take it down.
  def test_start_does_nothing_on_the_screen_between_floors
    run = play(frames: LIFT_IN + 6, program: self.class.with_a_lift) do |f|
      { 2 => [:a], LIFT_IN + 2 => [:start] }.fetch(f, [])
    end

    assert_equal 1, run[:_tally_showing], "the screen is up"
    assert_equal Menus::PLAYING, run[:screen], "and START left it there"
  end

  # THE GAME'S OWN LETTERING, pixel for pixel: each fixture picture is different all over, so one
  # read at the wrong number, or drawn in the wrong place, does not match.
  def test_the_screen_between_floors_is_written_in_the_games_own_lettering
    run = play(frames: LIFT_IN + 6, program: self.class.with_a_lift) { |f| f == 2 ? [:a] : [] }
    tally = Wolf3D::Tally
    ones = tally::FIGURES_X + (2 * tally::LETTER)

    assert_equal lettering(:tally_percent), picture_at(run, tally::PERCENT_X, tally::RATIOS_Y)
    assert_equal lettering(:tally_0), picture_at(run, ones, tally::RATIOS_Y), "the ones place of nought per cent"
    # "FLOOR 1" is seven letters, so 112 across and starting at 64, and the number is the seventh.
    assert_equal lettering(:tally_1), picture_at(run, 160, tally::FLOOR_Y), "the floor's number"
    assert_equal lettering(:tally_colon), picture_at(run, tally::CLOCK_X + (2 * tally::LETTER), tally::TIME_Y)
    assert_equal lettering(:tally_colon), picture_at(run, tally::CLOCK_X + (2 * tally::LETTER), tally::PAR_Y)
    assert_equal lettering(:tally_t), picture_at(run, tally::CLOCK_X - tally::GAP - (4 * tally::LETTER), tally::TIME_Y)
  end

  # EIGHT ROWS OF BIG LETTERS FILL THE VIEW EXACTLY, so the last one must not run under the bar.
  def test_the_last_row_between_floors_ends_where_the_bar_begins
    tally = Wolf3D::Tally

    assert_equal Wolf3D::FirstPerson::VIEW_H, tally::RATIOS_Y + (tally::RATIOS.length * tally::LETTER)
  end

  # NOR IS A DEATH. It stops drawing the view so the red can build up on what is there, so a menu
  # opened over it would stay on screen with the dots landing on it. The original reads no keys
  # until a death is over (Died, wl_game.cpp).
  MID_DEATH = 140

  def test_start_does_nothing_while_you_are_dying
    dying = play(frames: MID_DEATH, program: self.class.in_a_ring_of_guards)

    assert_operator dying[:dying], :>, Wolf3D::Dying::ALIVE, "the ring has killed you by now"

    run = play(frames: MID_DEATH + 2, program: self.class.in_a_ring_of_guards) do |f|
      f == MID_DEATH ? [:start] : []
    end

    assert_equal Menus::PLAYING, run[:screen]
  end

  def lettering(name) = self.class.art.picture(name, palette)[:data]

  def picture_at(run, left, top)
    (0...Wolf3D::Tally::LETTER).flat_map do |y|
      (0...Wolf3D::Tally::LETTER).map { |x| run.screen.pixel(left + x, top + y) }
    end
  end

  # THE LAST ROW GOES BACK TO WHAT YOU CAME FROM: the attract loop from the title, and the game
  # from a pause. One row, two meanings, which is exactly what the original's pause menu is.
  def test_the_last_row_goes_back_to_the_game_when_there_is_one
    run = playing(frames: 180) do |f|
      next [:start] if f == 95
      next [:down] if [100, 105, 110, 115, 120].include?(f)

      f == 140 ? [:a] : []
    end

    assert_equal 5, run[:__menu_main], "the last row"
    assert_equal Menus::PLAYING, run[:screen], "and it puts you back in the game"
  end

  # THE MENU PAINTS OVER THE BAR'S ROWS AND NOTHING ON THE BAR HAS CHANGED, so the bar cannot notice
  # for itself. Standing still in an empty room, the bar after the pause is the bar before it.
  def test_coming_back_from_the_menu_puts_the_bar_back
    before = playing(frames: 90)
    back = playing(frames: 180) do |f|
      next [:start] if f == 95
      next [:down] if [100, 105, 110, 115, 120].include?(f)

      f == 140 ? [:a] : []
    end

    assert_equal Menus::PLAYING, back[:screen]
    assert_equal 0, pixels_of_the_bar_changed(before, back)
    assert_equal 0, back[:__shown_status_bar_todo], "and with both pages painted it is left alone"
  end

  # BOTH PAGES, which is the half only the console can answer: the interpreter keeps one picture,
  # so a bar painted once reads right there and shows the menu's leftovers every other frame here.
  # The script is START, down five times to the last row, A, and the fade back.
  def test_the_console_shows_the_bar_on_both_pages_after_the_menu
    backend = GBA.new
    rom = ROM.assemble(backend.lower(self.class.booting_into_the_game), title: "MENU")
    keys = { 20 => Constants::KEY_START, 24 => Constants::KEY_DOWN, 28 => Constants::KEY_DOWN, 32 => Constants::KEY_DOWN,
             36 => Constants::KEY_DOWN, 40 => Constants::KEY_DOWN, 46 => Constants::KEY_A }
    script = ->(frame) { keys.fetch(frame, 0) }

    bars = [90, 91].map do |frames|
      gba = Verifier.new(rom, frames: frames, vars: backend.var_addresses, keys: script)

      assert_equal Menus::PLAYING, gba.var(:screen), "frame #{frames} should be back in the game"
      (0...FirstPerson::ACROSS).step(2).sum do |x|
        (FirstPerson::VIEW_H...FirstPerson::DOWN).step(2).count do |y|
          gba.pixel_gba(x, y) == Wolf3D::Palette.game[Wolf3D::StatusBar::GROUND]
        end
      end
    end

    assert_operator bars.first, :>, 0, "the bar's ground should be on screen"
    assert_equal bars.first, bars.last, "and on both pages, or it flickers with what the menu left"
  end

  # ...and the same again for a new game after an ended one, which starts on the same figures.
  def test_a_new_game_after_ending_one_has_a_bar
    before = playing(frames: 90)
    again = playing(frames: 280) { |f| [95, 120, 170, 180, 220].include?(f) ? [f == 95 ? :start : :a] : [] }

    assert_equal Menus::PLAYING, again[:screen]
    assert_equal 0, pixels_of_the_bar_changed(before, again)
  end

  def pixels_of_the_bar_changed(one, other)
    (FirstPerson::VIEW_H...FirstPerson::DOWN).sum do |y|
      (0...FirstPerson::ACROSS).count { |x| one.screen.pixel(x, y) != other.screen.pixel(x, y) }
    end
  end

  def test_the_first_row_ends_the_game_and_leaves_you_at_the_title
    run = playing(frames: 180) { |f| f == 95 ? [:start] : (f == 120 ? [:a] : []) }

    assert_equal Menus::TITLE, run[:screen], "ending a game leaves you at the title"
    assert_equal 0, run[:_in_game], "with no game behind the menu any more"
  end

  # A BUTTON STILL DOWN FROM THE MENU IS NOT A NEW PRESS. The original notes which buttons are
  # down as a still screen starts and waits for one that was not (IN_StartAck and IN_CheckAck,
  # id_in.cpp), so a player who ends the game and keeps A held a moment stays at the title.
  def test_a_button_held_on_from_the_menu_does_not_open_it_again
    run = playing(frames: 180) { |f| f == 95 ? [:start] : (f >= 120 ? [:a] : []) }

    assert_equal Menus::TITLE, run[:screen]
  end

  # --- THE EPISODE LIST ----------------------------------------------------------------------

  # A CARTRIDGE WITH ONE EPISODE HAS NOTHING TO ASK, so it does not ask. That is not a screen
  # left out: a list with one pickable row is a question with one answer.
  def test_one_episode_means_no_episode_list_at_all
    run = at_the_menu(frames: 40) { |f| f == 4 ? [:a] : [] }

    assert_equal Menus::DIFFICULTY, run[:screen], "NEW GAME goes straight to the difficulty"
  end

  def test_a_cartridge_with_two_episodes_asks_which_one
    run = play(frames: 40, program: self.class.two_episodes) do |f|
      f == 2 || f == 6 ? [:a] : []
    end

    assert_equal Menus::EPISODES, run[:screen]
  end

  # THE LIST IS BUILT FROM WHAT THE CARTRIDGE ACTUALLY HOLDS, not from a fixed six. A row for an
  # episode that is not here cannot be picked, so the cursor steps over it — which on a
  # two-episode cartridge means down from the second row wraps straight back to the first.
  def test_only_the_episodes_the_cartridge_holds_can_be_picked
    second = at_the_episodes(frames: 40) { |f| f == 30 ? [:down] : [] }

    assert_equal 1, second[:__menu_episodes], "down moves to the second episode"

    wrapped = at_the_episodes(frames: 44) { |f| [30, 34].include?(f) ? [:down] : [] }

    assert_equal 0, wrapped[:__menu_episodes], "and down again steps over the four that are not here"
  end

  def test_the_episode_you_pick_is_the_floor_the_game_starts_on
    run = at_the_episodes(frames: 90) { |f| f == 30 ? [:down] : (f == 40 ? [:a] : []) }

    assert_equal Menus::DIFFICULTY, run[:screen], "picking an episode asks how tough you are"
    assert_equal 1, run[:_start_floor], "and remembers which floor that episode begins at"
  end

  # --- BOOTING STRAIGHT TO A SCREEN ------------------------------------------------------------

  # A MEASURING DIAL, not a way to play: the attract loop takes a quarter of a minute to come
  # round and the episode list needs a cartridge with two episodes on it, so a cartridge that
  # boots on the screen you want to look at is worth being able to build.
  def test_a_cartridge_can_be_built_to_boot_on_any_screen
    run = play(frames: 2, program: self.class.booting_on_the_difficulty)

    assert_equal Menus::DIFFICULTY, run[:screen]
    assert showing?(run, Menus::DIFFICULTIES.first.last), "with the first portrait beside the rows"
  end

  def test_every_screen_has_a_name_and_a_name_nobody_knows_is_a_friendly_error
    assert_equal Menus::CREDITS, Menus.screen_named("credits")
    assert_equal Menus::NOTICE, Menus.screen_named(nil), "nothing said means the beginning"

    error = assert_raises(ArgumentError) { Menus.screen_named("attract") }

    assert_match(/no screen called/, error.message)
    assert_match(/credits/, error.message, "and it should say what the screens are")
  end

  # A cartridge asked to boot on a screen it does not carry would boot to nothing at all.
  def test_a_one_episode_cartridge_cannot_be_told_to_boot_on_the_episode_list
    error = assert_raises(ArgumentError) do
      self.class.cartridge(episodes: 1, starting_on: Menus::EPISODES)
    end

    assert_match(/no episode list/, error.message)
    assert_match(/more floors/, error.message, "and it should say how to fix it")
  end

  # --- THE GAME'S OWN LETTERING ---------------------------------------------------------------

  # THE ROWS ARE WRITTEN IN WOLFENSTEIN'S OWN ALPHABET, which is the whole of what this bead was
  # about. Checked against a real copy, because the fixture's alphabet is two characters wide on
  # purpose — it is there to catch a reader that assumes one width for a whole font.
  def test_the_rows_are_written_in_the_games_own_alphabet
    game_data_or_skip
    small = Wolf3D.vgagraph.font(0)
    art = Wolf3D::MenuArt.of(Wolf3D.vgagraph)

    assert_equal small.glyphs, art.font(0), "the menu's alphabet is the release's own"
    assert_operator small.glyphs.length, :>, 40, "and it is a whole alphabet"
    assert_operator small.width("M"), :>, small.width("I"), "and a proportional one"
  end

  # NOT ONE COLUMN IS LOST, which is why the window moves instead of the picture shrinking. The
  # credits' writing reaches from column 9 to column 313 — three hundred and five columns of it
  # for a screen two hundred and forty wide — so ANY squeeze across takes pixels out of the
  # words themselves, and every stroke there is two pixels wide.
  def test_the_full_screen_pictures_keep_every_column_they_were_painted_with
    game_data_or_skip
    art = Wolf3D::MenuArt.of(Wolf3D.vgagraph)

    %i[title credits].each do |name|
      painted = Wolf3D.vgagraph.picture(name)
      cut = art.picture(name, Wolf3D.palette)

      assert_equal painted.width, cut[:width], "#{name}: every column survives"
      assert_equal Menus::DOWN, cut[:height], "#{name}: only the height comes down"
      assert_operator cut[:width], :>, Menus::ACROSS, "#{name}: which is why it has to drift"
    end
  end

  # ...AND THE ROWS THAT GO ARE THE EMPTY ONES, so nothing of the writing is lost down the
  # screen either. Seventy-two of the credits' two hundred rows carry nothing at all and only
  # forty need to go — so every row that arrives is a row that was painted, whole. Nothing is
  # blended and nothing is invented.
  def test_every_row_that_arrives_is_a_painted_row_whole
    game_data_or_skip
    painted = Wolf3D.vgagraph.picture(:credits)
    cut = Wolf3D::MenuArt.of(Wolf3D.vgagraph).picture(:credits, Wolf3D.palette)
    was_painted = (0...painted.height).map { |y|
      (0...painted.width).map { |x| Wolf3D.palette[painted[x, y]] }
    }.to_set

    cut[:data].each_slice(cut[:width]).with_index do |row, n|
      assert_includes was_painted, row, "row #{n} was not painted like that"
    end
  end

  # THE WINDOW REALLY WALKS, and what it shows is exactly what was painted where it is looking.
  # Read off the screen against the picture rather than off the variable that moves it, because
  # a window that moves and draws the wrong thing is the failure worth catching.
  def test_the_window_drifts_across_a_picture_wider_than_the_screen
    cut = self.class.art.picture(:credits, palette)
    seen = [2, 60, 200].map do |frame|
      run = play(frames: frame, program: self.class.on_the_credits)

      assert_equal Menus::CREDITS, run[:screen]
      assert_equal cut[:data][run[:_screen_pan] * 2, Menus::ACROSS],
                   (0...Menus::ACROSS).map { |x| run.screen.pixel(x, 0) },
                   "frame #{frame} shows the painted columns the window is over"
      run[:_screen_pan]
    end

    assert_equal 0, seen.first, "it starts at the left edge"
    assert_operator seen.last, :>, seen.first, "and has walked right by the time it settles"
  end

  # --- ON THE CONSOLE --------------------------------------------------------------------------

  # THE SAME WALK ON REAL HARDWARE. The screen is read out of the memory it lives in rather than
  # off the picture, because what this is proving is that the state machine runs — the pictures
  # are the interpreter's business and it has already said.
  def test_the_menu_opens_on_the_console
    backend = GBA.new
    rom = ROM.assemble(backend.lower(self.class.program), title: "MENU")
    gba = Verifier.new(rom, frames: 6, vars: backend.var_addresses,
                                     keys: ->(frame) { frame >= 3 ? Constants::KEY_A : 0 })

    assert_equal Menus::MENU, gba.var(:screen), "a press should open the menu on the console"
    refute gba.all_black?, "and the menu should be on the screen"
  end

  private

  # --- READING THE SCREEN ----------------------------------------------------------------------

  # WHERE THIS PICTURE IS ON SCREEN, or nil. Every pixel of a fixture picture holds its own
  # picture's NUMBER plus how far into the picture it sits, so a picture's TOP ROW is its number
  # and the numbers counting on from it — a run no other picture here can carry, because two
  # pictures whose numbers differ by an odd amount can never line up along one.
  #
  # ONE PIXEL WILL NOT DO, and finding that out is what this comment is for. A picture of three
  # hundred pixels uses very nearly every number there is, so the first pixel of one turns up
  # somewhere inside another — and a test looking for a single pixel passes with the WRONG
  # picture on screen. Swapping the gun for the gun firing was invisible until this was a run.
  def where_is(run, name, from: 0)
    wanted = top_row_of(name)
    (from...Menus::DOWN).each do |y|
      (0..(Menus::ACROSS - wanted.length)).each do |x|
        next unless run.screen.pixel(x, y) == wanted.first
        return [x, y] if wanted.each_with_index.all? { |ink, n| run.screen.pixel(x + n, y) == ink }
      end
    end
    nil
  end

  # A PICTURE WIDER THAN THE SCREEN shows a WINDOW of itself, so it is never all on screen at
  # once and there is no run to go looking for. What is on screen is the slice the window is
  # over, and that is what gets compared.
  def showing?(run, name, from: 0)
    row = top_row_of(name)
    return !where_is(run, name, from: from).nil? if row.length <= Menus::ACROSS

    at = run[:_screen_pan] * 2
    (0...Menus::ACROSS).all? { |x| run.screen.pixel(x, 0) == row[at + x] }
  end

  # The first row of a picture as the cartridge holds it — which, for the two painted for a
  # bigger screen than this one, is the first row that survived being squeezed onto it.
  def top_row_of(name)
    @top_rows ||= {}
    @top_rows[name] ||= begin
      cut = self.class.art.picture(name, palette)
      cut[:data].first(cut[:width])
    end
  end

  # The row the gun is drawn on, whichever of its two pictures is showing — which is the row
  # the cursor is pointing at.
  def gun_row(run)
    found = where_is(run, :menu_gun, from: UNDER_THE_HEADING) ||
            where_is(run, :menu_gun_firing, from: UNDER_THE_HEADING)
    found&.last
  end

  # --- WALKING THE SCREENS ---------------------------------------------------------------------

  def play(frames:, program: self.class.program, &script)
    runner = Reference.new
    runner.input_each_frame(&script) if script
    runner.run(program, frames: frames)
  end

  # A press on frame 2 opens the menu; anything the caller wants happens after that.
  def at_the_menu(frames: 6, &script)
    play(frames: frames) { |f| f == 2 ? [:a] : (script ? script.call(f) : []) }
  end

  # ...and one more on frame 6 takes NEW GAME, which on a one-episode cartridge is the
  # difficulty screen. The fade takes ten frames, so nothing is asked of it before frame 40.
  def at_the_difficulty(frames: 40, &script)
    play(frames: frames) { |f| [2, 6].include?(f) ? [:a] : (script ? script.call(f) : []) }
  end

  # The same walk on the two-episode cartridge, which asks which episode first.
  def at_the_episodes(frames: 30, &script)
    play(frames: frames, program: self.class.two_episodes) do |f|
      [2, 6].include?(f) ? [:a] : (script ? script.call(f) : [])
    end
  end

  # ...and all the way into a game, so a pause has something to pause.
  def playing(frames:, &script)
    play(frames: frames) do |f|
      next [:a] if [2, 6, 44].include?(f)

      script ? script.call(f) : []
    end
  end

  # --- THE CARTRIDGES THIS FILE PLAYS ----------------------------------------------------------

  # ONE RELEASE AND TWO CARTRIDGES FOR THE WHOLE FILE. Packing the art and building the game is
  # the only slow thing here and nothing in the tests changes either.
  #
  # Kept per Ractor rather than on the class, because the suite runs in several and a worker may
  # not write to a class. Each worker that runs a test from this file builds them once.
  class << self
    include Wolf3DTest::Field

    # Enough walls for the lever's pictures, which sit near the end of a release's list of them.
    def release
      Ractor.current[:menus_release] ||= Release.new(set: "WL6", walls: (Wolf3D::Elevator::PULLED * 2) + 2)
    end

    def fixture = release
    def pictures = Ractor.current[:menus_pictures] ||= release.pictures
    def art = Ractor.current[:menus_art] ||= Wolf3D::MenuArt.of(pictures)
    def vswap = Ractor.current[:menus_vswap] ||= Wolf3D::Vswap.new(release.files["VSWAP"])
    def program = Ractor.current[:menus_program] ||= cartridge(episodes: 1)
    def two_episodes = Ractor.current[:menus_two_episodes] ||= cartridge(episodes: 2)

    def booting_on_the_difficulty
      Ractor.current[:menus_booting_on_the_difficulty] ||=
        cartridge(episodes: 1, starting_on: Menus::DIFFICULTY)
    end

    def on_the_credits
      Ractor.current[:menus_on_the_credits] ||= cartridge(episodes: 1, starting_on: Menus::CREDITS)
    end

    # +episodes+ floors, one at the START of each episode — which is what makes the episode
    # list offer that many, since an episode is only offered when its first floor is here.
    def floors_for(episodes)
      level = arena
      Floors.new(Array.new(episodes) { |n| floor_of(level, index: n * Floors::PER_EPISODE) })
    end

    # A floor you start on facing a lever, already in the game: what a test of a floor's end wants.
    def with_a_lift
      Ractor.current[:menus_with_a_lift] ||= begin
        level = arena(player: [4, 8], cells: { [5, 8] => Wolf3D::Elevator::SWITCH })
        cartridge(floors: Floors.new([floor_of(level, index: 0)]), starting_on: Menus::PLAYING)
      end
    end

    def booting_into_the_game
      Ractor.current[:menus_booting_into_the_game] ||= cartridge(episodes: 1, starting_on: Menus::PLAYING)
    end

    # Six guards standing round you, which is the quick way to a death.
    def in_a_ring_of_guards
      Ractor.current[:menus_in_a_ring_of_guards] ||= begin
        ring = [[9, 8, :west], [7, 8, :east], [8, 9, :north], [8, 7, :south], [9, 9, :west], [7, 7, :east]]
        cartridge(floors: Floors.new([floor_of(arena(guards: ring), index: 0)]), starting_on: Menus::PLAYING)
      end
    end

    def cartridge(episodes: 1, floors: floors_for(episodes), starting_on: Menus::NOTICE)
      menu_art = art
      cartridge_of(floors, sound: 1, lettering: menu_art) do |b, view, sound_on|
        menus = Wolf3D::Menus.new(build: b, view: view, art: menu_art, palette: Wolf3D::Palette.game,
                                  sound_on: sound_on, starting_on: starting_on)
        b.game_loop { menus.update }
      end
    end
  end
end
