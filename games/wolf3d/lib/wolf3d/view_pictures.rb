# frozen_string_literal: true

module Wolf3D
  # WHERE THE VIEW'S PICTURES COME FROM: the walls (WallAtlas) and the things standing in the rooms
  # (ThingAtlas), each one picture of 64 by 64 squares side by side, picked by column, and the gun in
  # your hands (WeaponAtlas), laid out the same way.
  #
  # A TRIMMED BUILD GIVES THEM AS COLOURS (Baked), read from VSWAP while it is built. A WHOLE BUILD
  # TAKES THEM FROM ITS DATA PACK (Packed), as places in the game's 256 colours (Palette), which
  # PictureUnpacking writes from the copy at LOAD ROM, laid out as the atlases lay them; then only
  # the unpacking reads VSWAP's pictures. The parts that draw ask for their pictures here and never
  # which kind of build they are in. A Packed one asks an atlas for its size alone.
  #
  # WHAT IT ANSWERS: declare_walls(atlas), declare_things(things), declare_thing_edges(things) (each
  # sprite's four edges as four tables, by its place in the row: a ThingAtlas::Edges of tables), and
  # declare_gun(atlas) (the gun and its first and last columns as two tables: a GunColumns).
  module ViewPictures
    # The tables of the gun's first and last columns, by frame.
    GunColumns = Data.define(:first_column, :last_column)

    # THE ROWS AS COLOURS, worked out from VSWAP while building.
    class Baked
      def initialize(build)
        @b = build
      end

      def declare_walls(atlas) = @b.image(:walls, width: atlas.width, height: atlas.height, data: atlas.pixels)

      def declare_things(things)
        @b.image :things, width: things.width, height: things.height, data: things.pixels, transparent: true
      end

      def declare_gun(atlas)
        @b.image :weapons, width: atlas.width, height: atlas.height, data: atlas.pixels, transparent: true
        GunColumns.new(first_column: @b.table(:gun_first, atlas.first_columns, width: :byte),
                       last_column: @b.table(:gun_last, atlas.last_columns, width: :byte))
      end

      def declare_thing_edges(things)
        edges = things.sprites.map { |sprite| things.edges(sprite) }
        ThingAtlas::Edges.new(first_column: @b.table(:thing_first, edges.map(&:first_column), width: :byte),
                              last_column: @b.table(:thing_last, edges.map(&:last_column), width: :byte),
                              first_row: @b.table(:thing_top, edges.map(&:first_row), width: :byte),
                              last_row: @b.table(:thing_bottom, edges.map(&:last_row), width: :byte))
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

      def declare_gun(atlas)
        @b.image :weapons, width: atlas.width, height: atlas.height, colors: Palette.game.colours,
                           places: @pack[:gun_pictures], see_through: PictureUnpacking::SEE_THROUGH
        GunColumns.new(first_column: @b.table(:gun_first, @pack[:gun_first_column]),
                       last_column: @b.table(:gun_last, @pack[:gun_last_column]))
      end

      def declare_thing_edges(_things)
        ThingAtlas::Edges.new(first_column: @b.table(:thing_first, @pack[:sprite_first_column]),
                              last_column: @b.table(:thing_last, @pack[:sprite_last_column]),
                              first_row: @b.table(:thing_top, @pack[:sprite_first_row]),
                              last_row: @b.table(:thing_bottom, @pack[:sprite_last_row]))
      end
    end
  end
end
