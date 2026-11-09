# frozen_string_literal: true

module Wolf3DTest
  # THE SECOND WORLD, beside the real view, for what test_playthrough.rb asks. Each step appends
  # its number, one to five, to the trail: another life that ran steps two and four and nothing
  # else reads 24.
  #
  # IN A FILE OF THEIR OWN, LOADED AS A GAME'S ARE, because these two run as the game plays and a
  # method in a test file is not read as game code.
  class StepCountingWorld
    STEPS = %i[reset_game reset_player select_floor place_player reset_floor].freeze

    def initialize(build)
      @trail = build.var :trail, 0
    end

    def reset_game = step(:reset_game)
    def reset_player = step(:reset_player)
    def select_floor = step(:select_floor)
    def place_player = step(:place_player)
    def reset_floor = step(:reset_floor)

    # Every floor held is one the copy has, as in any trimmed build.
    def holds_floor?(_slot) = true

    private

    def step(name)
      @trail = (@trail * 10) + STEPS.index(name) + 1
    end
  end

  # THE REST OF THE GAME, as far as a death reaches it, for test_lives.rb. Putting the floor back is
  # stood in for by a counter, because what it really does belongs to the view and is tested against
  # the real thing there — all this needs of it is that it is asked for. A new game puts the goes
  # back, which is the one step that is Lives' own.
  class RestartCountingWorld
    attr_writer :lives

    def initialize(restarts:, dying:)
      @restarts = restarts
      @dying = dying
    end

    def reset_game = @lives.start_again
    def reset_player = nil
    def select_floor = nil
    def place_player = nil
    def holds_floor?(_slot) = true

    def reset_floor
      @restarts += 1
      @dying.start_again
    end
  end
end
