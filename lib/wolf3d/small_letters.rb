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

    # +ground+ is the colour behind the letters, for a picture has no see-through in it.
    def initialize(build:, art:, palette:, ink:, ground:)
      @b = build
      @art = art
      @palette = palette
      @ink = ink
      @ground = ground
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
      glyphs = @art.font(0)
      @pictured = (FIRST_CODE..LAST_CODE).map(&:chr).select { |char| char != " " && glyphs[char] }
      @widths = @pictured.to_h { |char| [char.ord, even_width(glyphs[char])] }
      @pictured.each do |char|
        rows = glyphs[char]
        @b.image picture_name(char), width: width_of(char), height: rows.length,
                                     data: rows.flat_map { |row| painted(row, width_of(char)) }
      end
      @width_table = @b.table :small_letter_width, (0..LAST_CODE).map { |code| @widths[code] || BLANK_WIDTH }, width: :byte
      @code = @b.var :_small_letter_code, 0
      @half_x = @b.var :_small_letter_half_x, 0
      @y = @b.var :_small_letter_y, 0
      @b.func(:draw_small_letter, fast: false) do
        @pictured.each { |char| @b.blit picture_name(char), @half_x * 2, @y if @code == char.ord }
      end
    end

    def even_width(rows) = (rows.first.length + 1) & ~1

    def painted(row, wide)
      ground = @palette[@ground]
      row.map { |ink| ink.zero? ? ground : @palette[@ink] } + ([ground] * (wide - row.length))
    end

    def picture_name(char) = :"small_letter_#{char.ord}"
  end
end
