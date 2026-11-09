# frozen_string_literal: true

module Wolf3D
  # WHERE THE VIEW'S TWO ROWS OF PICTURES COME FROM: the walls (WallAtlas) and the things standing
  # in the rooms (ThingAtlas), each one picture of 64 by 64 squares side by side, picked by column.
  #
  # A TRIMMED BUILD GIVES THEM AS COLOURS (Baked), read from VSWAP while it is built. A WHOLE BUILD
  # TAKES THEM FROM ITS DATA PACK (Packed), as places in the game's 256 colours (Palette), which
  # PictureUnpacking writes from the copy at LOAD ROM, laid out as the atlases lay them; then only
  # the unpacking reads VSWAP. The parts that draw ask for their pictures here and never which kind
  # of build they are in.
  #
  # WHAT IT ANSWERS: declare_walls(atlas), declare_things(things), and declare_thing_edges(things),
  # each sprite's four edges (ThingAtlas#first_column and the rest) as four tables, by its place in
  # the row.
  module ViewPictures
    def self.for(build:, pack: nil) = pack ? Packed.new(build, pack) : Baked.new(build)

    # The four tables of a sprite's edges, by name, and the ThingAtlas edge each holds.
    EDGES = { thing_first: :first_column, thing_last: :last_column, thing_top: :first_row,
              thing_bottom: :last_row }.freeze

    # THE ROWS AS COLOURS, worked out from VSWAP while building.
    class Baked
      def initialize(build)
        @b = build
      end

      def declare_walls(atlas) = @b.image(:walls, width: atlas.width, height: atlas.height, data: atlas.pixels)

      def declare_things(things)
        @b.image :things, width: things.width, height: things.height, data: things.pixels, transparent: true
      end

      def declare_thing_edges(things)
        EDGES.to_h do |name, edge|
          values = things.sprites.map do |sprite|
            case edge
            when :first_column then things.first_column(sprite)
            when :last_column then things.last_column(sprite)
            when :first_row then things.first_row(sprite)
            when :last_row then things.last_row(sprite)
            end
          end
          [name, @b.table(name, values, width: :byte)]
        end
      end
    end

    # THE ROWS AS THE PACK HOLDS THEM: every page and every sprite of the largest VSWAP, so a
    # picture's place in the row is its own number, as WallAtlas and ThingAtlas lay a whole build's.
    class Packed
      def initialize(build, pack)
        @b = build
        @pack = pack
      end

      def declare_walls(atlas)
        @b.image :walls, width: atlas.width, height: atlas.height, colors: Palette.game.colours,
                         places: @pack[:wall_pictures]
      end

      def declare_things(things)
        @b.image :things, width: things.width, height: things.height, colors: Palette.game.colours,
                          places: @pack[:sprite_pictures], see_through: PictureUnpacking::SEE_THROUGH
      end

      def declare_thing_edges(_things)
        EDGES.to_h { |name, edge| [name, @b.table(name, @pack[:"sprite_#{edge}"])] }
      end
    end
  end
end
