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
    # as no pixel at all, so a place has to be chosen: the last of the 256, which no sprite of either
    # release draws in (test_floor_unpacking.rb holds the copies to that), where place nought, black,
    # is drawn in by many.
    SEE_THROUGH = 255

    # A post is three words: where it ends and where it starts, each a row times two, with the
    # pixels' place less the start between them; a nought word ends a column (wolf4sdl: wl_draw.cpp,
    # ScaleShape). No column of 64 rows holds more posts than this.
    POST_BYTES = 6
    MOST_POSTS = SIDE / 2

    # A sprite's header before its column table: its first and last columns, a word each.
    HEADER_BYTES = 4

    # The slot holding each of a sprite's four edges (ThingAtlas::Edges).
    SPRITE_EDGES = { first_column: :sprite_first_column, last_column: :sprite_last_column,
                     first_row: :sprite_first_row, last_row: :sprite_last_row }.freeze

    # THE GUN IN YOUR HANDS is the last WeaponAtlas::COUNT sprites of whichever release is loaded, so
    # where it starts differs between releases (Spear, which Holding is sized for, has 421 sprites to
    # the others' 436). A picture drawn from a pack takes one run of places, and the gun's frames are
    # not one run of the sprites' row, which is laid out row by row across every sprite; so the gun
    # gets a row of its own, as WeaponAtlas lays it, copied out of the sprites' row, with its first
    # and last columns.
    GUNS = WeaponAtlas::COUNT
    GUN_ACROSS = GUNS * SIDE

    # The slots the pictures take, declared on +slots+ (the data pack's).
    def self.declare(slots)
      slots.pixels :wall_pictures, count: PAGE_BYTES * WALL_PAGES
      slots.pixels :sprite_pictures, count: PAGE_BYTES * SPRITES
      SPRITE_EDGES.each_value { |name| slots.numbers name, count: SPRITES, width: :byte, signed: false }
      slots.pixels :gun_pictures, count: PAGE_BYTES * GUNS
      %i[gun_first_column gun_last_column].each do |name|
        slots.numbers name, count: GUNS, width: :byte, signed: false
      end
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
      unpack_gun
    end

    private

    # THE GUN'S ROW, out of the sprites' row: the release's last GUNS sprites, the knife's first
    # frame first (WeaponAtlas.first_sprite). A release with fewer sprites than that has no gun, and
    # its row stays nought: the palette's first colour, not see-through, so a square of it would
    # show. Every release Vanilla accepts has one.
    def unpack_gun
      first = routine_var(:first_gun)
      first.store!(routine_var(:first_sound) - routine_var(:first_sprite) - GUNS)
      has_gun = routine_var(:has_gun)
      has_gun.store!(0)
      has_gun.store!(1) if first >= 0
      @b.repeat(GUNS) do |frame|
        if has_gun == 1
          @pack[:gun_first_column][frame] = @pack[:sprite_first_column][first + frame]
          @pack[:gun_last_column][frame] = @pack[:sprite_last_column][first + frame]
          @b.repeat(SIDE) do |y|
            @b.repeat(SIDE) do |x|
              @pack[:gun_pictures][(y * GUN_ACROSS) + (frame * SIDE) + x] =
                @pack[:sprite_pictures][(y * SPRITE_ACROSS) + ((first + frame) * SIDE) + x]
            end
            @copy.count_written SIDE
          end
        end
      end
    end

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
    # ScaleShape).
    #
    # Must read nothing outside the page: a header whose columns are not inside the square, or whose
    # column table runs past the page, gives a sprite left see-through with edges of nought; a post
    # or a pixel whose place is outside the page is left alone. The rows are the ones a pixel was
    # written in, as ThingAtlas reads them off the pixels: the whole square for a sprite with none.
    def copy_sprite(sprite, start, length)
      left = routine_var(:left)
      right = routine_var(:right)
      left.store!(0)
      right.store!(-1)
      if length >= HEADER_BYTES
        left.store!(@vswap.half(start))
        right.store!(@vswap.half(start + 2))
      end
      if left <= right && right < SIDE && HEADER_BYTES + (2 * (right - left + 1)) <= length
        @pack[:sprite_first_column][sprite] = left
        @pack[:sprite_last_column][sprite] = right
        top = routine_var(:top)
        bottom = routine_var(:bottom)
        top.store!(SIDE)
        bottom.store!(-1)
        @b.repeat(SIDE) do |column|
          copy_column(sprite, start, length, column) if column <= right - left
        end
        if bottom < 0
          top.store!(0)
          bottom.store!(SIDE - 1)
        end
        @pack[:sprite_first_row][sprite] = top
        @pack[:sprite_last_row][sprite] = bottom
        @copy.count_written SPRITE_EDGES.length
      end
    end

    # The posts of the +column+th column from the sprite's left edge, each read only once it is known
    # to lie inside the page.
    def copy_column(sprite, start, length, column)
      post = routine_var(:post)
      ended = routine_var(:posts_ended)
      ends = routine_var(:post_end)
      pixels = routine_var(:post_pixels)
      begins = routine_var(:post_begins)
      post.store!(@vswap.half(start + HEADER_BYTES + (2 * column)))
      ended.store!(0)
      @b.repeat(MOST_POSTS, stop_when: ended == 1) do
        if post + POST_BYTES > length
          ended.store!(1)
        elsif @vswap.half(start + post) == 0
          ended.store!(1)
        else
          ends.store!(@vswap.half(start + post) / 2)
          pixels.store!(@vswap.half(start + post + 2))
          pixels.store!(pixels - 0x10000) if pixels >= 0x8000 # a signed word
          begins.store!(@vswap.half(start + post + 4) / 2)
          copy_post(sprite, start, length, column)
          post.store!(post + POST_BYTES)
        end
      end
    end

    # One post's pixels, rows from post_begins up to post_end, into the sprite's square.
    def copy_post(sprite, start, length, column)
      pixels = routine_var(:post_pixels)
      @b.repeat(SIDE) do |y|
        if y >= routine_var(:post_begins) && y < routine_var(:post_end) && pixels + y >= 0 && pixels + y < length
          @pack[:sprite_pictures][(y * SPRITE_ACROSS) + (sprite * SIDE) + routine_var(:left) + column] =
            @vswap.byte(start + pixels + y)
          routine_var(:top).store!(y) if y < routine_var(:top)
          routine_var(:bottom).store!(y) if y > routine_var(:bottom)
          @copy.count_written 1
        end
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
