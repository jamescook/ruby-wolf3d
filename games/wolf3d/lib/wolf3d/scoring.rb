# frozen_string_literal: true

module Wolf3D
  # POINTS, AND THE LIFE THAT COMES WITH EVERY FORTY THOUSAND OF THEM. Every gain of score comes
  # through here, which is the original's GivePoints (wl_agent.cpp): the score goes up, and each time
  # it has passed the next threshold, the threshold moves on and you get a go.
  #
  # THE THRESHOLD IS NOT THE SCORE'S TO PUT BACK. A death takes the floor's points away and leaves
  # this alone, so points earned a second time do not pay a life a second time. Only a new game
  # starts it again (NewGame, wl_main.cpp).
  #
  # THE ORIGINAL PLAYS ITS ONE-UP SOUND HERE, which is one of the AdLib effects this game has not got.
  class Scoring
    game_variables :paying, saved: false

    # EXTRAPOINTS, wl_def.h.
    EVERY = 40_000

    # THE ORIGINAL'S TEST IS A WHILE, because one payment could cross two thresholds. The biggest
    # payment in the game is thirty thousand, so here it never does twice, and a loop must end
    # somewhere.
    MOST_AT_ONCE = 2

    # +lasting+ is what a saved game holds, and the threshold is in the original's.
    def initialize(build:, player:, lives:, lasting:)
      @b = build
      @player = player
      @lives = lives
      @next = lasting.var :next_extra, EVERY
      @paying = 0
      @b.func(:the_score_goes_up) { pay_them }
    end

    # +points+ TO THE SCORE. A routine, because three places pay and it is the same few lines.
    def pay(points)
      @paying = points
      @b.call :the_score_goes_up
    end

    # A NEW GAME STARTS THE COUNT AGAIN.
    def start_again = @next = EVERY

    private

    def pay_them
      @player.score += @paying
      @b.repeat(MOST_AT_ONCE, stop_when: @player.score < @next) do
        @next += EVERY
        @lives.give_one
      end
    end
  end
end
