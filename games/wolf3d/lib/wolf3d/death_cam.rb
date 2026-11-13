# frozen_string_literal: true

module Wolf3D
  # HOW AN EPISODE ENDS WHEN ITS BOSS HAS NO WAY OUT BEHIND HIM. Schabbs, Giftmacher, Fettgesicht and
  # Hitler fall, the game says "Let's see that again!", and the view is put down in front of the body
  # and watches him fall a second time. Then the episode is over (A_StartDeathCam, wl_act2.cpp).
  #
  # THE VIEW HAS NO CAMERA OF ITS OWN, and neither has the original's. The player IS the camera, so
  # the player is what is moved: back to where you stood when you killed him, turned to face him
  # exactly, and then set down a little way in front of him and pushed back until that is not inside
  # a wall. You are out of the game from then on, so it does not matter where that leaves you.
  #
  # THE SAME ROUTINE RUNS TWICE. The picture of the body ends the fall with this, and the second
  # fall ends with this again, which is how the original knows it has seen enough.
  #
  # WHAT THIS LEAVES OUT: the fizzle back from the words into the replay. The original dots that one
  # in as well, but it is a fizzle to a whole new picture rather than to one colour, so here the
  # picture simply changes. See Fizzle.
  class DeathCam
    game_variables kill_x: :kill_x, kill_y: :kill_y

    game_variables :showing_words, :count, :boss, :blink, :boss_x, :boss_y, :dx, :dy, :best, :this, :far,
                   :angle, :done, :stage, :holding, saved: false

    # WHERE IT HAS GOT TO. Nought is that nothing is happening, and it is what the menus read.
    NOT_RUNNING = 0
    FIRST_HOLD = 1 # the body lies there a moment, with the world stopped
    FIZZLING = 2       # the view dots over to the ground the words stand on
    WORDS = 3      # "Let's see that again!"
    REPLAY = 4     # he falls again, in front of you
    LAST_HOLD = 5  # ...and lies there a moment, and the episode is over

    # The words, on two lines: at sixteen pixels a letter the one line would not fit.
    FIRST_LINE = "LET'S SEE"
    SECOND_LINE = "THAT AGAIN!"
    PRINTED = Ractor.make_shareable((FIRST_LINE + SECOND_LINE).delete(" ").chars.uniq)

    # The ground, the same as the screen between floors, and where the two lines sit on it.
    GROUND = 0x7f
    FIRST_Y = 40
    SECOND_Y = 64

    # HOW LONG IT HOLDS, in passes. The original waits 100 of its units with the body lying there, and
    # up to 300 for the words, which a press cuts short. These run by the pass like the rest of the
    # world, so where the world runs slow they do too.
    HOLD = 100 * Enemy::SIXTHS / Enemy::SIXTHS_A_PASS
    WORDS_FOR = 300 * Enemy::SIXTHS / Enemy::SIXTHS_A_PASS

    # THE BANNER FLASHES on 32 units of the clock and off for 32 (GetTimeCount()&32, wl_draw.cpp).
    BANNER_FOR = 32 * Enemy::SIXTHS / Enemy::SIXTHS_A_PASS

    # HOW FAR FROM THE BODY IT SETS YOU DOWN, and how far back each try after that (0x14000 and
    # 0x1000), and how wide a thing it wants to be clear of walls (the player's own box, PLAYERSIZE).
    FIRST_TRY = 0x14000 / Enemy::CELL.to_f
    NEXT_TRY = 0x1000 / Enemy::CELL.to_f
    BOX = 0x5800 / Enemy::CELL.to_f
    # ENOUGH TO CROSS THE WIDEST FLOOR, which is the original's "until it fits" with an end to it.
    TRIES = 64 * 16

    # +sines+ is the view's table, because the angle to the body is found by trying them. +lasting+
    # is what a saved game holds, which the spot you killed him from is part of (gamestate.killx).
    def initialize(build:, player:, sines:, victory:, lettering:, lasting:)
      @b = build
      @player = player
      @sines = sines
      @victory = victory
      @lettering = lettering
      @lasting = lasting
      declare
    end

    # WHAT MOVES THE BOSS AND ASKS ABOUT WALLS. Handed over after it is made, because it is told
    # about this too.
    def works_with(mind)
      @mind = mind
    end

    # How far it has got, nought when it is not running.
    attr_reader :stage

    # 1 while the whole world stands still for it, and what it is to have the words up.
    attr_reader :holding, :showing_words

    # YOU KILLED HIM FROM HERE, which has to be caught as he goes down, for he takes a while to fall
    # and you can walk about while he does (KillActor, wl_state.cpp).
    def remember_the_spot
      @kill_x = @player.x
      @kill_y = @player.y
    end

    # A BOSS HAS FINISHED FALLING. +guard+ is who.
    def he_is_down(guard)
      if @stage == NOT_RUNNING
        @boss = guard.index
        @boss_x = guard.x
        @boss_y = guard.y
        hold_for(FIRST_HOLD, HOLD)
      elsif @stage == REPLAY
        hold_for(LAST_HOLD, HOLD)
      end
    end

    # One pass while the world stands still.
    def update = @b.call(:the_death_cam_waits)

    # The words, painted when they go up and then left alone.
    def draw = @picture.draw

    # WHILE THE DOTS GO ON the view is not drawn, or it would paint over them. Dying's the same.
    def fizzling = @stage == FIZZLING
    def scatter_dots = @b.call(:death_cam_fizzle)

    # IS THE BANNER UP ON THIS PASS? It only is on the replay. Called once a pass, where it is drawn.
    def banner_is_up
      @blink += 1 if @stage == REPLAY
      @stage == REPLAY && ((@blink / BANNER_FOR) % 2) == 0
    end

    # A FLOOR STARTED AGAIN has no death cam running on it, whatever a game that ended left behind.
    def start_again
      @stage = NOT_RUNNING
      @holding = 0
      @showing_words = 0
    end

    private

    def declare
      b = @b
      @stage = NOT_RUNNING
      @holding = 0
      @showing_words = 0
      @count = 0
      @boss = 0
      @blink = 0
      @kill_x = 0.0
      @lasting.keep @kill_x
      @kill_y = 0.0
      @lasting.keep @kill_y
      @boss_x = 0.0
      @boss_y = 0.0
      @dx = 0.0
      @dy = 0.0
      @best = 0.0
      @this = 0.0
      @far = 0.0
      @angle = 0
      @done = 0
      @picture = b.keep_showing(:death_cam_words) { paint }
      @dots = Fizzle.new(build: b, colour: Palette.game[GROUND])
      b.func(:death_cam_fizzle) { @dots.scatter_dots }
      b.func(:the_death_cam_waits, fast: false) { wait }
      b.func(:the_death_cam_lines_up, fast: false) { line_up }
    end

    def hold_for(stage, passes)
      @stage = stage
      @count = passes
      @holding = 1
    end

    def wait
      @count -= 1
      if @stage == WORDS
        @b.call :the_death_cam_lines_up if @count <= 0 || @b.pressed(:any)
      elsif @stage == FIZZLING
        show_words if @dots.finished
      elsif @count <= 0
        @stage == FIRST_HOLD ? start_fizzle : @victory.won
      end
    end

    # BOTH PICTURES HOLD THE SAME ROOM by now, since the world has stood still for the whole of the
    # hold, so the two walkers are dotting over one view and it cannot shudder.
    def start_fizzle
      @dots.start_again
      @stage = FIZZLING
    end

    def show_words
      hold_for(WORDS, WORDS_FOR)
      @showing_words = 1
      @picture.changed
    end

    def paint
      @b.dma_fill_rect 0, 0, FirstPerson::ACROSS, FirstPerson::VIEW_H, Palette.game[GROUND]
      @lettering.write FIRST_LINE, @lettering.centred(FIRST_LINE), FIRST_Y
      @lettering.write SECOND_LINE, @lettering.centred(SECOND_LINE), SECOND_Y
    end

    # BACK TO WHERE YOU STOOD, FACING HIM, and then as near as it will go. Then he falls again.
    def line_up
      face_him_from_the_spot
      set_down_in_front_of_him
      @showing_words = 0
      @holding = 0
      @stage = REPLAY
      @mind.fall_again(@boss)
    end

    # THE ANGLE IS FOUND BY TRYING THEM ALL, once in a game: the one whose heading has the most of
    # the line to him along it. There is no arctangent here, and this is not worth carrying one for.
    def face_him_from_the_spot
      @dx = @boss_x - @kill_x
      @dy = @boss_y - @kill_y
      @best = -1000.0
      @b.repeat(FirstPerson::TURN) do |a|
        @this = @dx * @sines[(a + FirstPerson::QUARTER) % FirstPerson::TURN]
        @this += @dy * @sines[a]
        if @this > @best
          @best = @this
          @angle = a
        end
      end
      @player.angle = @angle
    end

    def set_down_in_front_of_him
      @dx = @sines[(@angle + FirstPerson::QUARTER) % FirstPerson::TURN]
      @dy = @sines[@angle]
      @far = FIRST_TRY
      @done = 0
      @b.repeat(TRIES, stop_when: @done == 1) do
        @player.x = @boss_x - (@dx * @far)
        @player.y = @boss_y - (@dy * @far)
        @done = 1
        @done = 0 if @mind.blocked_around(@player.x, @player.y, BOX)
        @far += NEXT_TRY
      end
    end
  end
end
