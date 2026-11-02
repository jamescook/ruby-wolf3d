# frozen_string_literal: true

module Wolf3D
  # THE SCREEN BETWEEN TWO FLOORS: how much of the one you just left you found, and what that was
  # worth. It is the original's LevelCompleted (wl_inter.cpp), and every rule here is read from it.
  #
  # THREE PERCENTAGES: the floor's guards killed, its secret walls shoved and its treasures taken.
  # Each is a share of what the floor held, on whole numbers and rounded down, and a floor that
  # held none of something reads nought rather than a hundred. A hundred per cent of any of them
  # is worth ten thousand points, which is why a player goes back for the last guard.
  #
  # AND THE CLOCK AGAINST PAR. Every ordinary floor has a par time, a target out of a table in the
  # original, and each whole second left of it when you reach the lift is worth five hundred
  # points. Finishing late takes nothing away. The clock is FloorRecords', and that says why it is
  # game time rather than a stopwatch.
  #
  # THE FIGURES COUNT UP FROM NOTHING, one at a time: the par bonus, then kills, secrets and
  # treasure, with each hundred per cent landing on the bonus as its figure finishes. A press
  # during that jumps every figure to its end, and it takes another press to leave. The score is
  # paid when the figures end, however they ended, which is the one moment the original pays it.
  #
  # THE TWO FLOORS AT THE END OF AN EPISODE ARE DIFFERENT. A map from the ninth on has no
  # percentages at all. It says the floor is done and hands over a flat fifteen thousand. The
  # original words that for the secret floor, because it is the only one of the two with a lift:
  # the boss floor is left by walking out, which is Victory's business.
  #
  # IT IS WRITTEN IN THE GAME'S OWN BIG LETTERING, a picture sixteen pixels square for each
  # character. Those were laid out for a screen eighty pixels wider, so the wording is cut to fit:
  # the original's "treasure ratio" alone would take fourteen of the fifteen letters across, with
  # nowhere to put its figure. Saying RATIO three times is what goes. Eight rows of those letters
  # fill the space above the bar exactly, so the rows touch.
  #
  # WHAT THIS LEAVES OUT of the original's screen: the sounds that go with the figures and the
  # music, which are AdLib and wait on that work; and BJ breathing at the side, who is as wide as a
  # third of this screen and cannot sit beside these letters.
  #
  # NOTHING SAYS TO PRESS A BUTTON, as nothing does in the original. See Menus: there is no "press
  # start" anywhere in Wolfenstein.
  class Tally
    # The ground, the original's VIEWCOLOR out of its 256 (wl_menu.h), which the lettering's own
    # pictures are painted on. The ink is for a release with no lettering to read.
    GROUND = 0x7f
    INK = 15

    # PERCENT100AMT and PAR_AMOUNT, and what a floor with no percentages hands over instead.
    FOR_A_HUNDRED_PER_CENT = 10_000
    PAR_AMOUNT = 500
    FOR_A_SECRET_FLOOR = 15_000

    # A MAP NUMBERED FROM THIS ONE ON HAS NO PERCENTAGES: the test is `mapon < 8` in the original,
    # counting from nought within an episode.
    NO_PERCENTAGES_FROM = 8

    # How often a climbing figure ticks: `i % 10` and `i % (PAR_AMOUNT / 10)`.
    TICK_EVERY_PER_CENT = 10
    TICK_EVERY_SECONDS = 50

    # parTimes, wl_inter.cpp, in seconds: an episode to a row and its eight ordinary floors. The
    # original writes these in minutes, and its "??:??" for the last two floors of an episode is
    # never shown, because those floors do not have this part of the screen.
    PAR_SECONDS = Ractor.make_shareable(
      [[90, 120, 120, 210, 180, 180, 150, 150],
       [90, 210, 180, 120, 240, 360, 60, 180],
       [90, 90, 150, 150, 210, 150, 120, 360],
       [120, 120, 90, 60, 270, 210, 120, 270],
       [150, 90, 150, 150, 240, 180, 270, 210],
       [390, 240, 270, 360, 300, 330, 330, 510]]
    )

    # WHICH FIGURE IS COUNTING, in the original's order, then none.
    COUNTING_PAR = 0
    COUNTING_KILLS = 1
    COUNT_FINISHED = 4

    # HOW MUCH A FIGURE CLIMBS IN A FRAME. The original's own pace is the length of a sound that
    # is not on this cartridge, so these come from what it puts on the screen instead: when it is
    # drawing to a hidden page it shows every other percentage (`i & 1`) and every tenth second of
    # par (`i % (PAR_AMOUNT / 50)`).
    RATIO_STEP = 2
    PAR_STEP = 10

    RATIOS = { kill: "KILL", secret: "SECRET", treasure: "TREASURE" }.freeze
    HEADING = "COMPLETED"
    FLOOR = "FLOOR "
    SECRET_HEADING = "SECRET FLOOR"
    BONUS = "BONUS"
    TIME = "TIME"
    PAR = "PAR"

    # Every character on this screen. See BigLettering.
    PRINTED = Ractor.make_shareable(
      (RATIOS.values + [HEADING, FLOOR, SECRET_HEADING, BONUS, TIME, PAR, "!%:", "0123456789"])
        .join.delete(" ").chars.uniq
    )

    # EVERY POSITION IS EVEN, because a picture on this screen has to start on an even column.
    LETTER = BigLettering::LETTER
    FLOOR_Y = 0
    COMPLETED_Y = FLOOR_Y + LETTER
    BONUS_Y = COMPLETED_Y + LETTER
    TIME_Y = BONUS_Y + LETTER
    PAR_Y = TIME_Y + LETTER
    RATIOS_Y = PAR_Y + LETTER

    # Three digits and a percent sign end where everything else ends: the bonus's six digits, the
    # most it can reach, and the five places of a time. Each label stops short of its figure.
    PERCENT_X = 200
    RIGHT_X = PERCENT_X + LETTER
    FIGURES_X = PERCENT_X - (3 * LETTER)
    BONUS_DIGITS = 6
    BONUS_X = RIGHT_X - (BONUS_DIGITS * LETTER)
    CLOCK_X = RIGHT_X - (5 * LETTER)
    GAP = 8

    # +totals+ is what the floor held, as :kill, :secret and :treasure. +floor+ is which floor is
    # being played, and +secret_lift+ says which lever called the lift, for the playthrough.
    # +lettering+ is what the words are written in, or the framework's font if nothing says. See
    # BigLettering. +records+ holds the floor's clock and keeps how it went.
    def initialize(build:, player:, scoring:, totals:, floors:, floor:, playthrough:, secret_lift:, records:,
                   lettering: BigLettering.new(build:, art: nil, printed: []), sounds: nil)
      @b = build
      @sounds = sounds
      @player = player
      @scoring = scoring
      @floors = floors
      @floor = floor
      @playthrough = playthrough
      @secret_lift = secret_lift
      @lettering = lettering
      @records = records
      @found = { kill: [player.kills, totals.fetch(:kill)],
                 secret: [player.secrets, totals.fetch(:secret)],
                 treasure: [player.treasures, totals.fetch(:treasure)] }
      declare
    end

    # 1 while this screen is up, which is what stops the world.
    attr_reader :showing

    # THE LIFT HAS ARRIVED: work the floor out and put the screen up.
    def floor_finished = @b.call(:tally_floor)

    # ONE PASS WITH THE SCREEN UP. A or B moves things on, and it takes a NEW press, so the finger
    # already on the trigger as the lift arrived does not skip anything. The figures climb by the
    # frame, so the count takes as long however much a pass costs.
    def update
      @b.call :tally_read_press
      @b.once_a_frame(:tally_count) { count_up }
    end

    # The picture, which is painted as the figures change and then left alone.
    def draw = @picture.draw

    private

    # NONE OF THESE IS IN A SAVED GAME, which is what the underscores say. The game cannot be saved
    # with this screen up, because the menu cannot be opened over it.
    def declare
      @showing = @b.var :_tally_showing, 0
      @stage = @b.var :_tally_stage, COUNT_FINISHED
      @bonus = @b.var :_tally_bonus, 0
      @shown_bonus = @b.var :_tally_shown_bonus, 0
      @time_left = @b.var :_tally_time_left, 0
      @shown_time_left = @b.var :_tally_shown_time_left, 0
      @minutes = @b.var :_tally_minutes, 0
      @seconds = @b.var :_tally_seconds, 0
      @ratios = RATIOS.keys.to_h { |name| [name, @b.var(:"_#{name}_ratio", 0)] }
      @shown = RATIOS.keys.to_h { |name| [name, @b.var(:"_#{name}_shown", 0)] }
      numbers = @floors.map { |floor| map_of(floor) + 1 }
      @floor_digits = numbers.max.to_s.length
      @floor_number = @b.table :tally_floor_number, numbers, width: :byte
      @no_percentages = @b.table :tally_no_percentages, @floors.map { |floor| percentages?(floor) ? 0 : 1 },
                                 width: :byte
      @par_seconds = @b.table :tally_par_seconds, @floors.map { |floor| par_of(floor) }, width: :half
      @picture = @b.keep_showing(:tally_picture) { paint }
      @b.func(:tally_floor, fast: false) { start_tally }
      @b.func(:tally_read_press, fast: false) { read_press }
      @b.func(:tally_finish_count, fast: false) { finish_count }
    end

    # Which map of its episode a floor is. A release not divided into tens has no last two floors
    # to treat differently, so every one of its floors is an ordinary one.
    def map_of(floor) = @floors.episodes_of_ten? ? floor.index % Floors::PER_EPISODE : floor.index
    def percentages?(floor) = !@floors.episodes_of_ten? || map_of(floor) < NO_PERCENTAGES_FROM

    # A release not divided into tens is not the one these par times were set for, so it has none.
    def par_of(floor)
      return 0 unless @floors.episodes_of_ten? && map_of(floor) < NO_PERCENTAGES_FROM

      PAR_SECONDS.fetch(floor.index / Floors::PER_EPISODE).fetch(map_of(floor))
    end

    def start_tally
      @records.stop_clock
      @minutes = @records.seconds_played / 60
      @seconds = @records.seconds_played % 60
      @shown_bonus = 0
      @shown_time_left = 0
      RATIOS.each_key { |name| @shown[name] = 0 }
      if @no_percentages[@floor] == 1
        @bonus = FOR_A_SECRET_FLOOR
        @time_left = 0
        finish_count
      else
        work_out_bonus
        @stage = COUNTING_PAR
      end
      # The original takes your keys before this screen, so the bar is already empty on it.
      @player.keys = 0
      @showing = 1
      @picture.changed
    end

    def work_out_bonus
      @time_left = 0
      @time_left = @par_seconds[@floor] - @records.seconds_played if @records.seconds_played < @par_seconds[@floor]
      @bonus = @time_left * PAR_AMOUNT
      @found.each do |name, (found, total)|
        @ratios[name] = 0
        @ratios[name] = found * 100 / total if total > 0
        @bonus += FOR_A_HUNDRED_PER_CENT if @ratios[name] >= 100
      end
      @records.record(@floor_number[@floor] - 1, kill: @ratios[:kill], secret: @ratios[:secret], treasure: @ratios[:treasure])
    end

    def read_press
      if @b.pressed(:a) || @b.pressed(:b)
        if @stage < COUNT_FINISHED
          finish_count
        else
          @showing = 0
          @playthrough.start(:next_floor, secret: @secret_lift)
        end
      end
    end

    def count_up
      if @stage < COUNT_FINISHED
        count_par if @stage == COUNTING_PAR
        RATIOS.each_key.with_index(COUNTING_KILLS) { |name, stage| count_ratio(name) if @stage == stage }
        @b.call :tally_finish_count if @stage == COUNT_FINISHED
        @picture.changed
      end
    end

    # A TICK AS THE FIGURES CLIMB, AND ONE SOUND AS EACH ARRIVES (wl_inter.cpp, LevelCompleted). The
    # original waits for each sound before it goes on. Here the pace is the step above, so the
    # ticks fall where they fall and a later one cuts an earlier one off.
    def count_par
      @shown_time_left += PAR_STEP
      if @shown_time_left >= @time_left
        @shown_time_left = @time_left
        @stage = COUNTING_KILLS
        @sounds&.adlib(:tally_done) if @time_left > 0
      elsif @shown_time_left % TICK_EVERY_SECONDS == 0
        @sounds&.adlib(:tally_tick)
      end
      @shown_bonus = @shown_time_left * PAR_AMOUNT
    end

    def count_ratio(name)
      @shown[name] += RATIO_STEP
      if @shown[name] >= @ratios[name]
        @shown[name] = @ratios[name]
        @shown_bonus += FOR_A_HUNDRED_PER_CENT if @ratios[name] >= 100
        @stage += 1
        sound_final_ratio(@ratios[name])
      elsif @shown[name] % TICK_EVERY_PER_CENT == 0
        @sounds&.adlib(:tally_tick)
      end
    end

    # Full marks and nothing at all each have a sound of their own, and the rest share one.
    def sound_final_ratio(ratio)
      if ratio >= 100
        @sounds&.adlib(:full_marks)
      elsif ratio == 0
        @sounds&.adlib(:no_bonus)
      else
        @sounds&.adlib(:tally_done)
      end
    end

    # EVERY FIGURE AT ITS END AND THE SCORE PAID, whether they got there or a press sent them.
    def finish_count
      RATIOS.each_key { |name| @shown[name] = @ratios[name] }
      @shown_time_left = @time_left
      @shown_bonus = @bonus
      @stage = COUNT_FINISHED
      @scoring.pay(@bonus)
      @picture.changed
    end

    def paint
      @b.dma_fill_rect 0, 0, FirstPerson::ACROSS, FirstPerson::VIEW_H, colour(GROUND)
      if @no_percentages[@floor] == 1
        draw_secret_floor
      else
        draw_floor_figures
      end
    end

    def draw_floor_figures
      left = @lettering.centred(FLOOR + ("0" * @floor_digits))
      @lettering.write FLOOR, left, FLOOR_Y
      @lettering.draw_a_figure @floor_number[@floor], left + @lettering.width_of(FLOOR), FLOOR_Y, digits: @floor_digits
      @lettering.write HEADING, @lettering.centred(HEADING), COMPLETED_Y
      draw_bonus
      draw_label TIME, CLOCK_X, TIME_Y
      @lettering.draw_clock @minutes, @seconds, CLOCK_X, TIME_Y
      draw_label PAR, CLOCK_X, PAR_Y
      @lettering.draw_clock @par_seconds[@floor] / 60, @par_seconds[@floor] % 60, CLOCK_X, PAR_Y
      RATIOS.each_with_index { |(name, label), row| draw_ratio(name, label, row) }
    end

    # A figure's turn has not come until its stage has: in the original the percent sign stands
    # beside bare ground until then.
    def draw_ratio(name, label, row)
      y = RATIOS_Y + (row * LETTER)
      draw_label label, FIGURES_X, y
      @lettering.draw_a_figure @shown[name], FIGURES_X, y, digits: 3 if @stage >= COUNTING_KILLS + row
      @lettering.write "%", PERCENT_X, y
    end

    def draw_bonus
      draw_label BONUS, BONUS_X, BONUS_Y
      @lettering.draw_a_figure @shown_bonus, BONUS_X, BONUS_Y, digits: BONUS_DIGITS
    end

    def draw_label(label, figure_x, y)
      @lettering.write label, figure_x - GAP - @lettering.width_of(label), y
    end

    def draw_secret_floor
      @lettering.write SECRET_HEADING, @lettering.centred(SECRET_HEADING), FLOOR_Y
      @lettering.write "#{HEADING}!", @lettering.centred("#{HEADING}!"), COMPLETED_Y
      draw_bonus
    end

    def colour(ink) = Palette.game[ink]
  end
end
