# frozen_string_literal: true

module Wolf3DTest
  # A WHOLE BUILD'S EPISODE LIST, booted on and picked from: down once, then A. Down lands on the
  # second episode where the copy holds it, and steps over the five the shareware lacks back to the
  # first, so what A picks says which episodes the list offers. test_holding.rb holds the floor it
  # picks, and films/whole_episodes.rb shows it.
  #
  # The original lists all six either way and dims the ones a release lacks
  # (wolf4sdl: wl_menu.cpp, NewEmenu, whose rows the six episodes' files switch on as the game
  # starts).
  module EpisodeScene
    SETTINGS = { screen: "episodes", hold: "whole" }.freeze
    DOWN_FRAME = 30   # After the list has faded in
    PICK_FRAME = 40
    FRAMES = 60       # Past the pick, on the difficulty screen
    TOUGH_FRAME = 70  # ...where A starts the game, for the film
    PLAYING_FRAMES = 200 # ...and its first floor drawn

    # The buttons down on +frame+, counted from one.
    def self.keys(frame)
      case frame
      when DOWN_FRAME then [:down]
      when PICK_FRAME, TOUGH_FRAME then [:a]
      else []
      end
    end
  end
end
