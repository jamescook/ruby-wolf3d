# frozen_string_literal: true

module Wolf3D
  # WHERE WOLFENSTEIN'S TWO PROPORTIONAL ALPHABETS COME FROM (Menus): font 0, the menus' lettering,
  # and font 1, their headings, each declared as a font of the framework's under a name.
  #
  # A TRIMMED BUILD READS THEM OFF VGAGRAPH (Baked) while it is built. A WHOLE BUILD TAKES THEM FROM
  # ITS DATA PACK (Packed): each letter a run of font_glyphs, where VgagraphUnpacking cut it out, at
  # the widths and height Vgagraph gives. Menus asks for them here and never which kind of build it
  # is in.
  #
  # WHAT IT ANSWERS: declare(name, font).
  module Alphabets
    # THE LETTERS AS VGAGRAPH HOLDS THEM, read while building.
    class Baked
      def initialize(build, art)
        @b = build
        @art = art
      end

      def declare(name, font) = @b.font(name, glyphs: @art.font(font))
    end

    # THE LETTERS AS THE PACK HOLDS THEM.
    class Packed
      def initialize(build, pack)
        @b = build
        @pack = pack
      end

      def declare(name, font)
        @b.font name, glyphs: glyphs(font), height: Vgagraph::FONT_HEIGHTS.fetch(font)
      end

      private

      # The letters Vgagraph::Font#glyphs hands over, the printable ones, each as its pixels in the pack.
      def glyphs(font)
        height = Vgagraph::FONT_HEIGHTS.fetch(font)
        Vgagraph::FONT_WIDTHS.fetch(font)
                             .select { |code, width| width.positive? && Vgagraph::Font::PRINTABLE.cover?(code) }
                             .to_h do |code, width|
          [code.chr, @pack[:font_glyphs].pixels(VgagraphUnpacking::GLYPH_AT.fetch(font).fetch(code), width * height)]
        end
      end
    end
  end
end
