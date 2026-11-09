# frozen_string_literal: true

module Wolf3D
  # The pictures of the things that STAND in a level — the guards, and the lamps and barrels and
  # bones they stand among — laid side by side in one picture, exactly as the walls are, so that
  # which one to draw is arithmetic on a column number and never a choice made as the game runs.
  #
  # A SECOND PICTURE RATHER THAN MORE OF THE WALLS' ONE, and speed is the whole reason. These
  # pictures are mostly nothing: a guard is a man standing in a square, and everywhere he is
  # not has to let the room behind him show. A picture that CAN be see-through is asked about
  # it at every pixel it draws, and the walls are the hottest thing this game does — three
  # hundred and something columns of them a frame, every pixel of every one. Keeping them in a
  # picture that cannot be see-through means they never ask.
  class ThingAtlas
    SIDE = Vswap::Sprite::SIDE

    attr_reader :sprites

    # +sprites+ are the sprite numbers to hold, in order. A whole build (Holding) holds every one of
    # the largest VSWAP, so a sprite's place in the row is its own number whichever release is
    # loaded; one past the end of this copy's sprites holds nothing and is never drawn.
    def self.whole(vswap, palette) = new(vswap, palette, (0...Holding::SPRITES).to_a)

    def initialize(vswap, palette, sprites)
      @vswap = vswap
      @palette = palette
      @sprites = sprites
    end

    def empty? = @sprites.empty?

    # Where a picture sits in the row, counting pictures...
    def position_of(sprite) = @sprites.index(sprite)

    # ...and the same as a COLUMN number, which is what a stretched column is asked for.
    def slice_of(sprite) = position_of(sprite) * SIDE

    def width = [@sprites.length, 1].max * SIDE
    def height = SIDE

    # Column-major in the file, and a picture here is row-major, so this is the one place the
    # two orders meet — the same crossing the walls make, over a sprite's see-through pixels.
    def pixels
      return Array.new(SIDE * SIDE, :transparent) if empty?

      rows = Array.new(SIDE) { [] }
      @sprites.each do |index|
        unless in_copy?(index)
          SIDE.times { |y| rows[y].concat([:transparent] * SIDE) }
          next
        end

        sprite = @vswap.sprite(index)
        SIDE.times do |y|
          SIDE.times do |x|
            value = sprite[x, y]
            rows[y] << (value.nil? ? :transparent : @palette[value])
          end
        end
      end
      rows.flatten
    end

    # WHICH COLUMNS OF A PICTURE HOLD ANYTHING. A guard fills about a third of the width of
    # his square and the rest is room showing through, so the strips either side of him are
    # work with nothing to show for it — and worse than nothing, because a strip that draws
    # no pixel still says it covered that part of the screen, which would rub out anything
    # standing behind it.
    #
    # Both numbers count from the LEFT EDGE of the picture, which is what the drawing walks.
    #
    # A sprite this copy does not have is held as nothing: both edges at nought.
    def first_column(sprite) = edges(sprite).first_column
    def last_column(sprite) = edges(sprite).last_column

    # ...AND WHICH ROWS, which is the same question down the other axis and matters for a
    # different reason. A great many of these things sit on the FLOOR — a clip of ammunition
    # fills the bottom sixth of its square and nothing else — and a square is always drawn
    # centred on the eye line. So the nearer you get to a clip the further its picture slides
    # off the bottom of the screen, and there is a distance at which every pixel of it is past
    # the bottom edge while the drawing still walks the whole square looking for it.
    def first_row(sprite) = edges(sprite).first_row
    def last_row(sprite) = edges(sprite).last_row

    # ALL FOUR AT ONCE, for whatever lays them out as tables (ViewPictures, PictureUnpacking's tests).
    Edges = Data.define(:first_column, :last_column, :first_row, :last_row)
    NO_EDGES = Edges.new(first_column: 0, last_column: 0, first_row: 0, last_row: 0)

    def edges(sprite)
      return NO_EDGES unless in_copy?(sprite)

      picture = @vswap.sprite(sprite)
      Edges.new(first_column: picture.first_column, last_column: picture.last_column,
                first_row: picture.first_row, last_row: picture.last_row)
    end

    private

    def in_copy?(sprite) = @vswap.sprite?(sprite)
  end
end
