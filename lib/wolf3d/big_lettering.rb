# frozen_string_literal: true

module Wolf3D
  # THE GAME'S OWN BIG LETTERING, a picture sixteen pixels square for each character, which the screen
  # between floors and the death cam are written in. A release with no lettering to read is written
  # in the framework's font instead.
  class BigLettering
    LETTER = 16

    # For a release with no lettering, and the ink it is written in.
    FONT = :default
    INK = 15

    # +art+ is the game's own (see MenuArt), or nil. +printed+ is every character the cartridge
    # writes, so only those pictures go on it. +figures+ says whether it also writes numbers.
    def initialize(build:, art:, printed:, figures: false)
      @b = build
      @art = art
      declare(printed, figures) if art
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

    def width_of(words)
      words.each_char.sum { |char| char == " " || @art.nil? ? LETTER : @art.width(picture_of(char)) }
    end

    # Where a line of words starts to sit in the middle of the screen, on an even column.
    def centred(words)
      x = (FirstPerson::ACROSS - width_of(words)) / 2
      x - (x % 2)
    end

    private

    def declare(printed, figures)
      printed.each do |char|
        cut = @art.picture(picture_of(char), Palette.game)
        @b.image picture_of(char), width: cut[:width], height: cut[:height], data: cut[:data]
      end
      declare_the_figures if figures
    end

    def declare_the_figures
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
      when "'" then :tally_apostrophe
      else :"tally_#{char.downcase}"
      end
    end

    # TEN PICTURES UNDER TEN TESTS, once, and every digit place calls it.
    def draw_a_numeral
      10.times { |digit| @b.blit :"tally_#{digit}", @half_x * 2, @row if @numeral == digit }
    end

    def colour(ink) = Palette.game[ink]
  end
end
