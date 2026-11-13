# frozen_string_literal: true

module Wolf3D
  # DYING: the view turns to face whatever killed you, and then dots over to red.
  #
  # Read out of the original (wl_game.cpp, Died) rather than remembered. Two things happen and
  # the order is the point. First the view rotates until it is looking straight at the guard who
  # shot you, drawing every step — which is what makes a death read as being killed BY
  # something rather than as the game stopping. Then the view fills with red one pixel at a
  # time, scattered, and closes up.
  #
  # NOTHING ELSE RUNS while either is happening. No walking, no guards, no doors — the world
  # stops the moment you are hit. That is what the original does and it is also what makes this
  # affordable: the eighty rays and eighty stretched columns that a normal frame spends nearly
  # all of itself on are simply not drawn once the fizzle starts, so the whole frame is free for
  # the dots.
  class Dying
    game_variables state: :dying

    # Where whatever killed you stood (Died's killerobj), which the view turns to face.
    game_variables :kill_x, :kill_y, saved: false
    # #turn's bearing on him: where the eye points, the line to him, which side of the eye he is
    # on, and that side as plus or minus one on this pass and the one before.
    game_variables :cos, :sin, :to_x, :to_y, :side, :now, :was, saved: false
    # How many passes the turn has taken, and how many the settled view has been drawn (#settle).
    game_variables :turned, :held, saved: false

    # What the player is doing. Everything else in the game asks this before it moves.
    ALIVE = 0
    TURNING = 1   # facing whatever killed you
    FIZZLING = 2  # the view fizzling over to red
    GONE = 3      # the story is told — what happens next is Lives's business, not this one's

    # The red, out of the game's own 256, which is the one the original fills with.
    INK = 4

    # HOW THE TURN ENDS. It turns a step at a time toward the killer and stops when it goes PAST
    # him — which is the only test that needs no angle worked out, and no arctangent exists here
    # to work one out with. The cap is a half turn's worth of steps and a couple over, so a
    # killer standing exactly behind you still finishes.
    #
    # A STEP IS THE ORIGINAL'S, DEATHROTATE two degrees a tic (wl_game.cpp Died), which of a
    # 1024-unit turn is nearest six.
    STEP_ANGLE_UNITS = 6
    MOST_TURNS = (FirstPerson::TURN / (2 * STEP_ANGLE_UNITS)) + 2

    # ...and then the view is drawn a couple more times before the dots start. Both pages have to
    # be holding the SAME settled picture when the drawing stops, or the display spends the whole
    # fizzle alternating between two views a turn-step apart, which reads as a shudder.
    SETTLE = 2

    # +lasting+ is what a saved game holds (see LastingState). Only whether you are dying is in
    # it; the rest is working room that each death begins by putting back. +sines+ is the view's
    # table of sines, which the player's own +sin+ is one entry of: the view turns as you die, so
    # this works the angle's sine out again from the table rather than waiting for a move to.
    def initialize(build:, player:, sines:, lasting: LastingState.new(build:), flash: nil, sounds: nil)
      @b = build
      @flash = flash # the red of the hit that did it, put away as the red of the death begins
      @sounds = sounds
      @player = player
      @sines = sines
      @lasting = lasting
      declare
    end

    # Which of the four above you are at, for a menu that must not open over a death: the view is
    # not redrawn once the dots start, so nothing would ever paint over the menu.
    attr_reader :state

    # What the rest of the game asks before it moves or draws.
    def alive = @state == ALIVE
    def showing_the_world = @state <= TURNING

    # ...and what the thing that counts your lives asks: the last dot is down and the view is
    # wholly red, so it is time either to start the floor again or to say the game is over. This
    # stays true until somebody does one of the two.
    def finished = @state == GONE

    # BACK TO THE TOP, for another go at the floor: alive again. What the last death remembered is
    # dropped when the next one begins — see #struck_by.
    def start_again = @state = ALIVE

    # A shot has landed and taken the last of the health. Remember where it came from — the turn
    # is the whole reason a death needs to know — and begin the death from its beginning: no turn
    # taken yet, and the dots back to the beginning.
    #
    # PUT BACK HERE, AS EACH DEATH BEGINS, because a saved game keeps whether you are dying and
    # none of the rest (see LastingState). A game loaded after a death has run to its end comes
    # back alive with that death's count still at its end, and the next death has to start from
    # nothing all the same, or it would draw no red at all.
    def struck_by(guard)
      if @state == ALIVE
        @sounds&.play_adlib_named(:player_death)
        @kill_x = guard.x
        @kill_y = guard.y
        @state = TURNING
        @was = 0
        @turned = 0
        @held = 0
        @dots.start_again
      end
    end

    # One frame of the turn. Which side of straight-ahead the killer is on decides which way to
    # go, and going PAST him is what says stop.
    #
    # WHICH SIDE HE IS ON, without an angle: point a vector where the eye points, point another
    # at the killer, and ask which way the second is from the first. That is one multiply each
    # way and a subtraction, and its SIGN is the answer — positive one side, negative the other.
    # When the sign is not the one it was last frame, the turn has crossed him and is done.
    def turn
      if @state == TURNING
        @cos = @sines[@player.angle + FirstPerson::QUARTER]
        @sin = @sines[@player.angle]
        @to_x = @kill_x - @player.x
        @to_y = @kill_y - @player.y
        @side = (@cos * @to_y) - (@sin * @to_x)

        @now = -1
        @now = 1 if @side > 0.0
        # The first frame has nothing to compare against, so it only takes a bearing.
        @was = @now if @was == 0
        if @now == @was
          swing
        else
          settle
        end
        @turned += 1
        settle if @turned >= MOST_TURNS
      end
    end

    # ...and one frame of the fizzle, which is the whole of what a frame does once it starts.
    def draw
      # Not on a normal frame: this runs for a second or two at the end of a life and never
      # otherwise.
      @b.call(:dying_fizzle) if @state == FIZZLING
    end

    private

    def swing
      if @now == 1
        @player.angle += STEP_ANGLE_UNITS
      else
        @player.angle -= STEP_ANGLE_UNITS
      end
    end

    # He is in front of us. Draw the settled view a couple more times so both pages agree, then
    # stop drawing it at all.
    def settle
      @held += 1
      if @held >= SETTLE
        @state = FIZZLING
        # THE FLASH OF THE LAST HIT ENDS HERE, after the turn, which is where the original's Died
        # calls FinishPaletteShifts (wl_game.cpp).
        @flash&.finish
      end
    end

    def declare
      b = @b
      @state = ALIVE
      @lasting.keep @state
      @kill_x = 0.0
      @kill_y = 0.0

      # WORKING ROOM. Each goes by a name of its own (dying_side), so it never takes the kind of
      # number another part's variable of the same name was given first.
      @cos = 0.0
      @sin = 0.0
      @to_x = 0.0
      @to_y = 0.0
      @side = 0.0
      @now = 0
      @was = 0

      @turned = 0
      @held = 0

      @dots = Fizzle.new(build: b, colour: Palette.game[INK])
      declare_the_scattering
    end

    # A ROUTINE RATHER THAN WRITTEN STRAIGHT IN THE LOOP, for the same reason the status bar is
    # one: the game loop is what the framework keeps in the console's quick memory and it has
    # about a page to spare.
    #
    # AND IT HAS TO STAY IN THAT MEMORY, which is not obvious and was tried the other way.
    #
    # This runs on almost no frames — a second or two at the end of a life — so it looks like
    # an easy thing to turn out of quick memory in favour of something that runs every frame.
    # It is not. A frame that IS fizzling has the whole frame to itself and only just fits in
    # it: run from the cartridge, one frame of the scatter costs more than a frame holds, and
    # the effect stops keeping up — measurably, it stops covering the view at all.
    #
    # So rare is not the same as cheap-to-slow-down. What decides this is the worst frame it
    # ever takes part in, and there it is the only thing running.
    def declare_the_scattering
      @b.func(:dying_fizzle) do
        @dots.scatter_dots
        @state = GONE if @dots.finished
      end
    end
  end
end
