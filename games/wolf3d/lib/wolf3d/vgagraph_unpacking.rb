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

    # The slots VGAGRAPH takes, declared on +slots+ (the data pack's).
    def self.declare(slots)
      slots.numbers :picture_count, count: 1, width: :half, signed: false, layout: :gba
      slots.numbers :picture_sizes, count: PICTURES * 2, width: :half, signed: false, layout: :gba
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
    end

    private

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
