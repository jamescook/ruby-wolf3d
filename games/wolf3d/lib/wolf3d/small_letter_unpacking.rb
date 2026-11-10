# frozen_string_literal: true

module Wolf3D
  # THE SMALL ALPHABET AS SMALLLETTERS DRAWS IT, MADE BY THE GAME ITSELF into the data pack
  # (DataPack), out of the characters of font 0 VgagraphUnpacking left in font_glyphs: each printable
  # one widened to an even width, the new column place nought, as SmallLetterPictures makes it in Ruby for a
  # trimmed build. All of them in one slot of pixels, small_letter_pictures, each row by row at its
  # own place (.letters).
  #
  # This file is game code (VBlank.require_game_file): every loop is a repeat of the routine's.
  class SmallLetterUnpacking
    FONT = 0
    HEIGHT = Vgagraph::FONT_HEIGHTS.fetch(FONT)

    # ONE LETTER OF THE SLOT: its character code, where it starts, its own width and the even width
    # it is drawn at.
    Letter = Data.define(:code, :at, :width, :even_width)

    # EVERY LETTER SmallLetters draws, in code order, from Vgagraph::FONT_WIDTHS alone, so a whole
    # build knows each one's place and size before any copy is read.
    def self.letters
      at = 0
      drawn = Vgagraph::FONT_WIDTHS.fetch(FONT).select { |code, _| code.between?(SmallLetters::FIRST_CODE + 1, SmallLetters::LAST_CODE) }
      drawn.map do |code, width|
        even = SmallLetterPictures.even_width(width)
        Letter.new(code: code, at: at, width: width, even_width: even).tap { at += even * HEIGHT }
      end
    end

    def self.places = letters.sum { |letter| letter.even_width * HEIGHT }

    def self.declare(slots)
      slots.pixels :small_letter_pictures, count: places
    end

    # +b+ is the routine's builder, and +copy+, +pack+ and +release+ what `fill_from_copy` hands it.
    def initialize(b, copy, pack, release)
      @b = b
      @copy = copy
      @pack = pack
      @release = release
    end

    # EVERY LETTER, one loop over a table of them: pixel x, y of a letter is its glyph's own where x
    # is inside the glyph's width, and place nought in the column that makes the width even.
    def fill
      letters = self.class.letters
      from = @b.table(:small_letter_from, letters.map { |letter| VgagraphUnpacking::GLYPH_AT.fetch(FONT).fetch(letter.code) },
                      width: :word)
      to = @b.table(:small_letter_to, letters.map(&:at), width: :word)
      widths = @b.table(:small_letter_own_width, letters.map(&:width), width: :byte)
      evens = @b.table(:small_letter_even_width, letters.map(&:even_width), width: :byte)
      @b.repeat(letters.length) do |n|
        @b.repeat(HEIGHT) do |y|
          @b.repeat(widths[n]) do |x|
            @pack[:small_letter_pictures][to[n] + (y * evens[n]) + x] = @pack[:font_glyphs][from[n] + (y * widths[n]) + x]
          end
          @pack[:small_letter_pictures][to[n] + (y * evens[n]) + evens[n] - 1] = 0 if widths[n] < evens[n]
          @copy.count_written evens[n]
        end
      end
    end
  end
end
