# frozen_string_literal: true

module Wolf3D
  # VGAGRAPH, UNPACKED BY THE GAME ITSELF into the data pack (DataPack): what Vgagraph reads in Ruby
  # for MenuArt, BarArt and the lettering.
  #
  # Three files work together (Vgagraph says how): VGAHEAD lists where each chunk starts, three
  # bytes a place; VGAGRAPH holds the chunks, each its unpacked length in four bytes and then
  # Huffman bits; VGADICT is the tree those bits walk (wolf4sdl: id_ca.cpp, CAL_HuffExpand and
  # CA_CacheGrChunk; IdSoftware::Codec::Huffman). The tree is in a file of its own, so the walk is
  # written here, reading both files, rather than as a format, which reads the one file its block
  # comes from.
  #
  # This file is game code (VBlank.require_game_file): an `if` on a number the routine reads is a
  # branch in it, and every count is a variable of the routine's (#routine_var).
  class VgagraphUnpacking
    PICTURES = Holding::VGA_PICTURES
    LENGTH_BYTES = Vgagraph::LENGTH_BYTES
    OFFSET_BYTES = Vgagraph::OFFSET_BYTES
    ABSENT = Vgagraph::ABSENT

    # The tree's root, the last of its 255 nodes; a node is two branches of two bytes each, and a
    # branch below 256 is a byte made, above it another node, 256 on.
    ROOT = IdSoftware::Codec::Huffman::ROOT
    NODES = IdSoftware::Codec::Huffman::NODE_COUNT
    NODE_BYTES = 4
    LEAVES = 256

    # The most packed bytes one chunk can take: the largest VGAGRAPH there is (the shareware's).
    MOST_PACKED = 330_000

    PLANES = Vgagraph::PLANES

    # WHERE EACH NAMED PICTURE STARTS in the slot of them, one after another in Vgagraph::SIZES'
    # order, each row by row at its own size; and how many places they take in all.
    NAMED_PLACES = Vgagraph::SIZES.values.sum { |width, height| width * height }
    PICTURE_AT = Ractor.make_shareable(
      Vgagraph::SIZES.keys.zip(Vgagraph::SIZES.values.map { |width, height| width * height }
                                              .each_with_object([0]) { |places, starts| starts << (starts.last + places) })
                     .to_h
    )

    # The slots VGAGRAPH takes, declared on +slots+ (the data pack's).
    def self.declare(slots)
      slots.numbers :picture_count, count: 1, width: :half, signed: false, layout: :gba
      slots.numbers :picture_sizes, count: PICTURES * 2, width: :half, signed: false, layout: :gba
      slots.pixels :vga_pictures, count: NAMED_PLACES
    end

    # +b+ is the routine's builder, and +copy+, +pack+ and +release+ what `fill_from_copy` hands it.
    def initialize(b, copy, pack, release)
      @b = b
      @copy = copy
      @pack = pack
      @release = release
    end

    def fill
      @head = @copy.file("VGAHEAD.#{@release}")
      @graph = @copy.file("VGAGRAPH.#{@release}")
      @dictionary = @copy.file("VGADICT.#{@release}")
      unpack_picture_table
      unpack_named_pictures
    end

    private

    # EVERY PICTURE THIS GAME DRAWS BY NAME, at its place in the slot (PICTURE_AT), by the number
    # this release keeps it under (Vgagraph::NAMES; a release with no names gives none). A picture is
    # four quarter-width pictures one after another, the display's four planes, so column x of the
    # whole is column x / 4 of plane x % 4 (wolf4sdl: id_vh.cpp, VWB_DrawPic; Vgagraph::Picture). A
    # picture the release's table gives another size is left at place nought.
    #
    # One walk, over tables of each picture's number, place and size, so the Huffman walk is written
    # into the routine once rather than once a picture.
    def unpack_named_pictures
      names = Vgagraph::NAMES.fetch(@release, {})
      return if names.empty? # a plain Ruby value: decided while building

      numbers = @b.table(:vga_named_number, names.values, width: :half)
      starts = @b.table(:vga_named_at, names.keys.map { |name| PICTURE_AT.fetch(name) }, width: :word)
      widths = @b.table(:vga_named_width, names.keys.map { |name| Vgagraph::SIZES.fetch(name).first }, width: :half)
      heights = @b.table(:vga_named_height, names.keys.map { |name| Vgagraph::SIZES.fetch(name).last }, width: :half)
      number = routine_var(:number)
      @b.repeat(names.length) do |n|
        number.store!(numbers[n])
        routine_var(:at).store!(starts[n])
        routine_var(:width).store!(widths[n])
        routine_var(:height).store!(heights[n])
        if (@pack[:picture_sizes][2 * number] == routine_var(:width)) &
           (@pack[:picture_sizes][(2 * number) + 1] == routine_var(:height))
          unpack_picture(Vgagraph::FIRST_PICTURE + number)
        end
      end
    end

    # The picture in chunk +chunk+, routine_var(:width) by routine_var(:height), into the slot from
    # routine_var(:at).
    def unpack_picture(chunk)
      width = routine_var(:width)
      quarter = routine_var(:quarter)
      plane_places = routine_var(:plane_places)
      quarter.store!(width / PLANES)
      plane_places.store!(quarter * routine_var(:height))
      unpack_chunk(chunk) do |byte, made|
        if made < width * routine_var(:height)
          @pack[:vga_pictures][routine_var(:at) + (((made % plane_places) / quarter) * width) +
                               ((made % quarter) * PLANES) + (made / plane_places)] = byte
          @copy.count_written 1
        end
      end
    end

    # THE PICTURE TABLE, chunk nought: a width and a height for each picture, two bytes each, so
    # the release's count of pictures is a quarter of its length. One past PICTURES is not kept.
    def unpack_picture_table
      low = routine_var(:low)
      @pack[:picture_count][0] = 0
      unpack_chunk(Vgagraph::PICTURE_TABLE) do |byte, at|
        if (at & 1) == 0
          low.store!(byte)
        elsif (at >> 1) < PICTURES * 2
          @pack[:picture_sizes][at >> 1] = low | (byte << 8)
          @copy.count_written 2
        end
      end
      count = routine_var(:pictures)
      count.store!(routine_var(:chunk_length) >> 2)
      count.store!(PICTURES) if count > PICTURES
      @pack[:picture_count][0] = count
    end

    # CHUNK +n+, each byte it unpacks to handed to the block with its place counted from nought. A
    # chunk never made, or one whose start or packed bits are not inside VGAGRAPH, gives nothing;
    # its length (#routine_var :chunk_length) is then nought.
    def unpack_chunk(n)
      start = routine_var(:chunk_start)
      length = routine_var(:chunk_length)
      at = routine_var(:packed_at)
      made = routine_var(:made)
      node = routine_var(:node)
      bits = routine_var(:bits)
      branch = routine_var(:branch)
      start.store!(@head.byte(OFFSET_BYTES * n) | (@head.byte((OFFSET_BYTES * n) + 1) << 8) |
                   (@head.byte((OFFSET_BYTES * n) + 2) << 16))
      length.store!(0)
      length.store!(@graph.word(start)) if start != ABSENT && start + LENGTH_BYTES <= @graph.size
      at.store!(start + LENGTH_BYTES)
      made.store!(0)
      node.store!(ROOT)
      @b.repeat(MOST_PACKED, stop_when: (made >= length) | (at >= @graph.size)) do
        bits.store!(@graph.byte(at))
        @b.repeat(8) do |bit|
          if made < length
            branch.store!(@dictionary.half((NODE_BYTES * node) + (2 * ((bits >> bit) & 1))))
            if branch < LEAVES
              yield branch, made
              made.increase!(1)
              node.store!(ROOT)
            elsif branch - LEAVES < NODES
              node.store!(branch - LEAVES)
            else
              # A branch to no node of the tree's 255 would read past VGADICT: the chunk ends here.
              length.store!(made)
            end
          end
        end
        at.increase!(1)
      end
      length.store!(made)
    end

    # A variable of the routine's, made the first time it is asked for.
    def routine_var(name) = (@routine_vars ||= {})[name] ||= @b.var(:"_vgagraph_unpacking_#{name}", 0)
  end
end
