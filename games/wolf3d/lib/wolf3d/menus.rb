# frozen_string_literal: true

module Wolf3D
  # EVERYTHING YOU MEET BEFORE YOU PLAY: the rating box, the title screen, the credits, the
  # main menu, the episode list, the difficulty screen — and the pause menu, which is the main
  # menu again with two of its rows saying something else.
  #
  # THE ATTRACT LOOP IS THE PART A PLAYER MEETS FIRST and the part nothing else in this game
  # does. Left alone at the boot screen the original cycles through its still screens for ever,
  # and ANY button at any point drops you into the menu. That is the only way in — there is no
  # "press start" anywhere in Wolfenstein.
  #
  # WHAT IS THINNER THAN THE ORIGINAL, and it is worth saying rather than discovering: the
  # original's loop plays a RECORDED DEMO between the still screens, which means replaying a
  # tape of somebody's input frame by frame. There is no such tape here and no machinery to
  # play one, so the loop is the still screens alone. That is the one place this is plainly
  # less than the game it came from.
  #
  # A MENU IS A SCENE and the game is another, which is the whole shape of this file. A scene
  # is a named state that runs once a frame while it is the one you are in, so "which screen am
  # I on" is a variable and "what does this screen do" is a scene — and the game itself is one
  # of them, no different from the menu in front of it.
  #
  # WHAT THE ORIGINAL DOES THAT THIS DOES NOT, both deliberate and both small: the gun does not
  # slide half a step with a sound at each end when you move (it jumps), and picking a row does
  # not play a shot. The blink is here, because the blink is what makes the selector read as a
  # gun rather than an arrow.
  class Menus
    # None is in a saved game. The screen lasts, but loading is done from a menu and goes straight
    # into the game, so a save has no use for which menu was up.
    game_variables :scores_lead_to, :waited, :blink, :song_wanted, :screen, :going_to, :pan, :in_game,
                   :start_floor, saved: false

    # WHICH SCREEN YOU ARE ON, in the order you meet them. The game is the last of them, which
    # is the point: it is a screen like the others.
    NOTICE = 0      # the rating box, shown once at boot
    TITLE = 1       # the title screen
    CREDITS = 2     # who made it
    MENU = 3        # the main menu, which is also the pause menu
    EPISODES = 4
    DIFFICULTY = 5
    PLAYING = 6
    LOADING = 7     # the list of saved games, to load one
    SAVING = 8      # the same list, to save into
    OVERWRITING = 9 # whether to save over the game already in a slot
    SCORES = 10     # the high score table
    NAMING = 11     # the same table, with a name to pick for the row you earned
    WINNING = 12    # the screen that says you won
    ARTICLE = 13    # what the episode ends on

    ACROSS = FirstPerson::ACROSS
    DOWN = FirstPerson::DOWN

    # HOW LONG EACH STILL SCREEN HOLDS, in frames. The original counts in seconds and so does
    # this: fifteen on the title, ten on the credits. The rating box is the one that differs —
    # the original waits for a key and would sit there all day, which is not what a handheld
    # left on the sofa should do.
    SECOND = 60
    NOTICE_FRAMES = 5 * SECOND
    TITLE_FRAMES = 15 * SECOND
    CREDITS_FRAMES = 10 * SECOND
    SCORES_FRAMES = 10 * SECOND

    # THE SELECTOR BLINKS rather than sitting still: the gun for a second, then the same gun
    # with its muzzle flashing for about a ninth of one. A steady cursor is the wrong look.
    BLINK_ON = SECOND
    BLINK_OFF = 7

    # HOW LONG A HELD BUTTON WAITS before it walks to the next row. The original's TicDelay(20)
    # is twenty of its seventy-a-second tics, so a fifth of a second either way.
    HELD_REPEAT = 17

    # THE MENU'S OWN COLOURS, out of Wolfenstein's 256 and out of the original's own header
    # (wl_menu.h) rather than matched by eye.
    BACKGROUND = 0x2d
    STRIPE = 0x2c
    BORDER = 0x29
    BORDER_SHADOW = 0x23
    TEXT = 0x17
    HIGHLIGHT = 0x13
    DISABLED = 0x2b

    # WHAT A MENU FADES TO WHEN YOU PICK A ROW, and it is not black: the original leaves every
    # menu on VL_FadeOut(0,255,43,0,0,10), which is ten steps to a dark RED. (Spear of Destiny
    # fades to blue.) Written as the channels the original writes, out of the 63 a VGA channel
    # held, so the number beside it is the one in the source.
    FADE_CHANNELS = [43, 0, 0].freeze
    FADE_FRAMES = 10
    # A WIN LEAVES THE GAME ON VW_FadeOut, which is black and thirty of the original's 70 ticks a second.
    WIN_FADE_FRAMES = 26

    # THE TWO ALPHABETS, as the release stores them: the small one is the menu's face and the
    # big one is what a heading is set in.
    LETTERING = :wolf_menu
    HEADING = :wolf_heading

    # ROWS ARE 13 PIXELS APART, which is the original's spacing and happens to be the small
    # alphabet's own height plus three.
    ROW_STEP = 13

    # The gun hangs off the left of the column of rows, with a gap between.
    GUN_GAP = 6

    # Where the main menu's heading plate goes, and the band of stripes behind it: a black bar
    # with a coloured rule along the bottom of it, which is what the plate sits on.
    STRIPE_Y = 8
    STRIPE_H = 24
    STRIPE_RULE = 22

    # Where a heading of lettering sits, and the space left under any heading before the rows
    # begin. The main menu's heading is a picture and the other two are a line of lettering; a
    # screen's rows are then centred in whatever is left below, so no screen carries a row
    # position of its own.
    HEADING_Y = 10
    HEADING_GAP = 8

    # How far outside the rows the main menu's bevelled window is drawn.
    WINDOW_PAD_X = 8
    WINDOW_PAD_Y = 6

    # WHAT THE MAIN MENU SAYS, and two of its five rows say something else once a game is on —
    # which is exactly what the original does with its pause menu. It does not open a second
    # menu; the same list changes what two of its rows mean, in place. Save Game is dim until there
    # is a game to save (MainMenu[savegame].active, wl_menu.cpp).
    NEW_GAME = ["NEW GAME", "END GAME"].freeze
    LOAD_GAME = "LOAD GAME"
    SAVE_GAME = "SAVE GAME"
    VIEW_SCORES = "VIEW SCORES"
    MENU_ROWS = 6
    SOUND = Music::ROW_WORDS
    BACK = ["BACK TO DEMO", "BACK TO GAME"].freeze

    # THE FOUR ANSWERS TO "HOW TOUGH ARE YOU?", in the order the original asks them: which
    # setting the row means, what it says, and the portrait of BJ that goes beside it.
    #
    # THE SETTING IS NAMED rather than left to be the row's position. Picking a row writes a
    # number the world then plays by, and the two lists live in different files with nothing
    # about either one hinting at the other — so reordering these rows, or adding a fifth, can
    # never quietly change what a row means. The one name that differs is the middle setting:
    # the original's art calls its portrait "normal" and its code calls the setting "medium".
    DIFFICULTIES = Ractor.make_shareable([
      [:baby, "Can I play, Daddy?", :difficulty_baby],
      [:easy, "Don't hurt me.", :difficulty_easy],
      [:medium, "Bring 'em on!", :difficulty_normal],
      [:hard, "I am Death incarnate!", :difficulty_hard]
    ])

    # WHAT THE ORIGINAL ASKS BEFORE SAVING OVER A GAME (GAMESVD, foreign.h), and how a pad answers.
    OVERWRITE_QUESTION = ["There's already a game", "saved at this position.", "Overwrite?"].freeze
    OVERWRITE_ANSWERS = "A: yes   B: no"
    QUESTION_TOP = 50

    # The little block beside a row of the high score table that is yours to name.
    MARK_X = 4
    MARK_SIZE = 8

    # The gap between a slot's words and the number of its floor.
    NUMBER_GAP = 4

    HOW_TOUGH = "How tough are you?"
    WHICH_EPISODE = "Which episode to play?"

    # THE SIX EPISODES BY NAME. A cartridge holds the floors it was built with, so a row is
    # only pickable when this one really carries that episode's first floor.
    EPISODE_NAMES = [
      "Escape from Wolfenstein",
      "Operation: Eisenfaust",
      "Die, Fuhrer, Die!",
      "A Dark Secret",
      "Trail of the Madman",
      "Confrontation"
    ].freeze

    # THE SCREENS BY NAME, so a cartridge can be built to boot on one of them. See +starting_on+.
    BY_NAME = { "notice" => NOTICE, "title" => TITLE, "credits" => CREDITS, "menu" => MENU,
                "episodes" => EPISODES, "difficulty" => DIFFICULTY, "playing" => PLAYING,
                "load" => LOADING, "scores" => SCORES, "won" => WINNING }.freeze

    # Which screen a name means, or nothing said, which means the beginning.
    def self.screen_named(name)
      return NOTICE if name.to_s.empty?

      BY_NAME.fetch(name.to_s.strip.downcase) do
        raise ArgumentError,
              "There is no screen called #{name.inspect}. " \
              "The screens are: #{BY_NAME.keys.join(', ')}."
      end
    end

    # +view+ is the game itself, which this puts a menu in front of. +art+ is Wolfenstein's own
    # menu pictures. +sound_setting+ is the variable the SOUND row moves, which the game's own
    # sounds are played under.
    #
    # +starting_on+ is which screen the cartridge boots on, and it is a MEASURING TOOL rather
    # than a way to play — the same kind of dial as which floors to ship. Every screen can be
    # reached by playing, but two of them are a quarter of a minute of waiting away and one only
    # exists on a cartridge carrying more than one episode, so a cartridge that boots straight
    # to the one you want to look at is worth being able to build.
    #
    # +music+ is the Music on this cartridge, or nil on one with none. +source+ is where the build's
    # pictures and alphabets come from (Source).
    def initialize(build:, view:, art:, palette:, sound_setting:, starting_on: NOTICE, music: nil, source: Source::BAKED)
      @b = build
      @view = view
      @art = art
      @palette = palette
      @source = source
      @pictures = source.menu_pictures(build, art: art, palette: palette)
      @sound_setting = sound_setting
      @music = music
      @episodes = view.floors.episodes
      @starting_on = starting_on
      declare
    end

    # ONE PASS OF THE GAME LOOP: exactly one screen runs, whichever one you are on.
    def update
      @b.call :choose_music if @music
      pairs = screens
      @b.case_var(:menus_screen) { pairs.each { |state, scene| when_val state, scene } }
    end

    # EVERY SCREEN THIS CARTRIDGE HAS, and the episode list is only one of them when there is
    # more than one episode on the cartridge to choose between.
    def screens
      list = { NOTICE => :the_notice, TITLE => :the_title, CREDITS => :the_credits,
               MENU => :the_menu, DIFFICULTY => :the_difficulty, PLAYING => :playing,
               LOADING => :load_game, SAVING => :save_game, OVERWRITING => :confirm_overwrite,
               SCORES => :high_scores, NAMING => :pick_a_name }
      list[EPISODES] = :the_episodes if offers_episodes?
      list.merge!(WINNING => :you_win, ARTICLE => :end_article) if episodes_can_end?
      list
    end

    # Which screen is showing, so a test can say where it got to.
    attr_reader :screen, :difficulty

    private

    # WHAT PLAYS ON EACH SCREEN: the original's title and menu songs, and the ones wl_inter.cpp starts
    # for the high scores and the end of an episode. The game itself is the one that depends.
    def screen_songs
      songs = Array.new(ARTICLE + 1, @music.song_index(Music::MENU_SONG))
      [NOTICE, TITLE, CREDITS].each { |screen| songs[screen] = @music.song_index(Music::INTRO_SONG) }
      [SCORES, NAMING].each { |screen| songs[screen] = @music.song_index(Music::ROSTER_SONG) }
      [WINNING, ARTICLE].each { |screen| songs[screen] = @music.song_index(Music::WON_SONG) }
      songs
    end

    def declare_music
      return unless @music

      table = @b.table :screen_song, screen_songs, width: :byte
      @song_wanted = 0
      @b.func(:choose_music, fast: false) do
        @song_wanted = table[@screen]
        song_for_the_attract_loop if @screen == SCORES
        @song_wanted = @music.floor_song(@view.playthrough.floor) if @screen == PLAYING
        @song_wanted = @music.song_index(Music::BETWEEN_FLOORS_SONG) if @screen == PLAYING && between_floors?
        if @screen == PLAYING && player_falling?
          @music.stop
        else
          @music.update(@song_wanted)
        end
      end
    end

    # THE TITLE'S SONG PLAYS ON through the attract loop's high scores (wl_main.cpp), and only a table
    # you came to yourself has a song of its own.
    def song_for_the_attract_loop
      @song_wanted = @music.song_index(Music::INTRO_SONG) if @scores_lead_to == TITLE
    end

    def between_floors? = @view.between_floors ? @view.between_floors == 1 : false

    # THE ORIGINAL STOPS THE MUSIC BEFORE A DEATH (StopMusic, wl_game.cpp) and starts the floor's song
    # from the top on the next life, which naming it again does here.
    def player_falling?
      return false unless @view.dying || @view.over

      (@view.dying ? @view.dying != 0 : false) || (@view.over ? @view.over != 0 : false)
    end

    def cycle_sound_setting
      @sound_setting = (@sound_setting + 1) % SOUND.length
      @scores.save_setting
    end

    def declare
      check_start_screen!
      declare_lettering
      declare_art
      @screen = @starting_on
      # Where the table goes back to, and whether it moves on by itself as it does in the attract loop.
      @scores_lead_to = TITLE
      declare_music
      # How long the screen you are on has been up, and where a fade is taking you. A fade is
      # running exactly while the second one holds a screen number rather than nothing.
      @waited = 0
      @going_to = NOWHERE
      @blink = 0
      # How far the window has drifted across a picture wider than the screen, in pairs of
      # pixels — which is the only step this screen can be drawn at.
      @pan = 0
      # Whether there is a game behind the menu, which is what makes the main menu a pause
      # menu: it decides what two of its rows say and what they do.
      @in_game = 0
      # WHICH FLOOR A GAME WILL START ON, set by the episode list. Nothing else writes it, so a
      # cartridge with no episode list to show simply starts on the first floor it holds.
      @start_floor = 0
      # HOW TOUGH YOU SAID YOU WERE, which this screen only WRITES. It belongs to the world —
      # which guards a floor stands up and what a shot takes off you both read it — so the view
      # declares it and this asks the view for it.
      @difficulty = @view.difficulty
      @saved = SavedGames.new(build: @b, view: @view)
      @letters = SmallLetters.new(build: @b, art: @art, palette: @palette, ink: HighScores::INK, ground: BACKGROUND,
                                  source: @source)
      @scores = HighScores.new(build: @b, letters: @letters, palette: @palette, view: @view,
                               player: @view.player, floor: @view.playthrough.floor, setting: @sound_setting)
      @view.hand_end_of_game_to_menus
      declare_fades
      declare_screens
    end

    # No screen at all, which is what "no fade is running" is written as.
    NOWHERE = -1

    # A cartridge asked to boot on a screen it does not carry would boot to nothing at all, so
    # it says so instead. Two screens can be missing: the episode list, on a cartridge of one
    # episode, and the screen that says you won, on one whose floors cannot end an episode.
    def check_start_screen!
      return if screens.key?(@starting_on)

      if @starting_on == EPISODES
        raise ArgumentError,
              "This cartridge has no episode list to start on. It holds #{@episodes.length} " \
              "episode. To fix this, build it with more floors. Or start on another screen."
      end

      raise ArgumentError,
            "This cartridge has no \"#{BY_NAME.key(@starting_on)}\" screen to start on. Its floors cannot end " \
            "an episode. To fix this, build it with the last floor of an episode. Or start on another screen."
    end

    # Both of Wolfenstein's alphabets (Alphabets).
    def declare_lettering
      alphabets = @source.alphabets(@b, art: @art)
      alphabets.declare LETTERING, 0
      alphabets.declare HEADING, 1
    end

    def declare_art
      %i[notice title credits menu_heading menu_gun menu_gun_firing load_game_heading save_game_heading
         high_scores level_label name_label score_label bj_wins]
        .each { |name| picture(name) }
      DIFFICULTIES.each { |(_, _, portrait)| picture(portrait) }
    end

    def picture(name)
      @pictures.declare(name)
      name
    end

    # THE FADE, AS TWO ROUTINES rather than as code in each screen. Three screens can start a
    # fade and each would otherwise carry its own copy of it; more to the point, a fade is one
    # thing the display does, so there should be one place that says how this game fades.
    def declare_fades
      @b.func(:_menu_fade_out) { @b.fade_out fade_colour, frames: FADE_FRAMES }
      @b.func(:_win_fade_out) { @b.fade_out @b.rgb(0, 0, 0), frames: WIN_FADE_FRAMES }
      @b.func(:_menu_fade_in) { @b.fade_in }
    end

    def declare_screens
      still_screen(:the_notice, :notice, after: TITLE, holding: NOTICE_FRAMES)
      still_screen(:the_title, :title, after: CREDITS, holding: TITLE_FRAMES)
      still_screen(:the_credits, :credits, after: SCORES, holding: CREDITS_FRAMES)
      declare_menu
      declare_episodes if offers_episodes?
      declare_difficulty
      declare_game
      declare_slot_screen(:load_game, :load_game_heading) { |n| load_slot(n) }
      declare_slot_screen(:save_game, :save_game_heading) { |n| save_to_slot(n) }
      declare_overwrite_question
      declare_score_screens
      declare_episode_end_screens if episodes_can_end?
    end

    # --- THE ATTRACT LOOP ------------------------------------------------------------------

    # A SCREEN THAT SHOWS ONE PICTURE AND WAITS: for its own time to run out, which moves it on
    # to the next of them, or for anybody to touch the pad, which opens the menu. The whole
    # attract loop is three of these.
    def still_screen(name, art, after:, holding:)
      wide, tall = @art.size(art)
      travel = (wide - ACROSS) / 2
      @b.scene(name) do
        show(art, wide: wide, tall: tall, travel: travel, over: holding)
        @waited += 1
        go_to after if @waited >= holding
        # A PRESS ALWAYS WINS, and it wins whichever way round these two are asked: moving on
        # puts the clock back to nothing, so the screen that arrives is the one the press
        # asked for either way. A player who touched the pad meant the menu.
        #
        # A NEW PRESS, not a button that is down. The original notes what is held as the screen
        # starts and waits for something that was not (IN_StartAck and IN_CheckAck, id_in.cpp),
        # so the A that ended a game, held a moment too long, does not open the menu again.
        go_to MENU if @b.pressed(:any)
      end
    end

    # THE PICTURE: centred where it fits, and where it does not, the SCREEN drifts across it.
    #
    # The title and the credits were painted a third wider than this screen, and squeezing them
    # to fit is what turns their lettering to mush (see MenuArt). So nothing is squeezed across:
    # every column is kept and the window walks over the eighty that do not fit, out and back,
    # over about four fifths of the time the screen is up. It costs one drawing a frame, which
    # is what a still picture cost anyway.
    #
    # IT MOVES TWO PIXELS AT A TIME because this screen holds two pixels in each of its places
    # and will not take one, so an odd column is not a column a picture can start at. Twice
    # anything is even, which is how the drift is written and how the framework's own refusal
    # says to write it.
    def show(art, wide:, tall:, travel:, over:)
      down = (DOWN - tall) / 2
      @b.clear_screen colour(0) unless [wide, tall] == [ACROSS, DOWN]
      return @b.blit(:"menu_#{art}", even((ACROSS - wide) / 2), down) unless travel.positive?

      @pan = @waited / pan_step(travel, over)
      # Out and back: past the far end it walks home again.
      @pan = (travel * 2) - @pan if @pan > travel
      @pan.clamp! 0, travel
      @b.blit :"menu_#{art}", -(@pan * 2), down
    end

    # How many frames each two-pixel step holds for, so the drift out and back takes about four
    # fifths of the time the screen is up and settles for the rest of it. Never less than one.
    def pan_step(travel, over) = [(over * 4 / 5) / (travel * 2), 1].max

    # --- THE MAIN MENU, WHICH IS ALSO THE PAUSE MENU -----------------------------------------

    def declare_menu
      rows = NEW_GAME + [LOAD_GAME, SAVE_GAME, VIEW_SCORES] + SOUND + BACK
      at = layout_for(rows)
      y = rows_top(@art.height(:menu_heading) + HEADING_GAP, MENU_ROWS)
      @b.scene(:the_menu) do
        the_ground
        the_stripes
        @b.blit :menu_menu_heading, even((ACROSS - @art.width(:menu_heading)) / 2), 0
        the_window(at, y, MENU_ROWS)
        picked = the_rows(:main, at, y) do |m|
          m.item(NEW_GAME, showing: @in_game) { new_game_or_end_it }
          m.item(LOAD_GAME) { leaving_for LOADING }
          m.item(SAVE_GAME, enabled: @in_game) { leaving_for SAVING }
          m.item(SOUND, showing: @sound_setting) { cycle_sound_setting }
          m.item(VIEW_SCORES) { view_scores }
          m.item(BACK, showing: @in_game) { leave_the_menu }
        end
        the_gun(at, y, picked)
        arriving
      end
    end

    # ONE ROW, TWO MEANINGS, which is the row the pause menu turns over. Outside a game it
    # starts one; inside a game it ends the one you are in and leaves you at the title.
    def new_game_or_end_it
      if @in_game == 1
        @in_game = 0
        leaving_for TITLE
      else
        leaving_for(offers_episodes? ? EPISODES : DIFFICULTY)
      end
    end

    # ...and so is the last row: back to the loop of still screens, or back to the game.
    def leave_the_menu
      if @in_game == 1
        leaving_for PLAYING
      else
        leaving_for TITLE
      end
    end

    # --- LOAD GAME AND SAVE GAME ----------------------------------------------------------------

    # ONE LIST OF SLOTS, under its own plate, for both (DrawLoadSaveScreen). B goes back to the main
    # menu. The block says what picking slot +n+ does.
    def declare_slot_screen(scene_name, heading, &pick)
      words = SavedGames::LABELS
      at = layout_for(words.map { |label| "#{label} 10" })
      y = rows_top(@art.height(heading) + HEADING_GAP, SavedGames::SLOTS)
      episode_x = at.rows_x + widest([SavedGames::EPISODE]) + NUMBER_GAP
      number_x = at.rows_x + widest(words) + NUMBER_GAP
      @b.scene(scene_name) do
        the_ground
        the_stripes
        @b.blit :"menu_#{heading}", even((ACROSS - @art.width(heading)) / 2), 0
        @saved.refresh_labels
        picked = the_rows(scene_name, at, y) do |m|
          (0...SavedGames::SLOTS).each do |n|
            m.item(words, showing: @saved.label_variable(n)) { pick.call(n) }
          end
        end
        (0...SavedGames::SLOTS).each do |n|
          if @saved.occupied?(n)
            draw_slot_number(@saved.episode_variable(n), n, episode_x, y, picked, digits: 1)
            draw_slot_number(@saved.number_variable(n), n, number_x, y, picked, digits: 2)
          end
        end
        the_gun(at, y, picked)
        leaving_for MENU if @b.pressed(:b)
        arriving
      end
    end

    # A number in a slot is not part of the row, so it lights up with the row by hand.
    def draw_slot_number(number, n, x, top, picked, digits:)
      if picked == n
        @b.draw_number number, x, top + (n * ROW_STEP), colour(HIGHLIGHT), digits: digits, font: LETTERING
      else
        @b.draw_number number, x, top + (n * ROW_STEP), colour(TEXT), digits: digits, font: LETTERING
      end
    end

    # A LOAD GOES STRAIGHT INTO THE GAME (CP_LoadGame sets StartGame). An empty slot does nothing.
    # Asked once, because a press during the fade would load it again.
    def load_slot(n)
      if @going_to == NOWHERE && @saved.occupied?(n)
        @saved.load_slot(n)
        @in_game = 1
        leaving_for PLAYING
      end
    end

    # A SAVE OVER A GAME ASKS FIRST, and either way ends at the main menu, not in the game
    # (CP_SaveGame).
    def save_to_slot(n)
      if @going_to == NOWHERE
        @saved.choose_slot(n)
        if @saved.occupied?(n)
          go_to OVERWRITING
        else
          write_save
        end
      end
    end

    def write_save
      @saved.write_chosen_slot
      leaving_for MENU
    end

    def declare_overwrite_question
      @b.scene(:confirm_overwrite) do
        the_ground
        OVERWRITE_QUESTION.each_with_index do |line, n|
          @b.draw_text line, :center, QUESTION_TOP + (n * ROW_STEP), colour(TEXT), font: LETTERING
        end
        @b.draw_text OVERWRITE_ANSWERS, :center, QUESTION_TOP + (4 * ROW_STEP), colour(HIGHLIGHT), font: LETTERING
        write_save if @b.pressed(:a)
        go_to SAVING if @b.pressed(:b)
        arriving
      end
    end

    # --- THE HIGH SCORES ------------------------------------------------------------------------

    def declare_score_screens
      @b.scene(:high_scores) do
        draw_score_table
        @waited += 1
        # IN THE ATTRACT LOOP IT MOVES ON, and from the menu it waits for you.
        go_to @scores_lead_to if @scores_lead_to == TITLE && @waited >= SCORES_FRAMES
        if @b.pressed(:any)
          @scores_lead_to = TITLE
          go_to MENU
        end
        arriving
      end
      @b.scene(:pick_a_name) do
        draw_score_table
        mark_new_row
        @scores.edit_name
        finish_name if @b.pressed(:a) || @b.pressed(:start)
        arriving
      end
    end

    def draw_score_table
      the_ground
      the_stripes
      @b.blit :menu_high_scores, even((ACROSS - @art.width(:high_scores)) / 2), 0
      @b.blit :menu_name_label, HighScores::NAME_X, HighScores::NAME_LABEL_Y
      @b.blit :menu_level_label, HighScores::FLOOR_X, HighScores::NAME_LABEL_Y
      @b.blit :menu_score_label, HighScores::SCORE_X + 16, HighScores::NAME_LABEL_Y
      @scores.draw
    end

    # THE ROW YOU EARNED, marked in the column before the names.
    def mark_new_row
      y = HighScores::TOP_ROW + (@scores.new_row * HighScores::ROW_STEP)
      @b.draw_rect_at MARK_X, y, MARK_SIZE, MARK_SIZE, colour(HIGHLIGHT)
    end

    def view_scores
      @scores_lead_to = MENU
      leaving_for SCORES
    end

    # AN EPISODE WON GOES STRAIGHT TO THE SCREEN THAT SAYS SO (the original's ex_victorious).
    def show_the_win
      return unless @view.won

      if @view.won == 1 && @going_to == NOWHERE
        @episode_end.add_up_the_episode
        leaving_for WINNING, fade: :_win_fade_out
      end
    end

    # Can an episode be won on this cartridge? Most test cartridges have no way to.
    def episodes_can_end? = !@view.won.nil?

    def declare_episode_end_screens
      @episode_end = EpisodeEnd.new(build: @b, art: @art, letters: @letters, lettering: @view.big_lettering,
                                    records: @view.records, floor: @view.playthrough.floor, floors: @view.floors,
                                    source: @source)
      # A cartridge built to boot here has won nothing, so the sums are done for it.
      @episode_end.add_up_the_episode if @starting_on == WINNING
      @b.scene(:you_win) do
        @episode_end.draw_summary
        leave_the_summary if @b.pressed(:any)
        arriving
      end
      @b.scene(:end_article) do
        @episode_end.draw_page
        turn_the_page if @b.pressed(:any)
        arriving
      end
    end

    def leave_the_summary
      if @going_to == NOWHERE
        @episode_end.open_article
        if @episode_end.article_open
          leaving_for ARTICLE
        else
          finish_game
        end
      end
    end

    def turn_the_page
      if @going_to == NOWHERE
        @episode_end.turn_page
        finish_game unless @episode_end.article_open
      end
    end

    # START ON A GAME OVER, which a cartridge with nothing on it to kill you does not have.
    def finish_game_on_start
      return unless @view.over

      finish_game if @view.over == 1 && @b.pressed(:start) && @going_to == NOWHERE
    end

    # THE GAME IS DONE, and the table comes next, with a name to pick if it earned a row
    # (CheckHighScore). There is no game behind the menu from here on.
    def finish_game
      @scores.enter_game
      @in_game = 0
      @scores_lead_to = TITLE
      if @scores.new_row == HighScores::NOBODY
        leaving_for SCORES
      else
        leaving_for NAMING
      end
    end

    def finish_name
      @scores.finish_name
      go_to SCORES
    end

    # --- THE EPISODE LIST --------------------------------------------------------------------

    # Only worth a screen when the cartridge holds more than one episode to start. A cartridge
    # with one has nothing to ask, and one begun in the MIDDLE of an episode — which is what the
    # dial for measuring a later floor's cost makes — has no episode start at all.
    def offers_episodes? = @episodes.length > 1

    def declare_episodes
      at = layout_for(EPISODE_NAMES)
      y = rows_top(under_a_written_heading, EPISODE_NAMES.length)
      @b.scene(:the_episodes) do
        the_ground
        @b.draw_text WHICH_EPISODE, :center, HEADING_Y, colour(TEXT), font: HEADING
        picked = the_rows(:episodes, at, y) do |m|
          EPISODE_NAMES.each_with_index do |name, n|
            slot = @episodes[n + 1]
            # An episode this cartridge does not hold is there to be seen and not to be
            # picked, so it has nothing to do either. A whole build holds every episode's floors
            # and learns as it runs which its copy has: the shareware's five are dim, as the
            # original's are (wolf4sdl: wl_menu.cpp, NewEmenu).
            next m.item(name, enabled: false) if slot.nil?

            m.item(name, enabled: @view.holds_floor?(slot)) { @start_floor = slot; leaving_for DIFFICULTY }
          end
        end
        the_gun(at, y, picked)
        arriving
      end
    end

    # --- THE DIFFICULTY SCREEN ---------------------------------------------------------------

    def declare_difficulty
      at = layout_for(DIFFICULTIES.map { |(_, words, _)| words })
      y = rows_top(under_a_written_heading, DIFFICULTIES.length)
      @b.scene(:the_difficulty) do
        the_ground
        @b.draw_text HOW_TOUGH, :center, HEADING_Y, colour(TEXT), font: HEADING
        picked = the_rows(:difficulty, at, y) do |m|
          DIFFICULTIES.each do |(setting, words, _)|
            m.item(words) { @difficulty = Guards.number_of(setting); start_the_game }
          end
        end
        the_portrait(y, picked)
        the_gun(at, y, picked)
        arriving
      end
    end

    # THE PORTRAIT BESIDE THE ROWS, which is the whole reason this screen is not a plain list:
    # BJ gets grimmer as you move down it, so the picture answers the question the rows ask.
    #
    # FOUR DRAWINGS UNDER FOUR TESTS rather than one picture of all four side by side, which is
    # how the bar's twenty-four faces are done. The trick pays when the set is big, or when the
    # picture is being walked a column at a time anyway; here it would turn one copied block
    # into twenty-four column walks to save three tests on a screen with nothing else to do.
    def the_portrait(rows_y, picked)
      wide, tall = @art.size(DIFFICULTIES.first.last)
      x = even(ACROSS - wide - PORTRAIT_MARGIN)
      y = rows_y + (((DIFFICULTIES.length * ROW_STEP) - tall) / 2)
      DIFFICULTIES.each_with_index do |(_, _, portrait), n|
        @b.blit :"menu_#{portrait}", x, y if picked == n
      end
    end

    PORTRAIT_MARGIN = 12

    # --- THE GAME ----------------------------------------------------------------------------

    def declare_game
      @b.scene(:playing) do
        @view.update
        pausing
        arriving
      end
    end

    # START OPENS THE MENU, and it opens it at once rather than fading — the fade belongs to
    # LEAVING a menu, which is what the original fades.
    #
    # UNLESS THE GAME IS OVER, and then START means the other thing it has always meant here:
    # begin another game on the floor the last one began on. The two never overlap, so one button
    # does both.
    #
    # NOR ON THE SCREEN BETWEEN TWO FLOORS. The game has stopped for that one already, and a game
    # ended from the menu behind it would leave the screen up over the title.
    #
    # NOR WHILE YOU ARE DYING. The original reads no keys until a death is over (Died, wl_game.cpp),
    # and here the fizzle adds to the picture already there, which would be the menu.
    #
    # NOR WHILE THE DEATH CAM RUNS, which is a game already over.
    def pausing
      show_the_win
      finish_game_on_start
      pause_unless([@view.over, @view.dying, @view.between_floors, @view.watching, @view.marching].compact)
    end

    # Each of +flags+ is 1 while START must not pause. A cartridge may hold neither of them.
    def pause_unless(flags)
      if flags.empty?
        if @b.pressed(:start)
          @view.put_the_flash_away
          @in_game = 1
          go_to MENU
        end
      elsif flags.first == 0
        pause_unless(flags.drop(1))
      end
    end

    # A GAME BEGINS: on the floor the episode list picked, with a fresh player, and then the
    # screen fades away to leave you in it.
    def start_the_game
      @view.playthrough.start(:new_game, floor: @start_floor)
      @in_game = 1
      leaving_for PLAYING
    end

    # --- THE CHROME EVERY MENU SHARES --------------------------------------------------------

    def the_ground = @b.clear_screen(colour(BACKGROUND))

    # A BLACK BAND WITH A COLOURED RULE ALONG THE BOTTOM OF IT, which is what the heading plate
    # sits on. The band is wider than the plate, so it runs out either side of it.
    def the_stripes
      @b.dma_fill_rect 0, STRIPE_Y, ACROSS, STRIPE_H, colour(0)
      @b.dma_fill_rect 0, STRIPE_Y + STRIPE_RULE, ACROSS, 1, colour(STRIPE)
    end

    # THE BEVELLED WINDOW BEHIND THE ROWS: an outline in two colours, the lighter along the top
    # and down the left, the darker along the bottom and up the right. Two colours rather than
    # one is the whole of what makes it read as cut into the screen rather than drawn on it.
    #
    # Drawn with the rectangle that takes any width, because a line down the side of it is ONE
    # pixel wide and the block fills on this screen want an even number.
    #
    # THE GUN IS INSIDE IT, so the window is measured from the gun's own column rather than
    # from the lettering's — a selector hanging outside the frame it points into reads as a
    # mistake.
    def the_window(at, y, rows)
      left = at.gun_x - WINDOW_PAD_X
      top = y - WINDOW_PAD_Y
      w = (at.rows_x - left) + at.wide + WINDOW_PAD_X
      h = (rows * ROW_STEP) + (WINDOW_PAD_Y * 2)
      @b.draw_rect_at left, top, w, 1, colour(BORDER)
      @b.draw_rect_at left, top, 1, h, colour(BORDER)
      @b.draw_rect_at left, top + h - 1, w, 1, colour(BORDER_SHADOW)
      @b.draw_rect_at left + w - 1, top, 1, h, colour(BORDER_SHADOW)
    end

    # THE ROWS THEMSELVES. Every menu in this game is drawn the same way, so the three colours
    # and the spacing and the button are said once here; what differs is only the rows.
    #
    # NO CURSOR OF THE FRAMEWORK'S OWN — the gun is drawn separately, because it is a picture
    # rather than a character and because it blinks.
    def the_rows(name, at, y, &rows)
      @b.menu(name, at: [at.rows_x, y], spacing: ROW_STEP, font: LETTERING, cursor: "",
                    color: colour(TEXT), picked: colour(HIGHLIGHT), disabled: colour(DISABLED),
                    press: :a, repeat_every: HELD_REPEAT, &rows).picked
    end

    # THE GUN, pointing at the row you are on and blinking: itself for a second, then itself
    # with its muzzle flashing for about a ninth of one.
    def the_gun(at, y, picked)
      tall = @art.height(:menu_gun)
      row = (picked * ROW_STEP) + y + ((ROW_STEP - tall) / 2)
      @blink += 1
      @blink = 0 if @blink >= BLINK_ON + BLINK_OFF
      if @blink < BLINK_ON
        @b.blit :menu_menu_gun, at.gun_x, row
      else
        @b.blit :menu_menu_gun_firing, at.gun_x, row
      end
    end

    # --- MOVING BETWEEN SCREENS --------------------------------------------------------------

    # STRAIGHT TO ANOTHER SCREEN, with the clock on the new one started from nothing.
    def go_to(screen)
      @screen = screen
      @waited = 0
    end

    # ...and the other way, which is what picking a row does: the screen fades away first and
    # the new one is not shown until it has gone. A second choice while a fade is running is
    # ignored, which is what the guard is for — the original simply stops reading the pad.
    def leaving_for(screen, fade: :_menu_fade_out)
      if @going_to == NOWHERE
        @going_to = screen
        @b.call fade
      end
    end

    # THE OTHER HALF OF THAT, run by every menu on every frame: once the screen has gone
    # completely dark, swap to what was waiting behind it and bring it back up.
    #
    # THE TEST IS ON THE ERRAND AND NOT ONLY ON THE DARKNESS. A fade that has just been asked
    # to come back is still at its darkest on the frame after it started, so a screen watching
    # the darkness alone would arrive twice.
    #
    # EVERY MENU HAS PAINTED THE WHOLE SCREEN, so the game is told on any arrival rather than only
    # on one at the game, which is reached this way and no other. Told on the way to the title it
    # is told early, and the next game starts by painting a bar it wanted anyway.
    def arriving
      if @going_to != NOWHERE && @b.fade_level == 100
        go_to @going_to
        @going_to = NOWHERE
        @view.painted_over
        @b.call :_menu_fade_in
      end
    end

    # --- LAYING A SCREEN OUT ------------------------------------------------------------------

    # WHERE ONE SCREEN'S ROWS GO ACROSS: the column the lettering starts at, the column the gun
    # hangs in beside it, and how wide the widest row comes out.
    Layout = Data.define(:rows_x, :gun_x, :wide)

    # Worked out from the alphabet rather than counted in pixels, so a row can be reworded and
    # nothing here is left stale. The pair — the gun and the rows — is centred as one thing, so
    # a screen of short rows is not pushed to one side by the gun beside them.
    def layout_for(labels)
      room = @art.width(:menu_gun) + GUN_GAP
      wide = widest(labels)
      x = [((ACROSS - room - wide) / 2) + room, room].max
      Layout.new(rows_x: x, gun_x: even(x - room), wide: wide)
    end

    def widest(labels) = labels.map { |words| @b.text_width(words, font: LETTERING) }.max

    # WHERE A SCREEN'S ROWS BEGIN DOWN THE SCREEN: centred in whatever is left under its
    # heading, so no screen carries a row position typed in by hand and a list of six sits as
    # well as a list of four.
    def rows_top(under, count) = under + ((DOWN - under - (count * ROW_STEP)) / 2)

    def under_a_written_heading = HEADING_Y + @b.text_height(font: HEADING) + HEADING_GAP

    def colour(ink) = @palette[ink]

    def fade_colour = @b.rgb(*FADE_CHANNELS.map { |channel| channel * 31 / 63 })

    # A PICTURE MUST START ON AN EVEN COLUMN on this screen, which takes two pixels at a time
    # and will not take one.
    def even(x) = x - (x % 2)
  end
end
