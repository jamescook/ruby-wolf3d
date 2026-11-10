# frozen_string_literal: true

module Wolf3D
  # WHERE THE STATUS BAR'S PICTURES COME FROM: the rows of faces, keys, numerals and weapons, each
  # label cut out of the plate, and the groove between fields (BarArt's pictures, declared as
  # `bar_<name>`).
  #
  # A TRIMMED BUILD GIVES THEM AS COLOURS (Baked), made from VGAGRAPH while it is built. A WHOLE BUILD
  # TAKES THEM FROM ITS DATA PACK (Packed), where BarUnpacking lays each piece out in bar_pictures.
  # StatusBar asks for each here and never which kind of build it is in.
  module BarPictures
    STRIPS = %i[faces keys numerals weapons].freeze

    # THE PICTURES AS COLOURS, made from VGAGRAPH while building.
    class Baked
      def initialize(build, art)
        @b = build
        @art = art
      end

      def declare_strips
        palette = Palette.game
        @b.image :bar_faces, width: @art.faces_width, height: @art.face_height, data: @art.faces(palette)
        @b.image :bar_keys, width: @art.keys_width, height: @art.key_height, data: @art.keys(palette)
        @b.image :bar_numerals, width: @art.numerals_width, height: @art.digit_height, data: @art.numerals(palette)
        @b.image :bar_weapons, width: @art.weapons_width, height: @art.weapon_height, data: @art.weapons(palette)
        BarArt::LABEL_FIELDS.each do |name|
          cut = @art.label(name, palette)
          @b.image :"bar_label_#{name}", width: cut[:width], height: cut[:height], data: cut[:data]
        end
      end

      def declare_rule(height)
        cut = @art.rule(height, Palette.game)
        @b.image :bar_rule, width: cut[:width], height: cut[:height], data: cut[:data]
      end
    end

    # THE PICTURES AS THE PACK HOLDS THEM (BarUnpacking.pieces).
    class Packed
      def initialize(build, pack)
        @b = build
        @pack = pack
      end

      def declare_strips
        STRIPS.each { |name| declare_piece(name) }
        BarArt::LABEL_FIELDS.each { |name| declare_piece(:"label_#{name}") }
      end

      # Must be asked for the height BarUnpacking cut, which is the bar inside the plate's edge.
      def declare_rule(height)
        unless height == BarUnpacking::RULE_HEIGHT
          raise ArgumentError, "The pack's groove is #{BarUnpacking::RULE_HEIGHT} rows tall, not #{height}."
        end

        declare_piece(:rule)
      end

      private

      def declare_piece(name)
        piece = BarUnpacking.piece(name)
        @b.image :"bar_#{name}", width: piece.width, height: piece.height, colors: Palette.game.colours,
                                 places: @pack[:bar_pictures].pixels(piece.at, piece.width * piece.height)
      end
    end
  end
end
