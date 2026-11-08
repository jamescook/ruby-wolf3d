# frozen_string_literal: true

module Wolf3D
  # WHERE A BUILD'S PER-FLOOR TABLES COME FROM, one source for every part of the game that reads
  # one, and two ways to fill it.
  #
  # A TRIMMED BUILD BAKES THEM (Baked): the Ruby readers work each floor out while the cartridge is
  # built, and the tables hold just the floors it carries, end to end. A WHOLE BUILD READS THEM FROM
  # ITS DATA PACK (Packed): FloorUnpacking works every floor out as game code, at LOAD ROM in a shell
  # or as an all-in-one build is made, into slots sized for the original's sixty floors (Holding),
  # each floor at its own number in the copy.
  #
  # A part of the game declares a table by what it holds and gets one either way, holding the same
  # numbers for the same floor, and asks where floor n's run starts; it never asks which kind of
  # build it is in. A table nothing on any floor needs may come back nil, which only a baked build
  # can know: a pack is filled after the build, so its tables are always there.
  module FloorTables
    # The source a build reads: from +pack+ (the data pack's handle) where it has one, else baked
    # from +floors+, every floor the build holds. +wall_picture+ answers where a wall code's lit
    # picture sits in the row of pictures, counting from one (FirstPerson#wall_picture); a baked
    # world is made with it.
    def self.for(build:, floors:, wall_picture:, pack: nil)
      pack ? Packed.new(build, floors, pack) : Baked.new(build, floors, wall_picture)
    end

    # THE TABLES WORKED OUT IN RUBY, as a trimmed build has always held them.
    class Baked
      def initialize(build, floors, wall_picture)
        @b = build
        @floors = floors
        @wall_picture = wall_picture
      end

      # Where the +n+th floor the build holds starts in a table laid out like the map: the floors
      # it holds, end to end.
      def map_base(n) = @floors.map_base(n)

      # WHAT EACH CELL OF EACH FLOOR SAYS TO THE WALK, every floor end to end (ThisFloor, where the
      # table is read, says what the numbers mean).
      def declare_world
        @b.table :world, @floors.flat_map { |floor|
          floor.level.each_cell.map { |x, y| encode_cell(floor, x, y) }
        }
      end

      # WHICH CELLS HOLD SOMETHING A FOOT CANNOT PASS, laid out like the world, or nil for a build
      # with nothing in the way anywhere, which then pays nothing for a table. A floor whose
      # scenery all lets you through contributes its own run of noughts rather than being left
      # out, because the floors after it are found by counting cells.
      def declare_blocked
        return nil if @floors.none? { |floor| floor.scenery && !floor.scenery.empty? }

        cells = @floors.flat_map do |floor|
          floor.level.each_cell.map { |x, y| floor.scenery&.blocks?(x, y) ? 1 : 0 }
        end
        return nil if cells.none?(1)

        @b.table :blocked, cells, width: :byte
      end

      private

      # WHAT ONE CELL OF THE WORLD SAYS.
      #
      # EVERY NUMBER IN IT IS LOCAL TO ITS OWN FLOOR — door three of this floor, not door
      # ninety-one of the cartridge — because what it names is state the game keeps while playing
      # that floor, and only one floor is ever being played. The tables of things settled while
      # building hold every floor end to end and are reached by adding where this floor's slice
      # starts; the two must not be confused, and keeping the map local is what stops them being.
      def encode_cell(floor, x, y)
        level = floor.level
        number = floor.doors.number_at(x, y)
        return ThisFloor::DOOR + number - 1 if number

        pushing = floor.pushwalls.number_at(x, y)
        return ThisFloor::PUSH + pushing - 1 if pushing

        # A lever, before the plain-wall test below, which would otherwise claim it: a lever IS a
        # wall, and the only thing that makes it more than one is that using it ends the floor.
        lever = floor.lifts&.number_at(x, y)
        return ThisFloor::LIFT + lever - 1 if lever

        return 0 unless level.solid?(x, y)

        @wall_picture.call(level.wall_code(x, y)) || 0
      end
    end

    # THE TABLES AS FLOORUNPACKING LEFT THEM IN THE DATA PACK, each read from its slot as the game
    # powers on, every floor of the copy at its own number.
    class Packed
      def initialize(build, floors, pack)
        @b = build
        @floors = floors
        @pack = pack
      end

      # Where the +n+th floor the build holds starts in a table laid out like the map: at its own
      # number in the copy, since the pack holds every floor and a build dialled to some of them
      # holds a few from the middle.
      def map_base(n) = @floors[n].index * FloorUnpacking::CELLS

      def declare_world = declare(:world)

      # Always a table: whether anything blocks is not known until the copy is read.
      def declare_blocked = declare(:blocked)

      private

      def declare(slot) = @b.table(slot, @pack[slot])
    end
  end
end
