# frozen_string_literal: true

module Wolf3D
  # HOW MANY GOES YOU GET, and what happens when you use one up.
  #
  # The death itself is Dying's story — turn toward what killed you, then the view dots over to
  # red — and it ends with the screen red and nothing running. This is what comes after: one life
  # comes off, and with any left the floor starts again from the top, which is what the original
  # does (wl_game.cpp, Died). With none left the game is over.
  #
  # WHAT IT DOES NOT OWN is putting the floor back. That is a great many things — where every
  # guard stands, which doors are open, which keys are still on the floor — and all of them belong
  # to the view, which is where their starting values were worked out in the first place. This
  # says WHEN, and asks the playthrough for another life or a new game.
  class Lives
    # How many goes a new game hands you, which is the original's number.
    START = 3

    # White, out of the game's own 256, for words over a red screen.
    INK = 15

    WORDS = "GAME OVER"
    AGAIN = "PRESS START"

    # How far above and below the eye line the two lines of words sit.
    ABOVE = 12
    BELOW = 8

    FONT = :default

    # +dying+ may be nil: a floor with nothing on it that can kill you still shows a number of
    # lives, and never spends one. +playthrough+ is what starts play again after a death.
    def initialize(build:, playthrough:, dying: nil)
      @b = build
      @playthrough = playthrough
      @dying = dying
      declare
    end

    # What the bar along the bottom shows.
    def left = @left

    # WHETHER THE GAME HAS ENDED, or nil on a floor with nothing on it that can kill you —
    # there is no death to count, so there is nothing to say the game is over. The menus read
    # it because START means two things while a game is on, and this is what tells them
    # apart: it opens the menu while you are playing, and starts another game once you are
    # not.
    def over = @ended

    # WHAT A NEW GAME PUTS BACK HERE: the goes back to three, and a game that is not over. Every
    # new game does this, however it was started — see Playthrough.
    def start_again
      @left.set! START
      @ended&.set! 0
    end

    # A GAME CAN ALSO END BY BEING WON, and when it does the flag this keeps is the one that has
    # to say so: it is what the menus read to tell START-opens-the-menu from START-plays-again,
    # and what #start_another_game watches. So Victory ends the game through here rather than
    # keeping a second flag nothing else knows about.
    #
    # It does NOT queue the words above — a won episode has its own, and they are drawn over the
    # last picture of the game rather than over the red a death leaves. See {Victory}.
    def ended_by_winning = @ended&.set!(1)

    # ANOTHER GO, which is what the one-up lying on the floor hands you. The original stops at
    # nine, and so does this: the bar keeps one figure for it.
    MOST = 9

    def give_one
      @left.add! 1
      @left.clamp! 0, MOST
    end

    # ONE PASS OF THE GAME LOOP, and it does nothing at all until the death has finished telling
    # its story.
    #
    # CALLED WHERE THE DEATH IS DRAWN rather than where the game is played, because that is where
    # a death finishes: the fizzle is drawing, and the pass that puts the last dot down is the
    # pass on which there is something to count.
    #
    # A ROUTINE RATHER THAN CODE IN THE LOOP, for the reason the status bar and the guards' minds
    # are: the console's quick memory holds 32K, the game loop's own body wants nearly all of it,
    # and this is a few hundred bytes that do nothing on all but a handful of passes in a whole
    # game. Written straight in it measured as a hundred bytes, which was enough to push the
    # routine that draws the guards out of that memory — and everything that routine does then
    # costs about two and a half times as much.
    def update
      @b.call(:after_a_death) if @dying
    end

    private

    # WHAT A FINISHED DEATH COMES TO, and the two arms are the whole of it. With a life left the
    # floor starts again and the death is put back to the beginning, so the test above stops being
    # true by itself. With none left there is nothing to put back, so a flag says the game is over
    # and holds it there — without one, the same finished death would take another life off on
    # every pass that followed.
    #
    # Then the words, if the game is over, over the red the fizzle left. Nothing else is being
    # drawn by then.
    def count_a_death
      (@ended == 0).then do
        @dying.finished.then do
          @left.sub! 1
          (@left > 0).then { another_life }.else { end_the_game }
        end
      end.else { start_another_game }

      @words.draw
    end

    # A LIFE LEFT: a fresh player, and the floor from the top (wl_game.cpp, Died).
    def another_life = @playthrough.start(:another_life)

    def end_the_game
      @ended.set! 1
      @words.changed
    end

    # START BEGINS A NEW GAME, on the floor the last one began on.
    def start_another_game
      @b.pressed(:start).then { @playthrough.start(:new_game) }
    end

    def declare
      @left = @b.var :lives, START
      return unless @dying

      # Whether the game has ended. It starts at nothing: a game that has not been played
      # cannot be over.
      @ended = @b.var :game_over, 0

      # The words, put up when the game ends and then left there. `keep_showing` decides how
      # many paints that takes: this game draws on a tear-free screen, where a picture painted
      # a single time reaches only half the frames.
      @words = @b.keep_showing(:game_over) { paint }

      @b.func(:after_a_death, fast: false) { count_a_death }
    end

    def paint
      @b.draw_text WORDS, centred_x(WORDS), FirstPerson::HORIZON - ABOVE, colour, font: FONT
      @b.draw_text AGAIN, centred_x(AGAIN), FirstPerson::HORIZON + BELOW, colour, font: FONT
    end

    # Where a line of words starts if it is to sit in the middle of the screen.
    def centred_x(words) = (FirstPerson::ACROSS - font.text_width(words)) / 2
    def font = RubyGBA::Graphics::Fonts.get(FONT)
    def colour = Palette.game[INK]
  end
end
