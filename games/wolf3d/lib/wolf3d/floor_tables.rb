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
  #
  # WHAT IT ANSWERS:
  # - map_base(n), run_start(kind, n): where the +n+th floor the build holds starts in a table laid
  #   out like the map, and in a run of one kind (:doors, :pushwalls, :pieces). Plain numbers.
  # - fetch_floor_value(what, n): a number a floor has, (:doors, :pushwalls or :pieces for how
  #   many it holds, :secret_car for the cell of its secret lift or minus one): a plain number
  #   baked, a table read packed. declare_floor_value(name, what) is a variable holding the first
  #   floor's, from power-on.
  # - declare_world, declare_blocked, declare_lying_at, declare_map: the tables laid out like the
  #   map.
  # - declare_items(name, ...) { |floor| values }: a run of one kind per floor, the block naming
  #   what each item of a floor holds, which a baked build runs and a packed one reads instead.
  # - declare_piece_rule(name, ...) { |piece| value }: something about a piece that follows from
  #   which of Scenery's pieces it is (what it gives, its picture), read by the piece's number.
  # - one_floor?: whether the build holds one floor and knows its counts while building, so a walk
  #   over its things can be counted by a plain number. none?(kind): whether it knows while
  #   building that no floor has any, so it can leave out what they would need.
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

      # ...and in a run of +kind+: after every item of the floors before it.
      def run_start(kind, n) = @floors.first_of(kind, n)

      # A number floor +n+ has: the block's, where the caller works it out, else how many of +what+
      # it holds, or its secret lift's cell.
      def fetch_floor_value(what, n, &baked)
        return baked.call(n) if baked
        return @floors[n].lifts&.secret_cars&.first || -1 if what == :secret_car

        @floors.count_of(what, n)
      end

      # A variable holding the first floor's, declared on +on+ (the build, or what a saved game
      # holds).
      def declare_floor_value(name, what, on: @b, &baked) = on.var(name, fetch_floor_value(what, 0, &baked))

      # ...and the same number where the build knows it while building, which a baked one always does.
      def known_floor_value(what, n, &baked) = fetch_floor_value(what, n, &baked)

      # A table of one number for each floor the build holds, read by the floor's place in them.
      def declare_per_floor(name, width: nil, slot: nil, &value) # rubocop:disable Lint/UnusedMethodArgument
        @b.table name, @floors.map(&value), width: width
      end

      # THE ROOMS A WALL THAT MOVES STANDS BETWEEN, each pair given to the block: +pairs+, worked out
      # while building over every floor (Rooms#always_joined).
      def join_secret_wall_rooms(pairs:, this_floor: nil, &join) # rubocop:disable Lint/UnusedMethodArgument
        pairs.each { |near, far| join.call(near, far) }
      end

      def one_floor? = @floors.count == 1

      # Whether no floor the build holds has any of +kind+ (Floors#no_floor_has?).
      def none?(kind) = @floors.no_floor_has?(kind)

      # A run of items per floor, every floor's end to end; a table must hold something, so a build
      # with none gets one entry nothing reads. +slot:+ and +plus:+ are for a packed build only.
      def declare_items(name, width: nil, slot: nil, plus: nil, &values) # rubocop:disable Lint/UnusedMethodArgument
        @b.table name, Floors.at_least_one(@floors.flat_map(&values)), width: width
      end

      # Something about each piece, run over +pieces+ (every floor's, end to end) and read by the
      # piece's place in them.
      def declare_piece_rule(name, pieces:, width: nil, &rule)
        @b.table name, Floors.at_least_one(pieces.map(&rule)), width: width
      end

      # ...and about each guard, the same way.
      def declare_guard_rule(name, guards:, width: nil, &rule)
        @b.table name, Floors.at_least_one(guards.map(&rule)), width: width
      end

      # The first floor's guards a game set +difficulty+ stands up, known while building.
      def known_first_guards(difficulty) = @floors.first_floor.guards&.at(difficulty) || []

      # What lies on each cell, counted from one, laid out like the world; +cells+ answers a
      # floor's.
      def declare_lying_at(&cells) = @b.table(:lying_at, @floors.flat_map(&cells), width: :half)

      # A table laid out like the world, one number a cell; +cells+ answers a floor's.
      def declare_map(name, width: nil, &cells) = @b.table(name, @floors.flat_map(&cells), width: width)

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

      # ...and in a run of +kind+: a fixed run per floor, so at its own number times the run.
      def run_start(kind, n) = @floors[n].index * PER_FLOOR.fetch(kind)

      # Read from the pack as the game runs, since it is not known until the copy is read. The men
      # to kill are the ones the setting a game opens on stands up (Guards::DEFAULT_DIFFICULTY); a
      # floor's start counts them again at whatever setting was picked (GuardPool#refill).
      def fetch_floor_value(what, n, &baked)
        return baked.call(n) if moved_start?(what, n)

        index = @floors[n].index
        return declare(:kill_total)[(index * Guards::SETTINGS.length) + DEFAULT_SETTING] if what == :kills


        declare(FLOOR_VALUES.fetch(what))[index]
      end

      # ...so a variable holding the first floor's starts at nought and is given it at power-on:
      # this is written where the build declares it, before the game loop, which runs once.
      def declare_floor_value(name, what, on: @b, &_baked)
        held = { value: on.var(name, 0) } # a Hash, since a name holds a value
        held[:value] = fetch_floor_value(what, 0)
        held[:value]
      end

      # Not known while building, but for a first floor's start moved by WOLF3D_START, which the
      # build set itself (Floors#start_moved?).
      def known_floor_value(what, n, &baked) = moved_start?(what, n) ? baked.call(n) : nil

      # A floor's slot, read at the floor's own number in the copy: by its place in the build,
      # through a table of each place's number.
      def declare_per_floor(name, slot: name, width: nil) # rubocop:disable Lint/UnusedMethodArgument
        floor_index = (@declared ||= {})[:_floor_index] ||= @b.table(:floor_index, @floors.map(&:index), width: :byte)
        ByKind.new(@b.table(name, @pack[slot]), floor_index)
      end

      # This floor's walls that move, each the pair of rooms it stands between (push_room_a and _b),
      # given to the block as it runs; a wall with no such pair gives nought twice, which joins
      # nothing (Rooms::NOWHERE is always open).
      def join_secret_wall_rooms(this_floor:, pairs: nil, &join) # rubocop:disable Lint/UnusedMethodArgument
        near = declare(:push_room_a)
        far = declare(:push_room_b)
        @b.repeat(this_floor.pushwall_count) do |wall|
          join.call(near[this_floor.pushwall(wall)], far[this_floor.pushwall(wall)])
        end
      end

      def one_floor? = false

      # Never known before the copy is read.
      def none?(_kind) = false

      def declare_world = declare(:world)

      # Always a table: whether anything blocks is not known until the copy is read.
      def declare_blocked = declare(:blocked)

      def declare_lying_at = declare(:lying_at)

      # The slot of the same name.
      def declare_map(name, width: nil) = declare(name) # rubocop:disable Lint/UnusedMethodArgument

      # The slot +slot+ holds the run, read through +plus+ where it keeps a raw number the baked
      # table holds worked (a cell, where the table holds its middle).
      def declare_items(name, slot: name, plus: nil, width: nil) # rubocop:disable Lint/UnusedMethodArgument
        table = @b.table(name, @pack[slot])
        plus ? Plus.new(table, plus) : table
      end

      # The rule run over each of Scenery's pieces, read by which one a piece is (piece_kind).
      def declare_piece_rule(name, pieces: nil, width: nil, &rule) # rubocop:disable Lint/UnusedMethodArgument
        rules = @b.table(name, (0...Scenery::PICTURES.length).map { |kind| rule.call(Scenery.make_piece(kind)) },
                         width: width)
        ByKind.new(rules, declare(:piece_kind))
      end

      # The rule run over each kind of enemy, standing and patrolling (two entries a kind, the
      # standing one first), read by which kind a guard is and whether he patrols. A pair no floor
      # can hold (a dog standing, a boss patrolling) is nought, and never read.
      def declare_guard_rule(name, guards: nil, width: nil, &rule) # rubocop:disable Lint/UnusedMethodArgument
        values = Enemy::ALL.flat_map do |kind|
          [false, true].map { |patrolling| Guards.can_stand_up?(kind, patrolling) ? rule.call(Guards.make_guard(kind, patrolling)) : 0 }
        end
        GuardRule.new(@b.table(name, values, width: width), declare(:guard_kind), declare(:guard_patrolling))
      end

      # Not known: the pack is read after the build. The first floor is stood up from the tables.
      def known_first_guards(_difficulty) = nil

      # Where each kind's runs sit in the pack (FloorUnpacking's per-floor limits).
      PER_FLOOR = {
        doors: FloorUnpacking::DOORS_PER_FLOOR, pushwalls: FloorUnpacking::PUSHWALLS_PER_FLOOR,
        pieces: FloorUnpacking::PIECES_PER_FLOOR, guards: FloorUnpacking::GUARDS_PER_FLOOR
      }.freeze

      # The slot each number a floor has is kept in.
      FLOOR_VALUES = { doors: :door_count, pushwalls: :pushwall_count, pieces: :piece_count,
                       guards: :guard_count, secret_car: :secret_car, treasure: :treasure_total,
                       start_x: :start_x, start_y: :start_y, start_turns: :start_quarter_turns }.freeze

      # Which of the men-to-kill counts a game opening on its default setting reads.
      DEFAULT_SETTING = Guards::SETTINGS.index(Guards::DEFAULT_DIFFICULTY)

      # A table read with a number added: a cell's middle, from the cell.
      Plus = Data.define(:table, :plus) do
        def [](at) = table[at].to_f + plus
      end

      # A table of rules read by which kind an item is, from a table of the items' kinds.
      ByKind = Data.define(:rules, :kinds) do
        def [](at) = rules[kinds[at]]
      end

      # ...and a table of rules read by a guard's kind and whether he patrols.
      GuardRule = Data.define(:rules, :kinds, :patrolling) do
        def [](at) = rules[(kinds[at] * 2) + patrolling[at]]
      end

      private

      STARTS = %i[start_x start_y start_turns].freeze

      def moved_start?(what, n) = n.zero? && @floors.start_moved? && STARTS.include?(what)

      # Each slot's table, declared the first time anything asks for it.
      def declare(slot) = (@declared ||= {})[slot] ||= @b.table(slot, @pack[slot])
    end
  end
end
