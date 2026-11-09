# frozen_string_literal: true

module Wolf3D
  # THE STATUS BAR'S PICTURES, MADE BY THE GAME ITSELF into the data pack (DataPack), out of the
  # pictures VgagraphUnpacking left in vga_pictures: what BarArt makes in Ruby for a trimmed build.
  # The faces, the keys and the numerals each as one row of pictures side by side; the weapons the
  # same, shrunk to the bar (BarArt#shrunk); each label cut out of the plate, widened to an even
  # width with the plate beside it; and a groove cut out of the plate's first rule. All of it in one
  # slot of pixels, bar_pictures, each piece row by row at its own place (.pieces).
  #
  # This file is game code (VBlank.require_game_file): every loop is a repeat of the routine's.
  class BarUnpacking
    # ONE PIECE OF THE SLOT: its name, where it starts, its width and height, and what it is made of:
    # +pictures+, each drawn at +width+ / their count across, or +cut+, a box [x, y] of the plate.
    Piece = Data.define(:name, :at, :width, :height, :pictures, :cut)

    # The groove's height: the bar inside the plate's edge (StatusBar#inside_height).
    RULE_HEIGHT = StatusBar::HEIGHT - BarArt::PLATE.top_edge.length - BarArt::PLATE.bottom_edge.length

    # EVERY PIECE, in order, laid out from the plate's recorded facts and Vgagraph::SIZES alone, so a
    # whole build knows each piece's place and size before any copy is read.
    def self.pieces
      art = BarArt.new(nil, plate: BarArt::PLATE)
      at = 0
      wanted = [
        [:faces, BarArt::FACES, art.face_width, art.face_height],
        [:keys, art.key_names, art.key_width, art.key_height],
        [:numerals, BarArt::NUMERALS, art.digit_width, art.digit_height],
        [:weapons, BarArt::WEAPON_PICTURES, art.weapon_width, art.weapon_height]
      ]
      strips = wanted.map do |name, pictures, width, height|
        Piece.new(name: name, at: at, width: width * pictures.length, height: height, pictures: pictures, cut: nil)
             .tap { |piece| at += piece.width * piece.height }
      end
      labels = BarArt::LABEL_FIELDS.map do |name|
        x, y, _, height = art.label_box(name)
        Piece.new(name: :"label_#{name}", at: at, width: art.label_width(name), height: height, pictures: nil, cut: [x, y])
             .tap { |piece| at += piece.width * piece.height }
      end
      rule = Piece.new(name: :rule, at: at, width: art.rule_width, height: RULE_HEIGHT, pictures: nil,
                       cut: [BarArt::RULE_COLUMNS.first, BarArt::RULE_ROWS_READ.first])
      strips + labels + [rule]
    end

    # Each piece by name, worked out when it is asked for, once FirstPerson (whose width the weapons
    # are shrunk by) has loaded. A dozen pieces of arithmetic, so it is not kept.
    def self.piece(name) = pieces.find { |piece| piece.name == name } || raise(ArgumentError, "There is no bar piece #{name}.")
    def self.places = pieces.sum { |piece| piece.width * piece.height }

    def self.declare(slots)
      slots.pixels :bar_pictures, count: places
    end

    # +b+ is the routine's builder, and +copy+, +pack+ and +release+ what `fill_from_copy` hands it.
    def initialize(b, copy, pack, release)
      @b = b
      @copy = copy
      @pack = pack
      @release = release
    end

    # Every piece; nothing at all for a release with no named pictures (Vgagraph::NAMES), whose
    # vga_pictures holds nothing to make them of.
    def fill
      return unless Vgagraph::NAMES.key?(@release) # a plain Ruby value: decided while building

      self.class.pieces.each { |piece| piece.pictures ? make_strip(piece) : cut_from_plate(piece) }
    end

    private

    PLATE_AT = VgagraphUnpacking::PICTURE_AT.fetch(:status_bar)
    PLATE_WIDTH = Vgagraph::SIZES.fetch(:status_bar).first

    # A ROW OF SAME-SIZE PICTURES side by side, each drawn at the strip's share of the width: pixel
    # x, y of picture n is the picture's own pixel x * its width / the drawn width, y likewise
    # (BarArt#strip), which for every strip but the weapons is the pixel itself.
    def make_strip(piece)
      wide = piece.width / piece.pictures.length
      own_width, own_height = Vgagraph::SIZES.fetch(piece.pictures.first)
      starts = @b.table(:"bar_#{piece.name}_from", piece.pictures.map { |name| VgagraphUnpacking::PICTURE_AT.fetch(name) },
                        width: :word)
      @b.repeat(piece.pictures.length) do |n|
        @b.repeat(piece.height) do |y|
          @b.repeat(wide) do |x|
            @pack[:bar_pictures][piece.at + (y * piece.width) + (n * wide) + x] =
              @pack[:vga_pictures][starts[n] + (((y * own_height) / piece.height) * own_width) + ((x * own_width) / wide)]
          end
          @copy.count_written wide
        end
      end
    end

    # A BOX OF THE PLATE, from its cut's corner, as BarArt#label and #rule cut it.
    def cut_from_plate(piece)
      x, y = piece.cut
      @b.repeat(piece.height) do |row|
        @b.repeat(piece.width) do |column|
          @pack[:bar_pictures][piece.at + (row * piece.width) + column] =
            @pack[:vga_pictures][PLATE_AT + ((y + row) * PLATE_WIDTH) + x + column]
        end
        @copy.count_written piece.width
      end
    end
  end
end
