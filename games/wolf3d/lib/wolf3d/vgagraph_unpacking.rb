# frozen_string_literal: true

module Wolf3D
  # VGAGRAPH, UNPACKED BY THE GAME ITSELF into the data pack (DataPack): what Vgagraph reads in Ruby
  # for MenuArt, BarArt, the lettering and the end of each episode.
  #
  # Three files work together (Vgagraph says how): VGAHEAD lists where each chunk starts, three
  # bytes a place; VGAGRAPH holds the chunks, each its unpacked length in four bytes and then
  # Huffman bits; VGADICT is the tree those bits walk (wolf4sdl: id_ca.cpp, CAL_HuffExpand and
  # CA_CacheGrChunk; IdSoftware::Codec::Huffman). The tree is in a file of its own, so the walk is
  # written here, reading both files, rather than as a format, which reads the one file its block
  # comes from.
  #
  # ONE WALK FOR EVERY CHUNK. The routine is game code, so a walk written out once per chunk is
  # that many copies of it in the routine. Instead the chunks this pack wants are a table
  # (#chunk_jobs) and one walk runs in a loop over it, each byte going where its kind of chunk says.
  #
  # This file is game code (VBlank.require_game_file): an `if` on a number the routine reads is a
  # branch in it, and a number one method sets and another reads, or a loop changes, is one of
  # its game_variables.
  class VgagraphUnpacking
    # The Huffman walk through one chunk (#unpack_chunk; wolf4sdl: id_ca.cpp, CAL_HuffExpand): where
    # the chunk starts in VGAGRAPH and how many bytes it unpacks to, the next packed byte and how
    # many bytes it has made, the node of the tree it stands at, the packed byte being read a bit at
    # a time, and the branch that bit takes.
    game_variables :chunk_start, :chunk_length, :packed_at, :made, :node, :bits, :branch
    # Putting a chunk's bytes in place: a picture's quarter width and the places in each of its four
    # planes (#unpack_job, #put_picture_byte), and the low byte of a size in the picture table, kept
    # until its high byte comes (#put_size_byte).
    game_variables :quarter, :plane_places, :low
    # Making a picture shorter (#shorten_screen): the smallest gap found so far and its row, the
    # next kept row below the one taken out and the kept row above that, and how many rows have been
    # written out.
    game_variables :best, :best_row, :below, :above, :written
    # #row_gap's running sum.
    game_variables :gap_sum

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

    # WHAT EACH CHUNK IN THE TABLE IS, which says where its bytes go.
    PICTURE_TABLE = 0
    PICTURE = 1
    FONT = 2
    ARTICLE = 3

    # WHERE EACH NAMED PICTURE STARTS in the slot of them, one after another in Vgagraph::SIZES'
    # order, each row by row at its own size; and how many places they take in all.
    NAMED_PLACES = Vgagraph::SIZES.values.sum { |width, height| width * height }
    PICTURE_AT = Ractor.make_shareable(
      Vgagraph::SIZES.keys.zip(Vgagraph::SIZES.values.map { |width, height| width * height }
                                              .each_with_object([0]) { |places, starts| starts << (starts.last + places) })
                     .to_h
    )

    # A FONT AS ITS CHUNK KEEPS IT (Vgagraph::Font): its height, where each of 256 characters starts,
    # each one's width, then the lettering. Kept whole first, one after the other, so each character
    # can then be cut out into a picture of its own; the chunk is the size the widths make it.
    FONT_HEIGHT_BYTES = Vgagraph::Font::HEIGHT_BYTES
    FONT_WIDTHS_AT = FONT_HEIGHT_BYTES + (Vgagraph::Font::CHARACTERS * Vgagraph::Font::LOCATION_BYTES)
    FONT_CHUNK_BYTES = Ractor.make_shareable(
      Vgagraph::FONT_WIDTHS.each_with_index.map do |widths, n|
        Vgagraph::Font::HEADER_BYTES + (widths.values.sum * Vgagraph::FONT_HEIGHTS.fetch(n))
      end
    )
    FONT_CHUNK_AT = Ractor.make_shareable([0, FONT_CHUNK_BYTES.first])

    # EACH CHARACTER AS A PICTURE, row by row at its own width, font 0's then font 1's, in the order
    # of Vgagraph::FONT_WIDTHS: where each starts, by font and code.
    def self.glyph_starts
      total = 0
      Vgagraph::FONT_WIDTHS.each_with_index.map do |widths, n|
        widths.to_h do |code, width|
          at = total
          total += width * Vgagraph::FONT_HEIGHTS.fetch(n)
          [code, at]
        end
      end
    end
    GLYPH_AT = Ractor.make_shareable(glyph_starts)
    GLYPH_PLACES = Vgagraph::FONT_WIDTHS.each_with_index.sum do |widths, n|
      widths.values.sum * Vgagraph::FONT_HEIGHTS.fetch(n)
    end

    # THE END OF EACH EPISODE, the words as the release keeps them (wl_text.cpp reads its own markup
    # out of them as it shows them), in a run of this many bytes each: the longest of either release
    # is 822.
    ARTICLES = 6
    ARTICLE_BYTES = 1024

    # THE TWO PICTURES PAINTED FOR A BIGGER SCREEN (MenuArt::FULL_SCREEN), each made MenuArt::DOWN
    # rows tall by the routine as MenuArt#keep makes it while building, one after the other.
    SCREENS = MenuArt::FULL_SCREEN
    SCREEN_ROWS = MenuArt::DOWN
    SCREEN_AT = Ractor.make_shareable(
      SCREENS.each_with_index.to_h { |name, n| [name, n * Vgagraph::SIZES.fetch(name).first * SCREEN_ROWS] }
    )

    # HOW LIGHT EACH OF THE GAME'S COLOURS IS, as MenuArt#brightness_of works it out.
    LIGHT = Ractor.make_shareable(MenuArt.brightness_of(Palette.game))

    # The slots VGAGRAPH takes, declared on +slots+ (the data pack's).
    def self.declare(slots)
      slots.numbers :picture_count, count: 1, width: :half, signed: false
      slots.numbers :picture_sizes, count: PICTURES * 2, width: :half, signed: false
      slots.pixels :vga_pictures, count: NAMED_PLACES
      slots.numbers :font_chunks, count: FONT_CHUNK_BYTES.sum, width: :byte, signed: false
      slots.pixels :font_glyphs, count: GLYPH_PLACES
      slots.numbers :end_articles, count: ARTICLES * ARTICLE_BYTES, width: :byte, signed: false
      slots.numbers :end_article_length, count: ARTICLES, width: :half, signed: false
      slots.pixels :screen_pictures, count: SCREENS.sum { |name| Vgagraph::SIZES.fetch(name).first * SCREEN_ROWS }
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
      @job = Job.new(0, 0, 0, 0, 0, 0)
      @chunk_start = 0
      @chunk_length = 0
      @packed_at = 0
      @made = 0
      @node = 0
      @bits = 0
      @branch = 0

      @quarter = 0
      @plane_places = 0
      @low = 0

      @best = 0
      @best_row = 0
      @below = 0
      @above = 0
      @written = 0

      @gap_sum = 0
      unpack_chunks
      cut_glyphs
      SCREENS.each { |name| shorten_screen(name) }
    end

    private

    # THE PICTURE +name+ MADE SCREEN_ROWS TALL, out of vga_pictures into screen_pictures, by
    # MenuArt#keep's rule: take the row least different from the one above it (the gap added along
    # the whole width, by LIGHT), the first such row on a tie, never the top row, one at a time and
    # asking again after each, until SCREEN_ROWS are left. A taken row is marked rather than moved
    # out of a list, so "the row above" is the nearest row above still kept.
    def shorten_screen(name)
      width, height = Vgagraph::SIZES.fetch(name)
      from = PICTURE_AT.fetch(name)
      light = @b.table(:"#{name}_light", LIGHT, width: :byte)
      kept = @b.list(:"_#{name}_kept", capacity: height)
      gaps = @b.list(:"_#{name}_gap", capacity: height)
      @b.repeat(height) do
        kept << 1
        gaps << 0
      end
      @b.repeat(height - 1) { |row| gaps[row + 1] = row_gap(from, width, light, row + 1, row) }
      @b.repeat(height - SCREEN_ROWS) do
        @best = -1
        @best_row = 0
        @b.repeat(height - 1) do |row|
          if kept[row + 1] == 1 && (@best < 0 || gaps[row + 1] < @best)
            @best = gaps[row + 1]
            @best_row = row + 1
          end
        end
        kept[@best_row] = 0
        # The next kept row below now has a new row above it.
        @below = -1
        @b.repeat(height - 1) do |row|
          @below = row + 1 if @below < 0 && row + 1 > @best_row && kept[row + 1] == 1
        end
        if @below >= 0
          @above = 0
          @b.repeat(height) { |row| @above = row if row < @below && kept[row] == 1 }
          gaps[@below] = row_gap(from, width, light, @below, @above)
        end
      end
      @written = 0
      @b.repeat(height) do |row|
        if kept[row] == 1
          @b.repeat(width) do |x|
            @pack[:screen_pictures][SCREEN_AT.fetch(name) + (@written * width) + x] =
              @pack[:vga_pictures][from + (row * width) + x]
          end
          @copy.count_written width
          @written += 1
        end
      end
    end

    # How different rows +a+ and +b+ of the picture at +from+ are, added along its +width+.
    def row_gap(from, width, light, a, b)
      @gap_sum = 0
      @b.repeat(width) do |x|
        difference = light[@pack[:vga_pictures][from + (a * width) + x]] - light[@pack[:vga_pictures][from + (b * width) + x]]
        difference = 0 - difference if difference < 0
        @gap_sum += difference
      end
      @gap_sum
    end

    # ONE ROW OF THE TABLE OF CHUNKS: which chunk, what kind, where its bytes start in their slot,
    # its width and height (a picture's) or how many bytes it may take (a font's, an article's), and
    # its number among its kind (a picture's in the release, a font's, an episode's).
    ChunkJob = Data.define(:chunk, :kind, :at, :width, :height, :number)

    # ...and the one being unpacked, as the routine's variables.
    Job = Struct.new(:chunk, :kind, :at, :width, :height, :number) do
      game_variables :chunk, :kind, :at, :width, :height, :number
    end

    # The chunks this release's pack wants, the picture table first, since a picture is checked
    # against it. A release with no names (Vgagraph::NAMES) has no pictures here.
    def chunk_jobs
      jobs = [ChunkJob.new(chunk: Vgagraph::PICTURE_TABLE, kind: PICTURE_TABLE, at: 0, width: 0, height: 0, number: 0)]
      Vgagraph::NAMES.fetch(@release, {}).each do |name, number|
        width, height = Vgagraph::SIZES.fetch(name)
        jobs << ChunkJob.new(chunk: Vgagraph::FIRST_PICTURE + number, kind: PICTURE, at: PICTURE_AT.fetch(name),
                             width: width, height: height, number: number)
      end
      Vgagraph::FONTS.times do |n|
        jobs << ChunkJob.new(chunk: Vgagraph::FIRST_FONT + n, kind: FONT, at: FONT_CHUNK_AT.fetch(n),
                             width: FONT_CHUNK_BYTES.fetch(n), height: 0, number: n)
      end
      Vgagraph::END_ARTICLES.fetch(@release, 0).times do |episode|
        jobs << ChunkJob.new(chunk: Vgagraph::FIRST_END_ARTICLE.fetch(@release) + episode, kind: ARTICLE,
                             at: episode * ARTICLE_BYTES, width: ARTICLE_BYTES, height: 0, number: episode)
      end
      jobs
    end

    # EVERY CHUNK OF THE TABLE, through the one walk. A picture the release's table gives another
    # size than Vgagraph::SIZES is not unpacked, and stays place nought.
    def unpack_chunks
      jobs = chunk_jobs
      # The table as one column for each field of ChunkJob, read into @job's field of that name.
      columns = ChunkJob.members.to_h do |field|
        [field, @b.table(:"vga_job_#{field}", jobs.map { |job| job.to_h.fetch(field) }, width: :word)]
      end
      @pack[:picture_count][0] = 0
      @b.repeat(jobs.length) do |n|
        @job.chunk = columns[:chunk][n]
        @job.kind = columns[:kind][n]
        @job.at = columns[:at][n]
        @job.width = columns[:width][n]
        @job.height = columns[:height][n]
        @job.number = columns[:number][n]
        wanted = true
        if @job.kind == PICTURE
          wanted = (@pack[:picture_sizes][2 * @job.number] == @job.width) &&
                   (@pack[:picture_sizes][(2 * @job.number) + 1] == @job.height)
        end
        unpack_job if wanted
      end
    end

    # The chunk @job names, each byte to its place.
    def unpack_job
      @quarter = @job.width / PLANES
      @plane_places = @quarter * @job.height
      unpack_chunk(@job.chunk) do |byte, made|
        if @job.kind == PICTURE_TABLE
          put_size_byte(byte, made)
        elsif @job.kind == PICTURE
          put_picture_byte(byte, made)
        elsif made < @job.width # a font's or an article's run
          if @job.kind == FONT
            @pack[:font_chunks][@job.at + made] = byte
          else
            @pack[:end_articles][@job.at + made] = byte
          end
          @copy.count_written 1
        end
      end
      finish_job
    end

    # A byte of the picture table: a width and a height for each picture, two bytes each.
    def put_size_byte(byte, made)
      if (made & 1) == 0
        @low = byte
      elsif (made >> 1) < PICTURES * 2
        @pack[:picture_sizes][made >> 1] = @low | (byte << 8)
        @copy.count_written 2
      end
    end

    # A byte of a picture, kept as four quarter-width pictures one after another, the display's four
    # planes, so column x of the whole is column x / 4 of plane x % 4 (wolf4sdl: id_vh.cpp,
    # VWB_DrawPic; Vgagraph::Picture).
    def put_picture_byte(byte, made)
      if made < @job.width * @job.height
        @pack[:vga_pictures][@job.at + (((made % @plane_places) / @quarter) * @job.width) +
                             ((made % @quarter) * PLANES) + (made / @plane_places)] = byte
        @copy.count_written 1
      end
    end

    # What a chunk leaves once it is walked: the release's count of pictures, a quarter of the
    # table's length and no more than PICTURES; an article's length, no more than its run.
    def finish_job
      if @job.kind == PICTURE_TABLE
        count = @chunk_length >> 2
        count = PICTURES if count > PICTURES
        @pack[:picture_count][0] = count
      elsif @job.kind == ARTICLE
        @chunk_length = ARTICLE_BYTES if @chunk_length > ARTICLE_BYTES
        @pack[:end_article_length][@job.number] = @chunk_length
      end
    end

    # EACH CHARACTER OF BOTH FONTS CUT OUT OF ITS CHUNK into a picture of its own (GLYPH_AT), where
    # the chunk says it starts. A font of another height than Vgagraph::FONT_HEIGHTS, a character of
    # another width than FONT_WIDTHS, or one whose pixels would run past its chunk, stays place
    # nought.
    def cut_glyphs
      Vgagraph::FONT_WIDTHS.each_with_index do |widths, n|
        font_at = FONT_CHUNK_AT.fetch(n)
        height = Vgagraph::FONT_HEIGHTS.fetch(n)
        codes = @b.table(:"font_#{n}_code", widths.keys, width: :half)
        sizes = @b.table(:"font_#{n}_width", widths.values, width: :byte)
        starts = @b.table(:"font_#{n}_glyph_at", widths.keys.map { |code| GLYPH_AT.fetch(n).fetch(code) }, width: :word)
        tall = font_byte(font_at) | (font_byte(font_at + 1) << 8)
        @b.repeat(widths.length) do |g|
          code = codes[g]
          location = font_byte(font_at + FONT_HEIGHT_BYTES + (2 * code)) |
                     (font_byte(font_at + FONT_HEIGHT_BYTES + (2 * code) + 1) << 8)
          if (tall == height) && (font_byte(font_at + FONT_WIDTHS_AT + code) == sizes[g]) &&
             (location + (sizes[g] * height) <= FONT_CHUNK_BYTES.fetch(n))
            @b.repeat(sizes[g] * height) do |pixel|
              @pack[:font_glyphs][starts[g] + pixel] = font_byte(font_at + location + pixel)
              @copy.count_written 1
            end
          end
        end
      end
    end

    def font_byte(at) = @pack[:font_chunks][at]

    # CHUNK +n+, each byte it unpacks to handed to the block with its place counted from nought. A
    # chunk VGAHEAD does not list, one never made, or one whose start or packed bits are not inside
    # VGAGRAPH, gives nothing; its length (@chunk_length) is then nought.
    def unpack_chunk(n)
      @chunk_start = ABSENT
      if (OFFSET_BYTES * n) + OFFSET_BYTES <= @head.size
        @chunk_start = @head.byte(OFFSET_BYTES * n) | (@head.byte((OFFSET_BYTES * n) + 1) << 8) |
                       (@head.byte((OFFSET_BYTES * n) + 2) << 16)
      end
      @chunk_length = 0
      @chunk_length = @graph.word(@chunk_start) if @chunk_start != ABSENT && @chunk_start + LENGTH_BYTES <= @graph.size
      @packed_at = @chunk_start + LENGTH_BYTES
      @made = 0
      @node = ROOT
      @b.repeat(MOST_PACKED, stop_when: (@made >= @chunk_length) || (@packed_at >= @graph.size)) do
        @bits = @graph.byte(@packed_at)
        @b.repeat(8) do |bit|
          if @made < @chunk_length
            @branch = @dictionary.half((NODE_BYTES * @node) + (2 * ((@bits >> bit) & 1)))
            if @branch < LEAVES
              yield @branch, @made
              @made += 1
              @node = ROOT
            elsif @branch - LEAVES < NODES
              @node = @branch - LEAVES
            else
              # A branch to no node of the tree's 255 would read past VGADICT: the chunk ends here.
              @chunk_length = @made
            end
          end
        end
        @packed_at += 1
      end
      @chunk_length = @made
    end
  end
end
