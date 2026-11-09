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

    SPRITES = Holding::SPRITES

    # One row of each row of pictures: every page of the largest VSWAP side by side.
    WALL_ACROSS = WALL_PAGES * SIDE
    SPRITE_ACROSS = SPRITES * SIDE

    # THE PLACE A SPRITE IS SEE-THROUGH AT, where no post covers it. Wolfenstein keeps see-through
    # as no pixel at all, so a place has to be chosen: the last of the 256, the magenta the game's
    # tools painted see-through in, which no sprite of either release draws in (place nought, black,
    # many do).
    SEE_THROUGH = 255

    # A post is three words: where it ends and where it starts, each a row times two, with the
    # pixels' place less the start between them; a nought word ends a column (wolf4sdl: wl_draw.cpp,
    # ScaleShape). No column of 64 rows holds more posts than this.
    POST_BYTES = 6
    MOST_POSTS = SIDE / 2

    # The four edges of each sprite ThingAtlas tells the drawing (ThingAtlas#first_column and the rest).
    SPRITE_EDGES = %i[sprite_first_column sprite_last_column sprite_first_row sprite_last_row].freeze

    # The slots the pictures take, declared on +slots+ (the data pack's).
    def self.declare(slots)
      slots.numbers :wall_pictures, count: PAGE_BYTES * WALL_PAGES, width: :byte, signed: false, layout: :gba
      slots.numbers :sprite_pictures, count: PAGE_BYTES * SPRITES, width: :byte, signed: false, layout: :gba
      SPRITE_EDGES.each { |name| slots.numbers name, count: SPRITES, width: :byte, signed: false, layout: :gba }
    end

    # +b+ is the routine's builder, and +copy+, +pack+ and +release+ what `fill_from_copy` hands it.
    def initialize(b, copy, pack, release)
      @b = b
      @copy = copy
      @pack = pack
      @release = release
    end

    def fill
      @vswap = @copy.file("VSWAP.#{@release}")
      routine_var(:pages).store!(@vswap.half(0))
      routine_var(:first_sprite).store!(@vswap.half(2))
      routine_var(:first_sound).store!(@vswap.half(4))
      unpack_walls
      unpack_sprites
    end

    private

    # EVERY WALL PAGE THE COPY HAS, laid out as WallAtlas lays a whole build's row of pictures: row by
    # row across every page, so page p's pixel at x, y is at y * WALL_ACROSS + p * SIDE + x. A page is
    # kept column by column in the file (Vswap::Texture), so this is where the two orders meet. A page
    # past the copy's walls, one it leaves empty, or one whose place is not inside VSWAP, stays place
    # nought, which WallAtlas draws in the palette's first colour.
    def unpack_walls
      start = routine_var(:page_start)
      length = routine_var(:page_length)
      @b.repeat(WALL_PAGES) do |page|
        if page < routine_var(:first_sprite)
          read_page(page, start, length)
          copy_wall(page, start) if length == PAGE_BYTES && start + PAGE_BYTES <= @vswap.size
        end
      end
    end

    # EVERY SPRITE THE COPY HAS, laid out as ThingAtlas.whole lays its row, every pixel no post
    # covers SEE_THROUGH; and its four edges, left at nought for a sprite the copy lacks, as
    # ThingAtlas holds them.
    def unpack_sprites
      start = routine_var(:page_start)
      length = routine_var(:page_length)
      @b.repeat(SIDE) do |y|
        @b.repeat(SPRITE_ACROSS) { |x| @pack[:sprite_pictures][(y * SPRITE_ACROSS) + x] = SEE_THROUGH }
        @copy.count_written SPRITE_ACROSS
      end
      @b.repeat(SPRITES) do |sprite|
        if sprite < routine_var(:first_sound) - routine_var(:first_sprite)
          read_page(routine_var(:first_sprite) + sprite, start, length)
          copy_sprite(sprite, start, length) if length > 0 && start + length <= @vswap.size
        end
      end
    end

    # Where page +page+ starts in VSWAP, into +start+, and how long it is, into +length+.
    def read_page(page, start, length)
      start.store!(@vswap.word(Vswap::HEADER_BYTES + (4 * page)))
      length.store!(@vswap.half(Vswap::HEADER_BYTES + (4 * routine_var(:pages)) + (2 * page)))
    end

    # SPRITE +sprite+, its page at +start+ for +length+ bytes: the first and last columns that hold
    # anything, then a word per column between them saying where its posts start, each post's
    # pixels at the post's pixel place plus the row (wolf4sdl: wl_def.h, t_compshape; wl_draw.cpp,
    # ScaleShape). A place that would read outside the page is left alone. The rows come from the
    # posts, as ThingAtlas reads them off the pixels: the whole square for a sprite with none.
    def copy_sprite(sprite, start, length)
      left = routine_var(:left)
      left.store!(@vswap.half(start))
      @pack[:sprite_first_column][sprite] = left
      @pack[:sprite_last_column][sprite] = @vswap.half(start + 2)
      top = routine_var(:top)
      bottom = routine_var(:bottom)
      top.store!(SIDE)
      bottom.store!(0)
      @b.repeat(SIDE) do |column|
        copy_column(sprite, start, length, column) if column <= @vswap.half(start + 2) - left
      end
      top.store!(0) if top == SIDE
      bottom.store!(SIDE - 1) if bottom == 0
      @pack[:sprite_first_row][sprite] = top
      @pack[:sprite_last_row][sprite] = bottom
      @copy.count_written SPRITE_EDGES.length
    end

    # The posts of the +column+th column from the sprite's left edge.
    def copy_column(sprite, start, length, column)
      post = routine_var(:post)
      ends = routine_var(:post_end)
      pixels = routine_var(:post_pixels)
      begins = routine_var(:post_begins)
      post.store!(@vswap.half(start + 4 + (2 * column)))
      @b.repeat(MOST_POSTS, stop_when: (post + POST_BYTES > length) | (@vswap.half(start + post) == 0)) do
        ends.store!(@vswap.half(start + post) / 2)
        pixels.store!(@vswap.half(start + post + 2))
        pixels.store!(pixels - 0x10000) if pixels >= 0x8000 # a signed word
        begins.store!(@vswap.half(start + post + 4) / 2)
        routine_var(:top).store!(begins) if begins < routine_var(:top)
        routine_var(:bottom).store!(ends - 1) if ends - 1 > routine_var(:bottom)
        @b.repeat(SIDE) do |y|
          if y >= begins && y < ends && pixels + y >= 0 && pixels + y < length
            @pack[:sprite_pictures][(y * SPRITE_ACROSS) + (sprite * SIDE) + routine_var(:left) + column] =
              @vswap.byte(start + pixels + y)
            @copy.count_written 1
          end
        end
        post.store!(post + POST_BYTES)
      end
    end

    # Wall +page+, starting at +start+ in VSWAP, into its place in the row.
    def copy_wall(page, start)
      @b.repeat(SIDE) do |x|
        @b.repeat(SIDE) do |y|
          @pack[:wall_pictures][(y * WALL_ACROSS) + (page * SIDE) + x] = @vswap.byte(start + (x * SIDE) + y)
        end
        @copy.count_written SIDE
      end
    end

    # A variable of the routine's, made the first time it is asked for.
    def routine_var(name) = (@routine_vars ||= {})[name] ||= @b.var(:"_picture_unpacking_#{name}", 0)
  end
end
