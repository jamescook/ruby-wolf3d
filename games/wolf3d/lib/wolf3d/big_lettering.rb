# frozen_string_literal: true

module Wolf3D
  # THE GAME'S OWN BIG LETTERING, a picture sixteen pixels square for each character, which the screen
  # between floors and the death cam are written in. A release with no lettering to read is written
  # in the framework's font instead.
  class BigLettering
    LETTER = 16

    # The ten numerals as a font of their pictures, which figures are drawn in.
    NUMERALS_FONT = :tally_numerals

    # For a release with no lettering, and the ink it is written in.
    FONT = :default
    INK = 15

    # +art+ is the game's own (see MenuArt), or nil. +printed+ is every character the cartridge
    # writes, so only those pictures go on it. +figures+ says whether it also writes numbers.
    # +source+ is where the build's pictures come from (Source); the letters are menu pictures.
    def initialize(build:, art:, printed:, figures: false, source: Source::BAKED)
      @b = build
      @art = art
      @pictures = art && source.menu_pictures(build, art: art, palette: Palette.game)
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

    # A FIGURE IS NOT, so it is drawn in NUMERALS_FONT, the numerals as a font, and places the
    # number has not reached are left as bare ground: the font has no picture for a space. The
    # numerals are solid pictures of one size, so the number stands against the right of its
    # room as the original's does.
    #
    # +zeros+ writes those places as noughts, as a clock does.
    def draw_a_figure(value, x, y, digits:, zeros: false)
      return @b.draw_number(value, x, y, colour(INK), digits: digits, font: FONT) unless @art

      @b.draw_number value, x, y, digits: digits, leading_zeros: zeros, font: NUMERALS_FONT
    end

    # A TIME, as the original writes one: two places of minutes, a colon, two places of seconds.
    def draw_clock(minutes, seconds, x, y)
      draw_a_figure minutes, x, y, digits: 2, zeros: true
      write ":", x + (2 * LETTER), y
      draw_a_figure seconds, x + (3 * LETTER), y, digits: 2, zeros: true
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
        name = picture_of(char)
        @pictures.declare(name, called: name)
      end
      declare_figures if figures
    end

    # The ten numerals as a font. Must follow the pictures' own declarations, which name them.
    def declare_figures
      @b.font NUMERALS_FONT, pictures: ("0".."9").to_h { |digit| [digit, picture_of(digit)] }
    end

    # What a character's picture is called in the release. See Vgagraph.
    def picture_of(char)
      case char
      when "%" then :tally_percent
      when ":" then :tally_colon
      when "!" then :tally_exclamation
      when "'" then :tally_apostrophe
      else :"tally_#{char.downcase}"
      end
    end

    def colour(ink) = Palette.game[ink]
  end
end
