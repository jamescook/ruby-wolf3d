# frozen_string_literal: true

module Wolf3D
  # WHERE THE MENUS' PICTURES COME FROM: the title, the credits, the rating box, the plates over the
  # menus, the gun, the difficulty portraits (MenuArt's pictures, each declared as `menu_<name>`).
  #
  # A TRIMMED BUILD GIVES THEM AS COLOURS (Baked), read from VGAGRAPH and shortened while it is
  # built. A WHOLE BUILD TAKES THEM FROM ITS DATA PACK (Packed), as places in the game's 256 colours:
  # VgagraphUnpacking writes every named picture into vga_pictures and the two shortened screens into
  # screen_pictures. Menus asks for each picture here and never which kind of build it is in.
  module MenuPictures
    def self.for(build:, art:, palette:, pack: nil)
      pack ? Packed.new(build, art, pack) : Baked.new(build, art, palette)
    end

    # THE PICTURES AS COLOURS, worked out from VGAGRAPH while building.
    class Baked
      def initialize(build, art, palette)
        @b = build
        @art = art
        @palette = palette
      end

      def declare(name)
        cut = @art.picture(name, @palette)
        @b.image :"menu_#{name}", width: cut[:width], height: cut[:height], data: cut[:data]
      end
    end

    # THE PICTURES AS THE PACK HOLDS THEM, at the sizes MenuArt gives.
    class Packed
      def initialize(build, art, pack)
        @b = build
        @art = art
        @pack = pack
      end

      def declare(name)
        width, height = @art.size(name)
        places = if MenuArt::FULL_SCREEN.include?(name)
                   @pack[:screen_pictures].pixels(VgagraphUnpacking::SCREEN_AT.fetch(name), width * height)
                 else
                   @pack[:vga_pictures].pixels(VgagraphUnpacking::PICTURE_AT.fetch(name), width * height)
                 end
        @b.image :"menu_#{name}", width: width, height: height, colors: Palette.game.colours, places: places
      end
    end
  end
end
