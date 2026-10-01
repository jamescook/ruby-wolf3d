# frozen_string_literal: true

module Wolf3D
  # STARTING PLAY, for each reason play starts: a new game, another life after a death, and the
  # next floor at the bottom of the lift.
  #
  # Each reason puts back a different part of the game, in an order that matters, and this is
  # the one place that says which and in what order. The parts of the game do the putting back
  # themselves: this calls a small fixed set of steps on the +world+, which is the view in the
  # real game.
  class Playthrough
    # +lasting+ is what a saved game holds (see LastingState), and the three numbers below are in
    # it.
    def initialize(build:, floors:, score:, world:, lasting: LastingState.new(build:))
      @b = build
      @floors = floors
      @score = score
      @world = world
      # WHICH FLOOR IS BEING PLAYED, counting from nought in the order the cartridge holds them.
      @floor = lasting.var :floor, 0
      # ...and THE SCORE YOU WALKED ONTO IT WITH, the original's oldscore. A death puts the score
      # back to it, and only finishing a floor moves it on, so a death takes back what was scored
      # on the floor it happened on.
      @floor_score = lasting.var :floor_score, 0
      # ...and THE FLOOR THIS GAME BEGAN ON, which is where a new game asked for no floor begins.
      @began_on = lasting.var :began_on, 0
      # ...and WHETHER THE LIFT WAS CALLED BY THE SECRET LEVER, copied in as it is called, and
      # where it takes you from each floor. Only a cartridge holding a secret floor asks.
      if secret_floor?
        @secret = @b.var :_secret_lift, 0
        @to_secret = @b.table :lift_to_secret, secret_floors, width: :byte
        @back = @b.table :lift_back_from_secret, ways_back, width: :byte
      end
      @declared = {}
    end

    # Which floor is being played. Nothing but this writes it; the view reads it to know which
    # slice of every table is this floor's.
    attr_reader :floor

    # START PLAY for +reason+: :new_game, :another_life, :next_floor, or :resume straight after a
    # saved game is loaded.
    #
    # +floor+, for a new game only, is the floor it begins on; without one it begins on the floor
    # the last game began on. +secret+, for the next floor only, is 1 when the secret lever called
    # the lift.
    def start(reason, floor: nil, secret: nil)
      check_request!(reason, floor, secret)
      @began_on.set! floor if floor
      @secret.set! secret if secret && @secret
      @b.call routine_for(reason)
    end

    # WHERE THE LIFT TAKES YOU, read off the original (wl_game.cpp, GameLoop's ex_completed
    # branch) rather than remembered. Three rules and they are tested in this order, which
    # matters:
    #
    #   COMING BACK FROM THE SECRET FLOOR puts you on the normal run of its episode, not one
    #     further along it: the map the original's ElevatorBackTo keeps for that episode.
    #   GOING TO THE SECRET FLOOR is what the secret lever does, and there is one such floor per
    #     episode — the last of its ten, map 9 counting from nought.
    #   OTHERWISE the next floor along.
    #
    # ALL OF IT IS WITHIN THE EPISODE YOU ARE IN, because the original counts its maps from nought
    # within an episode. A cartridge holds floors end to end, perhaps several episodes and perhaps
    # starting partway through one, so each floor's two answers are worked out while the cartridge
    # is built, from where that floor sits in the release, and kept in two tables a floor number
    # reads.
    #
    # A ROUTE TO A FLOOR THE CARTRIDGE DOES NOT HOLD is no route, and that lever goes to the next
    # floor instead. A cartridge holding none at all emits none of the first two rules. Clamping a
    # missing one to a floor it does have would be wrong: the floor it clamps to is the FIRST, so
    # "are you coming back from the secret floor" would become "are you on the first floor", which
    # is true at the start of every game.
    #
    # AND WHEN IT RUNS OUT OF FLOORS it goes round to the first. That is not the original: there a
    # lift never runs out of floors, because the last floor of an episode is left by its way out,
    # not by a lift. Going round beats stopping dead on a lever that does nothing.
    SECRET_FLOOR = 9
    BACK_FROM_SECRET = [1, 1, 7, 3, 5, 3].freeze

    # WHAT EACH REASON ASKS OF THE WORLD, in the order it asks. A new game also puts back the
    # game's own counts, and only the lift leaves the player alone.
    #
    # RESUMING A SAVED GAME asks the least: a load has already put back everything the game keeps
    # (see LastingState), the floor among it, so all that is left is to point every table at that
    # floor again. The original's LoadTheGame (wl_main.cpp) does the same: SetupGameLevel for the
    # floor the save names, then the save read over it.
    STEPS = Ractor.make_shareable({
      new_game: %i[reset_game reset_player select_floor place_player reset_floor],
      another_life: %i[reset_player select_floor place_player reset_floor],
      next_floor: %i[select_floor place_player reset_floor],
      resume: %i[select_floor]
    })
    private_constant :STEPS

    private

    # ONE ROUTINE PER REASON, made the first time anything asks for it. It is a lot of code that
    # runs a few times a game, so it lives outside the console's quick memory; and a cartridge
    # where nothing ever starts play again carries none of it.
    def routine_for(reason)
      once(:"start_#{reason}") do
        case reason
        when :new_game
          @floor.set! @began_on
          @score.set! 0
          @floor_score.set! 0
        when :another_life then @score.set! @floor_score
        when :next_floor
          choose_next_floor
          @floor_score.set! @score
        end
        # ...and :resume changes nothing first: the save already said which floor, and the score.
        STEPS.fetch(reason).each { |step| @b.call step_routine(step) }
      end
    end

    # ...and ONE PER STEP, because most steps are shared by more than one reason, and putting the
    # floor back is the biggest thing here.
    def step_routine(step) = once(:"playthrough_#{step}") { @world.public_send(step) }

    # The routine +name+, with +body+, made if it has not been already.
    def once(name, &body)
      return name if @declared[name]

      @declared[name] = true
      @b.func(name, fast: false, &body)
      name
    end

    def choose_next_floor
      if secret_floor?
        (@back[@floor] >= 0).then { @floor.set! @back[@floor] }
          .else do
            ((@secret == 1) & (@to_secret[@floor] >= 0)).then { @floor.set! @to_secret[@floor] }
              .else { advance_one_floor }
          end
      elsif @floors.count > 1
        advance_one_floor
      end
    end

    def advance_one_floor
      @floor.add! 1
      (@floor > @floors.count - 1).then { @floor.set! 0 }
    end

    # Does any lever on this cartridge lead to a secret floor, or back from one? Worked out once,
    # while the cartridge is built.
    def secret_floor?
      @secret_floor = (secret_floors + ways_back).any? { |slot| slot >= 0 } if @secret_floor.nil?
      @secret_floor
    end

    # WHERE THE SECRET LEVER ON EACH FLOOR TAKES YOU: the secret floor of that floor's own
    # episode, as the cartridge's floor number, or -1 where the cartridge does not hold it. The
    # secret floor itself sends you nowhere secret.
    def secret_floors
      return Array.new(@floors.count, -1) unless @floors.episodes_of_ten?

      @floors.map do |floor|
        episode, map = floor.index.divmod(Floors::PER_EPISODE)
        next -1 if map == SECRET_FLOOR

        holding((episode * Floors::PER_EPISODE) + SECRET_FLOOR)
      end
    end

    # ...AND WHERE THE LEVER ON EACH SECRET FLOOR BRINGS YOU BACK TO, the map its episode keeps in
    # BACK_FROM_SECRET; -1 on every other floor, and where the cartridge does not hold that map.
    def ways_back
      return Array.new(@floors.count, -1) unless @floors.episodes_of_ten?

      @floors.map do |floor|
        episode, map = floor.index.divmod(Floors::PER_EPISODE)
        back = BACK_FROM_SECRET[episode]
        next -1 unless map == SECRET_FLOOR && back

        holding((episode * Floors::PER_EPISODE) + back)
      end
    end

    # Which of the cartridge's floors is the release's map +index+, or -1 where it holds none.
    def holding(index) = @floors.to_a.index { |floor| floor.index == index } || -1

    def check_request!(reason, floor, secret)
      unless STEPS.key?(reason)
        raise ArgumentError, "Play cannot start for #{reason.inspect}. " \
                             "The reasons are #{STEPS.keys.map(&:inspect).join(', ')}."
      end
      if floor && reason != :new_game
        raise ArgumentError, "Only a new game begins on a floor that you choose. " \
                             "To fix this, remove floor: from start(#{reason.inspect})."
      end
      if floor.is_a?(Integer) && !(0...@floors.count).cover?(floor)
        raise ArgumentError, "This cartridge holds #{@floors.count} floors, so floor #{floor} " \
                             "does not exist. Give a floor from 0 to #{@floors.count - 1}."
      end
      if secret && reason != :next_floor
        raise ArgumentError, "A lever calls only the lift. " \
                             "To fix this, remove secret: from start(#{reason.inspect})."
      end
      return unless reason == :next_floor && secret.nil? && secret_floor?

      raise ArgumentError, "This cartridge holds a secret floor, so the lift must know which lever " \
                           "called it. To fix this, give secret: to start(:next_floor)."
    end
  end
end
