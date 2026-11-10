# frozen_string_literal: true

module Wolf3D
  # WHERE THE SMALL ALPHABET'S PICTURES COME FROM (SmallLetters): every printable letter of font 0,
  # painted in one ink on one ground, for a picture has no see-through in it.
  #
  # A TRIMMED BUILD PAINTS THEM FROM VGAGRAPH (Baked) while it is built. A WHOLE BUILD TAKES THEM FROM
  # ITS DATA PACK (Packed), where SmallLetterUnpacking widened each one into small_letter_pictures.
  # SmallLetters asks for them here and never which kind of build it is in.
  #
  # WHAT IT ANSWERS: declare(ink, ground), which declares each letter as `small_letter_<code>` and
  # returns how wide each comes out, by character code, in code order.
  module SmallLetterPictures
    # EVERY LETTER IS MADE UP TO AN EVEN WIDTH, the new column blank, because a picture here can only
    # start on an even column.
    def self.even_width(width) = (width + 1) & ~1

    def self.name_of(code) = :"small_letter_#{code}"

    # THE LETTERS AS COLOURS, painted from font 0 while building.
    class Baked
      def initialize(build, art, palette)
        @b = build
        @art = art
        @palette = palette
      end

      def declare(ink, ground)
        glyphs = @art.font(SmallLetterUnpacking::FONT)
        codes = (SmallLetters::FIRST_CODE..SmallLetters::LAST_CODE).select { |code| code != " ".ord && glyphs[code.chr] }
        codes.to_h do |code|
          rows = glyphs[code.chr]
          wide = SmallLetterPictures.even_width(rows.first.length)
          @b.image SmallLetterPictures.name_of(code), width: wide, height: rows.length,
                                                      data: rows.flat_map { |row| paint_row(row, wide, ink, ground) }
          [code, wide]
        end
      end

      private

      def paint_row(row, wide, ink, ground)
        row.map { |dot| dot.zero? ? @palette[ground] : @palette[ink] } + ([@palette[ground]] * (wide - row.length))
      end
    end

    # THE LETTERS AS THE PACK HOLDS THEM, drawn through a list whose place nought is the ground and
    # every other place the ink, as Baked paints a glyph.
    class Packed
      def initialize(build, palette, pack)
        @b = build
        @palette = palette
        @pack = pack
      end

      def declare(ink, ground)
        colours = [@palette[ground]] + ([@palette[ink]] * (Palette::ENTRIES - 1))
        SmallLetterUnpacking.letters.to_h do |letter|
          places = letter.even_width * SmallLetterUnpacking::HEIGHT
          @b.image SmallLetterPictures.name_of(letter.code), width: letter.even_width, height: SmallLetterUnpacking::HEIGHT,
                                                             colors: colours,
                                                             places: @pack[:small_letter_pictures].pixels(letter.at, places)
          [letter.code, letter.even_width]
        end
      end
    end
  end
end
