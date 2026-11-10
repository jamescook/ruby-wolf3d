# frozen_string_literal: true

module Wolf3D
  # THE SMALL ALPHABET AS PICTURES, for words nobody knows while the cartridge is built: a name somebody
  # typed, a score. The framework's words are painted into the code, so these are drawn a letter at a
  # time at a place worked out as the game runs. Every letter is made up to an even width, because a
  # picture here can only start on an even column.
  class SmallLetters
    # A BLANK IS AS WIDE AS A THIN LETTER.
    BLANK_WIDTH = 6
    FIRST_CODE = 32
    LAST_CODE = 126

    # +ground+ is the colour behind the letters, for a picture has no see-through in it. +source+ is
    # where the build's pictures come from (Source).
    def initialize(build:, art:, palette:, ink:, ground:, source: Source::BAKED)
      @b = build
      @ink = ink
      @ground = ground
      @pictures = source.small_letter_pictures(build, art: art, palette: palette)
      declare
    end

    # How wide a character comes out, while the cartridge is built.
    def width_of(char) = @widths[char.ord] || BLANK_WIDTH

    # Start a line at +x+ and +y+, which may be worked out as the game runs. +x+ must be even.
    def start_at(x, y)
      @half_x = x / 2
      @y = y
    end

    # One character by its code, and the place moves on past it.
    def draw(code)
      @code = code
      @b.call :draw_small_letter
      @half_x += @width_table[@code] / 2
    end

    # The place moves on by +pixels+, which must be even, with nothing drawn.
    def skip(pixels)
      @half_x += pixels / 2
    end

    # ...or by the width of the character +code+.
    def skip_past(code)
      @half_x += @width_table[code] / 2
    end

    # Where the place has got to, for a cursor.
    def x = @half_x * 2

    private

    def declare
      @widths = @pictures.declare(@ink, @ground)
      @width_table = @b.table :small_letter_width, (0..LAST_CODE).map { |code| @widths[code] || BLANK_WIDTH }, width: :byte
      @code = @b.var :_small_letter_code, 0
      @half_x = @b.var :_small_letter_half_x, 0
      @y = @b.var :_small_letter_y, 0
      @b.func(:draw_small_letter, fast: false) do
        @widths.each_key { |code| @b.blit SmallLetterPictures.name_of(code), @half_x * 2, @y if @code == code }
      end
    end
  end
end
