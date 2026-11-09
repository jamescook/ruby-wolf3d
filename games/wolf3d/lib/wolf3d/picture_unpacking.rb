# frozen_string_literal: true

module Wolf3D
  # THE PICTURES OF VSWAP, UNPACKED BY THE GAME ITSELF into the data pack (DataPack): the rows of
  # pictures WallAtlas and ThingAtlas lay out in Ruby for a whole build, as places in the game's 256
  # colours (Palette), which are not in the copy.
  #
  # VSWAP's header is a page count, the first sprite's page and the first sound's, then a start (four
  # bytes) and a length (two) for every page (wolf4sdl: id_pm.cpp, PM_Startup; Wolf3D::Vswap reads
  # the same). The walls are the pages before the first sprite.
  #
  # This file is game code (VBlank.require_game_file): an `if` on a number the routine reads is a
  # branch in it, and every count is a variable of the routine's (#routine_var).
  class PictureUnpacking
    SIDE = Vswap::Texture::SIDE
    PAGE_BYTES = Vswap::Texture::BYTES
    WALL_PAGES = Holding::WALL_PAGES

    # One row of the walls' row of pictures: every page of the largest VSWAP side by side.
    WALL_ACROSS = WALL_PAGES * SIDE

    # The slots the pictures take, declared on +slots+ (the data pack's).
    def self.declare(slots)
      slots.numbers :wall_pictures, count: PAGE_BYTES * WALL_PAGES, width: :byte, signed: false, layout: :gba
    end

    # +b+ is the routine's builder, and +copy+, +pack+ and +release+ what `fill_from_copy` hands it.
    def initialize(b, copy, pack, release)
      @b = b
      @copy = copy
      @pack = pack
      @release = release
    end

    def fill
      unpack_walls
    end

    private

    # EVERY WALL PAGE THE COPY HAS, laid out as WallAtlas lays a whole build's row of pictures: row by
    # row across every page, so page p's pixel at x, y is at y * WALL_ACROSS + p * SIDE + x. A page is
    # kept column by column in the file (Vswap::Texture), so this is where the two orders meet. A page
    # past the copy's walls, one it leaves empty, or one whose place is not inside VSWAP, stays place
    # nought, which WallAtlas draws in the palette's first colour.
    def unpack_walls
      vswap = @copy.file("VSWAP.#{@release}")
      pages = routine_var(:pages)
      first_sprite = routine_var(:first_sprite)
      start = routine_var(:page_start)
      length = routine_var(:page_length)
      pages.store!(vswap.half(0))
      first_sprite.store!(vswap.half(2))
      @b.repeat(WALL_PAGES) do |page|
        if page < first_sprite
          start.store!(vswap.word(Vswap::HEADER_BYTES + (4 * page)))
          length.store!(vswap.half(Vswap::HEADER_BYTES + (4 * pages) + (2 * page)))
          copy_wall(vswap, page, start) if length == PAGE_BYTES && start + PAGE_BYTES <= vswap.size
        end
      end
    end

    # Wall +page+, starting at +start+ in VSWAP, into its place in the row.
    def copy_wall(vswap, page, start)
      @b.repeat(SIDE) do |x|
        @b.repeat(SIDE) do |y|
          @pack[:wall_pictures][(y * WALL_ACROSS) + (page * SIDE) + x] = vswap.byte(start + (x * SIDE) + y)
        end
        @copy.count_written SIDE
      end
    end

    # A variable of the routine's, made the first time it is asked for.
    def routine_var(name) = (@routine_vars ||= {})[name] ||= @b.var(:"_picture_unpacking_#{name}", 0)
  end
end
