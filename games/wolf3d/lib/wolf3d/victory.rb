# frozen_string_literal: true

module Wolf3D
  # WHAT WINNING AN EPISODE IS, which is the other way a game can stop.
  #
  # Its sibling is Lives, and deliberately so: the two are the same shape — a flag that says the
  # game has ended, words over the last picture, and START to begin another. What differs is
  # which of them you reached and what it says. Written against that shape rather than beside it
  # so the menus have one question to ask ("is a game still being played") and not two.
  #
  # WHAT ENDS AN EPISODE IS WALKING OUT OF IT, not killing the boss — see Level::EXIT — on the two
  # floors that have a way out. The boss stands between you and a gold-locked door, and the corridor
  # behind it is where the way out lies, so the key he leaves is what killing him buys. That is the
  # original's own arrangement and it is a better fight than "the boss falls and the screen changes":
  # you still have to get past him and out. On the other four the boss's fall ends it. See DeathCam.
  #
  # THE WORDS BELOW ARE FOR A CARTRIDGE WITH NO MENUS. One with menus goes on to what the original
  # shows, which is EpisodeEnd, and BJ's run comes before all of it where his pictures are held. See
  # VictoryMarch.
  class Victory
    # White, out of the game's own 256, for words over whatever was last drawn.
    INK = 15

    WORDS = "EPISODE COMPLETE"
    AGAIN = "PRESS START"

    # How far above and below the eye line the two lines of words sit.
    ABOVE = 12
    BELOW = 8

    FONT = :default

    # +lives+ is who owns "the game has ended" — see Lives#ended_by_winning for why the flag is
    # kept there and not here, and why START is answered there too. +lasting+ is what a saved
    # game holds (see LastingState).
    def initialize(build:, lives:, lasting: LastingState.new(build:))
      @b = build
      @lives = lives
      @lasting = lasting
      declare
    end

    # Whether an episode has been won and is still on the screen. What the world reads to stop
    # running: winning stops the game exactly as dying does.
    def over = @won

    # WALKED OUT OF THE EPISODE. Called from the walk, on the frame the player reaches the way
    # out. Once only, so that standing on the tile does not keep re-winning it.
    def won
      if @won == 0
        @won = 1
        # ...and the game has ended, which is the fact the menus and the restart both read.
        @lives.ended_by_winning
      end
    end

    # A NEW GAME PUTS THIS BACK, however it was started — see Playthrough.
    def start_again = @won = 0

    # See FirstPerson#hand_end_of_game_to_menus.
    def hand_end_of_game_to_menus
      @menus_end_games = true
    end

    # ONE PASS. Nothing at all until an episode has been won, and then the words, on every pass
    # until START.
    #
    # EVERY PASS, NOT ONCE, and that is what makes this different from GAME OVER. A death stops
    # the view being drawn, so its words are painted once and left over the red. A won episode
    # only stops the world MOVING: the view is still drawn every pass, the same picture each time,
    # and it would cover words painted once on the very next pass.
    #
    # A ROUTINE RATHER THAN CODE IN THE LOOP, for the reason Lives gives: the console's quick
    # memory holds 32K, the game loop's own body wants nearly all of it, and this is a few
    # hundred bytes that do nothing on all but a handful of passes in a whole game.
    def update = @b.call(:after_a_victory)

    private

    def declare
      @won = @lasting.var :episode_won, 0
      @b.func(:after_a_victory, fast: false) { paint_words unless @menus_end_games }
    end

    def paint_words
      paint if @won == 1
    end

    def paint
      @b.draw_text WORDS, centred_x(WORDS), FirstPerson::HORIZON - ABOVE, colour, font: FONT
      @b.draw_text AGAIN, centred_x(AGAIN), FirstPerson::HORIZON + BELOW, colour, font: FONT
    end

    # Where a line of words starts if it is to sit in the middle of the screen.
    def centred_x(words) = (FirstPerson::ACROSS - font.text_width(words)) / 2
    def font = VBlank::Graphics::Fonts.get(FONT)
    def colour = Palette.game[INK]
  end
end
