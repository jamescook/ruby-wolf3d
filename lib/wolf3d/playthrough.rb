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
    def initialize(build:, floors:, score:, world:)
      @b = build
      @floors = floors
      @score = score
      @world = world
      # WHICH FLOOR IS BEING PLAYED, counting from nought in the order the cartridge holds them.
      @floor = @b.var :floor, 0
      # ...and THE SCORE YOU WALKED ONTO IT WITH, the original's oldscore. A death puts the score
      # back to it, and only finishing a floor moves it on, so a death takes back what was scored
      # on the floor it happened on.
      @floor_score = @b.var :floor_score, 0
      # ...and THE FLOOR THIS GAME BEGAN ON, which is where a new game asked for no floor begins.
      @began_on = @b.var :began_on, 0
      # ...and WHETHER THE LIFT WAS CALLED BY THE SECRET LEVER, copied in as it is called. Only
      # a cartridge holding a secret floor asks.
      @secret = @b.var :_secret_lift, 0 if secret_floor?
      @declared = {}
    end

    # Which floor is being played. Nothing but this writes it; the view reads it to know which
    # slice of every table is this floor's.
    attr_reader :floor

    # START PLAY for +reason+.
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

    # WHERE THE LIFT TAKES YOU, read off the original (wl_game.cpp) rather than remembered. Three
    # rules and they are tested in this order, which matters:
    #
    #   COMING BACK FROM THE SECRET FLOOR puts you on the normal run, not one further along it.
    #     The original keeps a small table of where each episode comes back to; for the first it
    #     is the second floor.
    #   GOING TO THE SECRET FLOOR is what the secret lever does, and there is one such floor per
    #     episode — the last of the ten.
    #   OTHERWISE the next floor along.
    #
    # A CARTRIDGE HOLDING FEWER FLOORS THAN A WHOLE EPISODE has no secret floor, so neither of the
    # first two rules is emitted at all and every lever simply goes to the next floor. Clamping
    # them to a floor it does have was tried and is wrong in a way worth remembering: the floor a
    # missing one clamps to is the FIRST, so "are you coming back from the secret floor" became
    # "are you on the first floor", which is true at the start of every game.
    #
    # AND WHEN IT RUNS OUT OF FLOORS it goes round to the first. That is not the original, which
    # has an episode to end; this has nowhere to put an ending yet, and going round beats stopping
    # dead on a lever that does nothing.
    SECRET_FLOOR = 9
    BACK_FROM_SECRET = 1

    private

    # WHAT EACH REASON ASKS OF THE WORLD, in the order it asks. A new game also puts back the
    # game's own counts, and only the lift leaves the player alone.
    STEPS = Ractor.make_shareable({
      new_game: %i[reset_game reset_player select_floor place_player reset_floor],
      another_life: %i[reset_player select_floor place_player reset_floor],
      next_floor: %i[select_floor place_player reset_floor]
    })

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
        (@floor == SECRET_FLOOR).then { @floor.set! BACK_FROM_SECRET }
          .else do
            (@secret == 1).then { @floor.set! SECRET_FLOOR }.else { advance_one_floor }
          end
      elsif @floors.count > 1
        advance_one_floor
      end
    end

    def advance_one_floor
      @floor.add! 1
      (@floor > @floors.count - 1).then { @floor.set! 0 }
    end

    def secret_floor? = @floors.count > SECRET_FLOOR

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
        raise ArgumentError, "Only the lift is called by a lever. " \
                             "To fix this, remove secret: from start(#{reason.inspect})."
      end
      return unless reason == :next_floor && secret.nil? && secret_floor?

      raise ArgumentError, "This cartridge holds a secret floor, so the lift must know which lever " \
                           "called it. To fix this, give secret: to start(:next_floor)."
    end
  end
end
