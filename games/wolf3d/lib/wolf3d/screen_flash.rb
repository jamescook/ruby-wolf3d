# frozen_string_literal: true

module Wolf3D
  # THE SCREEN GOES RED WHEN YOU ARE HIT AND GOLD WHEN YOU PICK SOMETHING UP.
  #
  # THIS IS NOT IN ANY SOURCE ANYBODY CAN READ. The routines were left out of the WL_PLAY.C id
  # released, but they are in the shipped game, and WOLF3D.MAP says
  # where. Everything here is read out of WOLF3D.EXE at those addresses: StartBonusFlash, 0x10889;
  # StartDamageFlash, 0x10894; UpdatePaletteShifts, 0x108A0; InitRedShifts, 0x1070C.
  #
  # TWO COUNTS, AND THEY ARE NOT THE SAME KIND. A pickup SETS its count to eighteen, so two in quick
  # succession restart the flash. A hit ADDS what it took, so a hard hit shows longer and hits stack.
  # Each pass the count says which step shows, a count of ten to a red and six to a gold, and both
  # come down by a pass's worth. Red wins if both are running.
  #
  # IT IS ONLY WORK WHEN IT MOVES. The picture on this screen is numbers into one table of colours, so
  # a tint rewrites the table, which costs nothing on a pass where the step has not changed.
  class ScreenFlash
    game_variables :damage, :running, :red, :gold, :wanted, :bonus, :shown, saved: false

    # HOW FAR TOWARD THE COLOUR EACH STEP GOES, as a percentage. InitRedShifts builds six reds at one
    # eighth a step and three golds at one twentieth a step, which is why gold is a glance and red can
    # all but fill the screen.
    REDS = (1..6).map { |step| step * 100 / 8 }.freeze
    GOLDS = (1..3).map { |step| step * 100 / 20 }.freeze

    # The original's colour for each is out of 64 a channel: (64, 0, 0) and (64, 62, 0).
    GOLD = [31, 30, 0].freeze

    # EVERYTHING COUNTS IN SIXTHS OF THE ORIGINAL'S UNIT and comes down by Enemy::SIXTHS_A_PASS, the
    # clock every enemy is on too.
    SIXTHS = Enemy::SIXTHS
    PER_PASS = Enemy::SIXTHS_A_PASS

    BONUS_COUNT = 18 * SIXTHS
    A_RED = 10 * SIXTHS
    A_GOLD = 6 * SIXTHS

    def initialize(build:)
      @b = build
      declare
    end

    # YOU WERE HIT, for +points+. A wound of nothing, which the easiest setting can make, shows nothing.
    def hurt(points)
      @damage += points * SIXTHS
      @running = 1
    end

    # YOU PICKED SOMETHING UP.
    def bonus
      @bonus = BONUS_COUNT
      @running = 1
    end

    # One pass, and nearly always one comparison.
    def update
      @b.call :the_flash_runs if @running == 1
    end

    # THE FLASH IS PUT AWAY AT ONCE, by a death and by a floor starting. The tint would otherwise lie
    # over whatever comes next.
    def finish
      @b.call :the_flash_stops if @running == 1
    end

    private

    # NOT IN A SAVED GAME: the original's counts are plain variables outside its gamestate.
    def declare
      b = @b
      @damage = 0
      @bonus = 0
      @running = 0
      @shown = 0
      @red = 0
      @gold = 0
      @wanted = 0
      @percent = b.table :flash_percent, [0] + REDS + GOLDS, width: :byte
      b.func(:the_flash_shows, fast: false) { show }
      b.func(:the_flash_runs, fast: false) { run }
      b.func(:the_flash_stops, fast: false) { stop }
    end

    def run
      @red = 0
      @gold = 0
      if @damage > 0
        @red = (@damage / A_RED) + 1
        @red.clamp! 0, REDS.length
        @damage -= PER_PASS
        @damage = 0 if @damage < 0
      end
      if @bonus > 0
        @gold = (@bonus / A_GOLD) + 1
        @gold.clamp! 0, GOLDS.length
        @bonus -= PER_PASS
        @bonus = 0 if @bonus < 0
      end
      @wanted = 0
      @wanted = REDS.length + @gold if @gold > 0
      @wanted = @red if @red > 0
      @b.call :the_flash_shows if @wanted != @shown
      @running = 0 if @wanted == 0
    end

    def show
      @shown = @wanted
      if @shown > REDS.length
        @b.tint @b.rgb(*GOLD), @percent[@shown]
      else
        @b.tint :red, @percent[@shown]
      end
    end

    def stop
      @damage = 0
      @bonus = 0
      @wanted = 0
      @running = 0
      show
    end
  end
end
