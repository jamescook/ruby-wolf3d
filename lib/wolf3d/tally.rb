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
  # THE TWO FLOORS AT THE END OF AN EPISODE ARE DIFFERENT. A map from the ninth on has no
  # percentages at all. It says the floor is done and hands over a flat fifteen thousand. The
  # original words that for the secret floor, because it is the only one of the two with a lift:
  # the boss floor is left by walking out, which is Victory's business.
  #
  # IT IS WRITTEN IN THE GAME'S OWN BIG LETTERING, a picture sixteen pixels square for each
  # character. Those were laid out for a screen eighty pixels wider, so the wording is cut to fit:
  # the original's "treasure ratio" alone would take fourteen of the fifteen letters across, with
  # nowhere to put its figure. Saying RATIO three times is what goes.
  #
  # WHAT THIS LEAVES OUT of the original's screen: the time taken and the par time beside it, with
  # the bonus they earn; the figures counting up from nothing, and the sounds that go with them;
  # the music; and BJ breathing at the side, who is as wide as a third of this screen. All of that
  # sits on top of these rules.
  #
  # THE SCORE IS PAID WHEN THE SCREEN APPEARS, which the original does when its figures finish
  # counting. With nothing counting up the two moments are the same one to a player.
  #
  # NOTHING SAYS TO PRESS A BUTTON, as nothing does in the original. See Menus: there is no "press
  # start" anywhere in Wolfenstein.
  class Tally
    # The ground, the original's VIEWCOLOR out of its 256 (wl_menu.h), which the lettering's own
    # pictures are painted on. The ink is for a release with no lettering to read.
    GROUND = 0x7f
    INK = 15

    # PERCENT100AMT, and what a floor with no percentages hands over instead.
    FOR_A_HUNDRED_PER_CENT = 10_000
    FOR_A_SECRET_FLOOR = 15_000

    # A MAP NUMBERED FROM THIS ONE ON HAS NO PERCENTAGES: the test is `mapon < 8` in the original,
    # counting from nought within an episode.
    NO_PERCENTAGES_FROM = 8

    RATIOS = { kill: "KILL", secret: "SECRET", treasure: "TREASURE" }.freeze
    HEADING = "COMPLETED"
    FLOOR = "FLOOR "
    SECRET_HEADING = "SECRET FLOOR"
    BONUS = "BONUS"

    # Every character on this screen, so only those pictures go on the cartridge.
    PRINTED = Ractor.make_shareable(
      (RATIOS.values + [HEADING, FLOOR, SECRET_HEADING, BONUS, "!%", "0123456789"]).join.delete(" ").chars.uniq
    )

    # EVERY POSITION IS EVEN, because a picture on this screen has to start on an even column.
    LETTER = 16
    FLOOR_Y = 4
    COMPLETED_Y = FLOOR_Y + LETTER
    BONUS_Y = 44
    RATIOS_Y = 68

    # Three digits and a percent sign, ending where the bonus's five digits end, with each label
    # stopping short of its figure.
    PERCENT_X = 200
    FIGURES_X = PERCENT_X - (3 * LETTER)
    BONUS_X = PERCENT_X + LETTER - (5 * LETTER)
    GAP = 8

    # The framework's own lettering, for a release whose pictures we cannot name.
    FONT = :default

    # +totals+ is what the floor held, as :kill, :secret and :treasure. +floor+ is which floor is
    # being played, and +secret_lift+ says which lever called the lift, for the playthrough.
    # +lettering+ is the game's own art (see MenuArt), or nil to write in the framework's font.
    def initialize(build:, player:, totals:, floors:, floor:, playthrough:, secret_lift:, lettering: nil)
      @b = build
      @player = player
      @floors = floors
      @floor = floor
      @playthrough = playthrough
      @secret_lift = secret_lift
      @art = lettering
      @found = { kill: [player.kills, totals.fetch(:kill)],
                 secret: [player.secrets, totals.fetch(:secret)],
                 treasure: [player.treasures, totals.fetch(:treasure)] }
      declare
    end

    # 1 while this screen is up, which is what stops the world.
    attr_reader :showing

    # THE LIFT HAS ARRIVED: work the floor out, pay for it and put the screen up.
    def floor_finished = @b.call(:tally_the_floor)

    # ONE PASS WITH THE SCREEN UP. A or B goes on to the next floor, and it takes a NEW press, so
    # the finger already on the trigger as the lift arrived does not skip the screen unread.
    def wait_for_a_press = @b.call(:tally_waits)

    # The picture, which is painted as the floor ends and then left alone.
    def draw = @picture.draw

    private

    # NONE OF THESE IS IN A SAVED GAME, which is what the underscores say. The game cannot be saved
    # with this screen up, because the menu cannot be opened over it.
    def declare
      @showing = @b.var :_tally_showing, 0
      @bonus = @b.var :_tally_bonus, 0
      @ratios = RATIOS.keys.to_h { |name| [name, @b.var(:"_#{name}_ratio", 0)] }
      numbers = @floors.map { |floor| map_of(floor) + 1 }
      @floor_digits = numbers.max.to_s.length
      @floor_number = @b.table :tally_floor_number, numbers, width: :byte
      @no_percentages = @b.table :tally_no_percentages, @floors.map { |floor| percentages?(floor) ? 0 : 1 },
                                 width: :byte
      declare_the_lettering if @art
      @picture = @b.keep_showing(:tally_picture) { paint }
      @b.func(:tally_the_floor, fast: false) { tally_the_floor }
      @b.func(:tally_waits, fast: false) { wait }
    end

    # Which map of its episode a floor is. A release not divided into tens has no last two floors
    # to treat differently, so every one of its floors is an ordinary one.
    def map_of(floor) = @floors.episodes_of_ten? ? floor.index % Floors::PER_EPISODE : floor.index
    def percentages?(floor) = !@floors.episodes_of_ten? || map_of(floor) < NO_PERCENTAGES_FROM

    def tally_the_floor
      if @no_percentages[@floor] == 1
        @bonus = FOR_A_SECRET_FLOOR
      else
        @bonus = 0
        @found.each do |name, (found, total)|
          @ratios[name] = 0
          @ratios[name] = found * 100 / total if total > 0
          @bonus += FOR_A_HUNDRED_PER_CENT if @ratios[name] >= 100
        end
      end
      @player.score += @bonus
      # The original takes your keys before this screen, so the bar is already empty on it.
      @player.keys = 0
      @showing = 1
      @picture.changed
    end

    def wait
      if @b.pressed(:a) || @b.pressed(:b)
        @showing = 0
        @playthrough.start(:next_floor, secret: @secret_lift)
      end
    end

    def paint
      @b.dma_fill_rect 0, 0, FirstPerson::ACROSS, FirstPerson::VIEW_H, colour(GROUND)
      if @no_percentages[@floor] == 1
        draw_a_secret_floor
      else
        draw_the_percentages
      end
    end

    def draw_the_percentages
      left = centred(FLOOR + ("0" * @floor_digits))
      write FLOOR, left, FLOOR_Y
      draw_a_figure @floor_number[@floor], left + width_of(FLOOR), FLOOR_Y, digits: @floor_digits
      write HEADING, centred(HEADING), COMPLETED_Y
      draw_the_bonus
      RATIOS.each_with_index { |(name, label), row| draw_a_percentage(name, label, RATIOS_Y + (row * LETTER)) }
    end

    def draw_a_percentage(name, label, y)
      write label, FIGURES_X - GAP - width_of(label), y
      draw_a_figure @ratios[name], FIGURES_X, y, digits: 3
      write "%", PERCENT_X, y
    end

    def draw_the_bonus
      write BONUS, BONUS_X - GAP - width_of(BONUS), BONUS_Y
      draw_a_figure @bonus, BONUS_X, BONUS_Y, digits: 5
    end

    def draw_a_secret_floor
      write SECRET_HEADING, centred(SECRET_HEADING), FLOOR_Y
      write "#{HEADING}!", centred("#{HEADING}!"), COMPLETED_Y
      draw_the_bonus
    end

    # --- THE LETTERING -------------------------------------------------------------------------

    def declare_the_lettering
      PRINTED.each do |char|
        cut = @art.picture(picture_of(char), Palette.game)
        @b.image picture_of(char), width: cut[:width], height: cut[:height], data: cut[:data]
      end
      @numeral = @b.var :_tally_numeral, 0
      @half_x = @b.var :_tally_half_x, 0
      @row = @b.var :_tally_row, 0
      @b.func(:tally_numeral, fast: false) { draw_a_numeral }
    end

    # What a character's picture is called in the release. See Vgagraph.
    def picture_of(char)
      case char
      when "%" then :tally_percent
      when "!" then :tally_exclamation
      else :"tally_#{char.downcase}"
      end
    end

    # WORDS ARE KNOWN WHILE THE CARTRIDGE IS BUILT, so each letter is one picture drawn at one
    # place. A space takes a letter's room, as it does in the original.
    def write(words, x, y)
      words.each_char do |char|
        unless char == " "
          if @art
            @b.blit picture_of(char), x, y
          else
            @b.draw_text char, x, y, colour(INK), font: FONT
          end
        end
        x += width_of(char)
      end
    end

    # A FIGURE IS NOT, so each place works out its digit as the game runs, and places the number
    # has not reached are left as bare ground. The numerals are solid pictures of one size, so the
    # number stands against the right of its room as the original's does.
    def draw_a_figure(value, x, y, digits:)
      return @b.draw_number(value, x, y, colour(INK), digits: digits, font: FONT) unless @art

      digits.times do |i|
        place = 10**(digits - 1 - i)
        if place == 1 || value >= place
          @numeral = (value / place) % 10
          # HALF THE COLUMN, DOUBLED: the framework draws a picture only where it can prove the
          # column is even, and twice anything is.
          @half_x = (x + (i * LETTER)) / 2
          @row = y
          @b.call :tally_numeral
        end
      end
    end

    # TEN PICTURES UNDER TEN TESTS, once, and every digit place calls it.
    def draw_a_numeral
      10.times { |digit| @b.blit :"tally_#{digit}", @half_x * 2, @row if @numeral == digit }
    end

    def width_of(words)
      words.each_char.sum { |char| char == " " || @art.nil? ? LETTER : @art.width(picture_of(char)) }
    end

    # Where a line of words starts to sit in the middle of the screen, on an even column.
    def centred(words)
      x = (FirstPerson::ACROSS - width_of(words)) / 2
      x - (x % 2)
    end

    def colour(ink) = Palette.game[ink]
  end
end
