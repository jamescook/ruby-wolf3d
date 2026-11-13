# frozen_string_literal: true

module Wolf3D
  # THE FLOORS, UNPACKED BY THE GAME ITSELF, at a shell's LOAD ROM or as a whole build is made: what
  # Maps, Doors, Pushwalls, Elevator and ThisFloor work out in Ruby while a trimmed build is made,
  # done as game code into the data pack (Holding says which builds these are).
  #
  # EVERY SLOT IS SIZED FOR SIXTY FLOORS whichever release is loaded, and the release's own count is
  # a number in the pack, so the shareware's ten floors and the six episodes' sixty fill one shape.
  #
  # This file is game code (VBlank.require_game_file): a `while` or an `if` on a number the routine
  # reads is a loop or a branch in it, and a number one method sets and another reads, or a loop
  # changes, is one of its game_variables.
  class FloorUnpacking
    # Reading the floors' planes (#unpack_planes): how many floors are unpacked, and whether the next
    # one's header or planes lie outside GAMEMAPS, which ends the floors there.
    game_variables :floors, :outside
    # Counting what one floor's walk joins (#fill_world): its doors and its levers, and the cell of
    # the secret lift's car, minus one where it has none.
    game_variables :doors, :levers, :secret_car
    # One floor's way out and start (#fill_rooms): the first and last exit cell, and whether the
    # player's start has been written.
    game_variables :exit_first, :exit_last, :started
    # Counting one floor's guards (#fill_guards): how many stand there, and the men to kill on each
    # setting.
    game_variables :guards, :kills
    # The guard a thing code puts down (#read_guard, #set_boss, #set_rank), which #write_guard
    # writes: his kind, the way he faces, whether he patrols, whether he lies in wait, and the
    # easiest setting he turns up on.
    game_variables :guard_kind, :guard_dir, :guard_patrolling, :guard_ambush, :guard_from
    # Counting what stands in one floor's rooms (#fill_pieces): every piece, and the treasures among
    # them.
    game_variables :pieces, :treasures
    # Counting one floor's walls that move (#fill_pushwalls).
    game_variables :pushed

    WIDTH = 64 # Cells across a floor, and down it
    CELLS = WIDTH * WIDTH
    FLOORS = Holding::FLOORS
    PLANE_BYTES = CELLS * 2

    # Where a floor's header names its first plane, in GAMEMAPS: three plane starts, four bytes each.
    THINGS_PLANE_AT = 4
    # ...and where the planes' packed lengths follow them: after three plane starts.
    PLANE_LENGTHS_AT = 12

    # A FLOOR'S DOORS ARE A FIXED RUN OF THIS MANY in each door slot, floor n's from n times it, so
    # nothing has to add up the floors before it. The original's own limit (Holding::ROOM).
    #
    # A floor past one of these limits is never unpacked: the original quits on one (wolf4sdl:
    # wl_act1.cpp, SpawnDoor at MAXDOORS and SpawnStatic at MAXSTATS), and the pack is
    # only ever made from a copy Vanilla::RELEASES names by its SHA-1, whose every floor the tests
    # hold to the readers. So past a limit the lists stop and the maps go on, unchecked.
    DOORS_PER_FLOOR = Holding::ROOM.fetch(:doors)
    PUSHWALLS_PER_FLOOR = Holding::ROOM.fetch(:pushwalls)
    PIECES_PER_FLOOR = Holding::ROOM.fetch(:pieces)
    GUARDS_PER_FLOOR = Holding::ROOM.fetch(:guards)

    # The lowest thing code any enemy answers to; nearly every cell holds one below it.
    LOWEST_GUARD_CODE = Enemy::ALL.select { |enemy| enemy.codes.positive? }.map(&:standing).min

    # The pieces the screen between floors counts as treasure: the four treasures and the one-up
    # (Pickups::COUNTS_AS_TREASURE), as Scenery's kinds.
    TREASURE_KINDS = Scenery::BONUSES.select { |_, (gives, _)| %i[treasure extra_life].include?(gives) }.keys.freeze

    # What a guard is as the floor puts him down, a byte each, in the order #write_guard writes
    # them. All the rest of what GuardPool's guard_home tables hold (his first state, how long it
    # lasts, how much killing he takes, whether he counts) follows from his kind and whether he
    # patrols, which are rules of the game and not data in the copy.
    GUARD_SLOTS = %i[guard_x guard_y guard_kind guard_dir guard_patrolling guard_ambush guard_from].freeze

    # The start code that faces east (Level::FACINGS), which the quarter turns count from.
    FACING_EAST = Level::FACINGS.key(:east)

    # The four cells beside one, east, west, south and north, as steps across and down.
    BESIDE = Ractor.make_shareable([[1, 0], [-1, 0], [0, 1], [0, -1]])

    # The slots the floors take, declared on +slots+ (the data pack's).
    def self.declare(slots)
      slots.numbers :floor_count, count: 1, width: :byte, signed: false
      slots.numbers :wall_plane, count: CELLS * FLOORS, width: :half, signed: false
      slots.numbers :thing_plane, count: CELLS * FLOORS, width: :half, signed: false
      slots.numbers :world, count: CELLS * FLOORS, width: :half, signed: false
      %i[door_count pushwall_count lift_count].each do |name|
        slots.numbers name, count: FLOORS, width: :byte, signed: false
      end
      %i[door_picture door_across door_lock door_side_a door_side_b].each do |name|
        slots.numbers name, count: DOORS_PER_FLOOR * FLOORS, width: :byte, signed: false
      end
      slots.numbers :push_home, count: PUSHWALLS_PER_FLOOR * FLOORS, width: :half, signed: false
      %i[push_face push_room_a push_room_b].each do |name|
        slots.numbers name, count: PUSHWALLS_PER_FLOOR * FLOORS, width: :byte, signed: false
      end
      # Minus one where a floor has no secret lift, because nought is a real cell (ThisFloor).
      slots.numbers :secret_car, count: FLOORS, width: :half, signed: true
      declare_pieces(slots)
      slots.numbers :guard_count, count: FLOORS, width: :byte, signed: false
      GUARD_SLOTS.each { |name| slots.numbers name, count: GUARDS_PER_FLOOR * FLOORS, width: :byte, signed: false }
      declare_rooms(slots)
    end

    # THE ROOMS (Rooms), counting from one so nought is Rooms::NOWHERE: every cell's, laid out like
    # the map. The way out (FirstPerson#the_way_out_of) as the first and last cell of its run of
    # exit tiles, first above last where a floor has none. And the totals the screen between floors
    # counts against (Tally): the men to kill at each of Guards::SETTINGS, and the treasure.
    def self.declare_rooms(slots)
      slots.numbers :room_of, count: CELLS * FLOORS, width: :byte, signed: false
      slots.numbers :guard_arrow, count: CELLS * FLOORS, width: :byte, signed: false
      %i[exit_first exit_last treasure_total].each do |name|
        slots.numbers name, count: FLOORS, width: :half, signed: false
      end
      slots.numbers :kill_total, count: FLOORS * Guards::SETTINGS.length, width: :byte, signed: false
      # Where the player starts each floor, and the way they face as quarter turns clockwise from
      # east, the way FirstPerson's angle runs.
      %i[start_x start_y start_quarter_turns].each do |name|
        slots.numbers name, count: FLOORS, width: :byte, signed: false
      end
    end

    # A piece's cell, which of Scenery's pieces it is (its code less Scenery::FIRST_CODE: what it
    # gives you is looked up by that), and its picture. Then two tables laid out like the map: one
    # for a cell a foot cannot pass, one for a cell with something to pick up, as the piece's number
    # in its floor counting from one. A floor can hold more pieces than a byte counts.
    def self.declare_pieces(slots)
      slots.numbers :piece_count, count: FLOORS, width: :half, signed: false
      %i[piece_x piece_y piece_kind piece_picture piece_room].each do |name|
        slots.numbers name, count: PIECES_PER_FLOOR * FLOORS, width: :byte, signed: false
      end
      slots.numbers :blocked, count: CELLS * FLOORS, width: :byte, signed: false
      slots.numbers :lying_at, count: CELLS * FLOORS, width: :half, signed: false
    end

    # +b+ is the routine's builder, and +copy+, +pack+ and +release+ what `fill_from_copy` hands it.
    def initialize(b, copy, pack, release)
      @b = b
      @copy = copy
      @pack = pack
      @release = release
    end

    # The whole of it, in the order each part needs the last. Only the floors the release has are
    # worked out; the rest of each slot stays nought.
    #
    # EVERY LOOP HERE IS A COUNTED `repeat`: a loop on a plain Ruby number would run while the
    # routine is BUILT, writing its body out once a cell.
    def fill
      @floors = 0
      @outside = false

      @doors = 0
      @levers = 0
      @secret_car = -1

      @exit_first = -1
      @exit_last = 0
      @started = false

      @guards = 0
      @kills = Array.new(Guards::SETTINGS.length, 0)

      @guard_kind = -1
      @guard_dir = 0
      @guard_patrolling = 0
      @guard_ambush = 0
      @guard_from = 0

      @pieces = 0
      @treasures = 0

      @pushed = 0
      unpack_planes
      # The doors' pictures are the last eight pages before the sprites (Doors::DOOR_PICTURES), and
      # VSWAP's header says where the sprites start: its second word.
      first_door = @copy.file("VSWAP.#{@release}").half(2) - Doors::DOOR_PICTURES
      @b.repeat(@floors) { |n| fill_world(n, first_door) }
    end

    private

    # BOTH PLANES OF EVERY FLOOR THE RELEASE HAS, and how many that is, into @floors: MAPHEAD's
    # places run until the first that is nought, or the first floor whose planes are not all inside
    # GAMEMAPS.
    #
    # Must check every place against the file: one past its end reads on into the next file of the
    # copy without a word. Only a release Vanilla names by its SHA-1 is unpacked, so this never stops
    # a real one.
    def unpack_planes
      head = @copy.file("MAPHEAD.#{@release}")
      maps = @copy.file("GAMEMAPS.#{@release}")
      @b.repeat(FLOORS, stop_when: (head.word(2 + (4 * @floors)) == 0) || @outside) do
        level_at = head.word(2 + (4 * @floors))
        @outside = true unless planes_inside?(maps, level_at)
        unless @outside
          maps.unpack_map_plane at: maps.word(level_at), into: @pack[:wall_plane], start: PLANE_BYTES * @floors,
                                tag: head.half(0)
          maps.unpack_map_plane at: maps.word(level_at + THINGS_PLANE_AT), into: @pack[:thing_plane],
                                start: PLANE_BYTES * @floors, tag: head.half(0)
          @floors += 1
        end
      end
      @pack[:floor_count][0] = @floors
    end

    # WHETHER A FLOOR'S HEADER AT +level_at+ AND ITS TWO PLANES LIE INSIDE GAMEMAPS (+maps+). The
    # header holds the three planes' starts, four bytes each, then their packed lengths, two bytes
    # each (wolf4sdl: id_ca.h, maptype's planestart and planelength).
    def planes_inside?(maps, level_at)
      level_at + PLANE_LENGTHS_AT + 4 <= maps.size &&
        maps.word(level_at) + maps.half(level_at + PLANE_LENGTHS_AT) <= maps.size &&
        maps.word(level_at + THINGS_PLANE_AT) + maps.half(level_at + PLANE_LENGTHS_AT + 2) <= maps.size
    end

    # WHAT EACH CELL OF FLOOR +n+ MEANS TO THE WALK (FloorTables::Baked#encode_cell): a door's number above
    # ThisFloor::DOOR, a wall that moves above PUSH, a lever above LIFT, else a wall's lit picture
    # counting from one, or nought for floor. Doors and levers are numbered in the order the map
    # is read, a row at a time, as Doors and Elevator number them.
    def fill_world(n, first_door)
      base = CELLS * n
      @doors = 0
      @levers = 0
      @secret_car = -1
      # First, because a door, a wall that moves and a piece each ask which room is beside them.
      fill_rooms(n, base)
      @b.repeat(CELLS) do |cell|
        code = wall_code(base + cell)
        number = 0
        # The first cell in the map's order marked as the secret lift's car (Elevator#secret_cars).
        @secret_car = cell if code == Elevator::SECRET_CAR && @secret_car < 0
        if door?(code)
          number = ThisFloor::DOOR + @doors
          write_door((DOORS_PER_FLOOR * n) + @doors, code, first_door, base, cell) if @doors < DOORS_PER_FLOOR
          @doors += 1
        elsif code == Elevator::SWITCH
          number = ThisFloor::LIFT + @levers
          @levers += 1
        elsif code < Level::FLOOR && code != Level::AMBUSH && code >= 1 && code <= Holding::WALL_PAGES / 2
          number = ((code - 1) * 2) + 1
        end
        write_world(base + cell, number)
      end
      @pack[:door_count][n] = @doors
      @pack[:lift_count][n] = @levers
      @pack[:secret_car][n] = @secret_car
      @copy.count_written 4
      fill_pushwalls(n, base)
      fill_pieces(n, base)
      fill_guards(n, base)
    end

    # FLOOR +n+'S ROOMS AND ITS WAY OUT. A floor cell's code is Level::FLOOR plus its room
    # (Level#area), and every other cell is in none. The exit tiles lie side by side in one row on
    # the two floors that have them (FirstPerson#the_way_out_of refuses a floor where they do not).
    def fill_rooms(n, base)
      @exit_first = -1
      @exit_last = 0
      @started = false
      @b.repeat(CELLS) do |cell|
        code = wall_code(base + cell)
        thing = thing_code(base + cell)
        @pack[:room_of][base + cell] = code - (Level::FLOOR - 1) if code >= Level::FLOOR
        if thing == Level::EXIT
          @exit_first = cell if @exit_first < 0
          @exit_last = cell
        end
        if !@started && thing >= Level::FACINGS.keys.min && thing <= Level::FACINGS.keys.max
          write_start(n, cell, thing)
          @started = true
        end
        # A TURNING POINT sends a patrolling guard who reaches it the way it names (Guards#arrow_at):
        # eight codes from Guards::FIRST_ARROW in the original's order of directions. Every other
        # cell says nowhere, which is carry on.
        @pack[:guard_arrow][base + cell] = Guards::NOWHERE
        if thing >= Guards::FIRST_ARROW && thing < Guards::FIRST_ARROW + Guards::NOWHERE
          @pack[:guard_arrow][base + cell] = thing - Guards::FIRST_ARROW
        end
        @copy.count_written 2
      end
      @exit_first = 1 if @exit_first < 0
      @pack[:exit_first][n] = @exit_first
      @pack[:exit_last][n] = @exit_last
      @copy.count_written 4
    end

    # WHERE THE PLAYER STARTS FLOOR +n+: the first cell in the map's order holding one of
    # Level::FACINGS' codes (Level#start), which run north, east, south, west. Counted from east's
    # and taken in fours that is east nought, south one, west two, north three: quarter turns
    # clockwise from east (FirstPerson#facing_angle).
    def write_start(n, cell, code)
      @pack[:start_x][n] = cell_x(cell)
      @pack[:start_y][n] = cell_y(cell)
      @pack[:start_quarter_turns][n] = (code - FACING_EAST) % Level::FACINGS.length
      @copy.count_written 3
    end

    # THE ROOM AT CELL +x+, +y+ of the floor at +base+: nought outside the map.
    def room_at(base, x, y)
      room = 0
      room = @pack[:room_of][cell_at(base, x, y)] if x >= 0 && y >= 0 && x < WIDTH && y < WIDTH
      room
    end

    # EVERYONE FLOOR +n+ CAN HOLD, at any setting, in the map's order (Guards#guard_at): a thing
    # code names a kind by the block it falls in, less the harder games' steps, and what is left
    # says which way he faces and whether he patrols. No two blocks overlap
    # (Guards.overlapping_codes), so at most one arm below matches a cell.
    def fill_guards(n, base)
      @guards = 0
      Guards::SETTINGS.each_index { |setting| @kills[setting] = 0 }
      @b.repeat(CELLS) do |cell|
        read_guard(thing_code(base + cell), wall_code(base + cell))
        if @guard_kind >= 0
          write_guard((GUARDS_PER_FLOOR * n) + @guards, cell) if @guards < GUARDS_PER_FLOOR
          @guards += 1
          # A man to kill on every setting from the easiest he turns up on (Guards#to_kill).
          Guards::SETTINGS.each_index { |setting| @kills[setting] += 1 if @guard_from <= setting }
          # THE MAN INSIDE THE MACHINE stands in the machine's cell from the start, waiting
          # (Guards#with_the_man_inside), one more of the floor's guards, and no man to kill
          # (Enemy#counted?): the machine was. wolf4sdl: wl_act2.cpp, A_HitlerMorph.
          if @guard_kind == kind_number(:mecha)
            @guard_kind = kind_number(:hitler)
            write_guard((GUARDS_PER_FLOOR * n) + @guards, cell) if @guards < GUARDS_PER_FLOOR
            @guards += 1
          end
        end
      end
      @pack[:guard_count][n] = @guards
      Guards::SETTINGS.each_index do |setting|
        @pack[:kill_total][(n * Guards::SETTINGS.length) + setting] = @kills[setting]
      end
      @copy.count_written 1 + Guards::SETTINGS.length
    end

    # WHO A THING CODE PUTS DOWN, into the @guard_ variables: his kind's number, or minus one for
    # nobody. +floor_code+ is the wall plane's code under him, which says whether he lies in wait.
    def read_guard(thing, floor_code)
      @guard_kind = -1
      # Nearly every cell holds a code below every kind's, and asks no more than this.
      read_guard_kind(thing, floor_code) if thing >= LOWEST_GUARD_CODE
    end

    # ...for a code that can be somebody's: one arm per block of every kind.
    def read_guard_kind(code, floor_code)
      Enemy::ALL.each_with_index do |enemy, number|
        enemy.blocks.times do |step|
          within = code - (step * enemy.harder) - enemy.standing
          if within >= 0 && within < enemy.codes
            @guard_kind = number
            @guard_from = Guards::FROM.fetch(step)
            if enemy.boss?
              set_boss
            else
              set_rank(within, floor_code)
              # A kind that never stands reads its standing block as nobody: the dog.
              @guard_kind = -1 if !enemy.stands && within < Guards::FACES
            end
          end
        end
      end
    end

    # A BOSS faces nowhere, never patrols and lies in wait wherever he is put (Guards#boss_at).
    def set_boss
      @guard_dir = Guards::NOWHERE
      @guard_patrolling = 0
      @guard_ambush = 1
    end

    # One of the rank and file: four codes facing east, north, west and south (Guards::FACINGS),
    # then the same four patrolling. The original numbers directions with the diagonals between,
    # so a square one is every other number (Guards.direction_of).
    def set_rank(within, floor_code)
      @guard_dir = (within % Guards::FACES) * 2
      @guard_patrolling = 0
      @guard_patrolling = 1 if within >= Guards::FACES
      @guard_ambush = 0
      @guard_ambush = 1 if floor_code == Level::AMBUSH
    end

    # GUARD +at+ IN ITS SLOTS, from the @guard_ variables, standing in +cell+.
    def write_guard(at, cell)
      @pack[:guard_x][at] = cell_x(cell)
      @pack[:guard_y][at] = cell_y(cell)
      @pack[:guard_kind][at] = @guard_kind
      @pack[:guard_dir][at] = @guard_dir
      @pack[:guard_patrolling][at] = @guard_patrolling
      @pack[:guard_ambush][at] = @guard_ambush
      @pack[:guard_from][at] = @guard_from
      @copy.count_written GUARD_SLOTS.length
    end

    def kind_number(name) = Enemy::ALL.index { |enemy| enemy.name == name }

    # WHAT STANDS IN THE ROOMS OF FLOOR +n+ (Scenery): every cell whose thing code names one of
    # Scenery's pieces, in the map's order. Only a cell with something on it is written; the rest
    # of the two map-shaped tables stays nought.
    def fill_pieces(n, base)
      @pieces = 0
      @treasures = 0
      @b.repeat(CELLS) do |cell|
        kind = thing_code(base + cell) - Scenery::FIRST_CODE
        if kind >= 0 && kind < Scenery::PICTURES.length
          write_piece((PIECES_PER_FLOOR * n) + @pieces, base, cell, kind) if @pieces < PIECES_PER_FLOOR
          @treasures += 1 if any_of?(kind, TREASURE_KINDS)
          @pack[:blocked][base + cell] = 1 if any_of?(kind, Scenery::BLOCKING)
          @pieces += 1
          @pack[:lying_at][base + cell] = @pieces if any_of?(kind, Scenery::BONUSES.keys)
          @copy.count_written 3
        end
      end
      @pack[:piece_count][n] = @pieces
      @pack[:treasure_total][n] = @treasures
      @copy.count_written 4
    end

    # PIECE +at+ IN ITS SLOTS. Its picture is Scenery.picture_of: each piece wears the picture
    # of its own number, but for the few in Scenery::PICTURES that borrow another's.
    def write_piece(at, base, cell, kind)
      @pack[:piece_room][at] = room_at(base, cell_x(cell), cell_y(cell))
      picture = Scenery::FIRST_PICTURE + kind
      Scenery::PICTURES.each_with_index do |worn, own|
        picture = Scenery::FIRST_PICTURE + worn if worn != own && kind == own
      end
      @pack[:piece_x][at] = cell_x(cell)
      @pack[:piece_y][at] = cell_y(cell)
      @pack[:piece_kind][at] = kind
      @pack[:piece_picture][at] = picture
      @copy.count_written 5
    end

    # DOOR +at+ IN THE DOOR SLOTS, from its wall +code+ (Doors#door_at): the picture it wears, at its
    # page, which way its panel runs, and the key bit it wants (FirstPerson::KEY_BITS). An even code
    # runs across x; a lift's door and a locked one wear pictures of their own. It joins the rooms
    # either side of its panel (Rooms#joins): west and east of one across x, else north and south.
    def write_door(at, code, first_door, base, cell)
      x = cell_x(cell)
      y = cell_y(cell)
      if (code & 1) == Doors::ACROSS_X
        @pack[:door_side_a][at] = room_at(base, x - 1, y)
        @pack[:door_side_b][at] = room_at(base, x + 1, y)
      else
        @pack[:door_side_a][at] = room_at(base, x, y - 1)
        @pack[:door_side_b][at] = room_at(base, x, y + 1)
      end
      @copy.count_written 2
      kind = Doors::FACE
      kind = Doors::ELEVATOR if code == Level::ELEVATOR_DOORS[0] || code == Level::ELEVATOR_DOORS[1]
      kind = Doors::LOCKED if code >= Level::LOCKED_DOORS.first && code <= Level::LOCKED_DOORS.last
      @pack[:door_picture][at] = first_door + kind + (code & 1)
      @pack[:door_across][at] = code & 1
      lock = 0
      # The locked codes run in pairs, gold's then silver's (Level#lock_at).
      gold, _, silver, = Level::LOCKED_DOORS
      lock = FirstPerson::KEY_BITS.fetch(:gold) if code == gold || code == gold + 1
      lock = FirstPerson::KEY_BITS.fetch(:silver) if code == silver || code == silver + 1
      @pack[:door_lock][at] = lock
      @copy.count_written 3
    end

    # A WALL THAT MOVES CLAIMS ITS OWN CELL AND UP TO TWO EACH WAY, while the floor goes on
    # (Pushwalls#reachable_from), and the first in the map's order keeps a cell two of them reach. A
    # door's cell stays the door's. Each wall's home cell and face go in floor +n+'s run.
    def fill_pushwalls(n, base)
      @pushed = 0
      @b.repeat(CELLS) do |cell|
        if thing_code(base + cell) == Level::PUSHWALL && solid?(base, cell_x(cell), cell_y(cell))
          if @pushed < PUSHWALLS_PER_FLOOR
            write_pushwall((PUSHWALLS_PER_FLOOR * n) + @pushed, cell, wall_code(base + cell))
            write_pushwall_rooms((PUSHWALLS_PER_FLOOR * n) + @pushed, base, cell)
          end
          claim(base, cell_x(cell), cell_y(cell), @pushed)
          BESIDE.each do |dx, dy|
            x = cell_x(cell) + dx
            y = cell_y(cell) + dy
            unless solid?(base, x, y)
              claim(base, x, y, @pushed)
              x += dx
              y += dy
              claim(base, x, y, @pushed) unless solid?(base, x, y)
            end
          end
          @pushed += 1
        end
      end
      @pack[:pushwall_count][n] = @pushed
      @copy.count_written 1
    end

    # WALL THAT MOVES +at+ IN ITS SLOTS: the cell it starts in, counted within its own floor, and
    # the page of its lit face. It is made of an ordinary wall, so it wears that wall's picture
    # (FirstPerson#push_pictures), and a code's lit face is page (code - 1) * 2 in the whole row.
    def write_pushwall(at, cell, code)
      @pack[:push_home][at] = cell
      @pack[:push_face][at] = (code - 1) * 2
      @copy.count_written 3
    end

    # THE TWO ROOMS A WALL THAT MOVES STANDS BETWEEN, which Rooms keeps joined for good
    # (Rooms#always_joined): the rooms of the four cells round it, each once, in the order east,
    # west, south, north, and only where there are exactly two. Nought for both otherwise.
    def write_pushwall_rooms(at, base, cell)
      near = 0
      far = 0
      more = false
      BESIDE.each do |dx, dy|
        room = room_at(base, cell_x(cell) + dx, cell_y(cell) + dy)
        if room > 0
          if near == 0
            near = room
          elsif room != near && far == 0
            far = room
          elsif room != near && room != far
            more = true
          end
        end
      end
      if far > 0 && !more
        @pack[:push_room_a][at] = near
        @pack[:push_room_b][at] = far
      end
      @copy.count_written 2
    end

    # Cell +x+, +y+ of the floor at +base+ for wall that moves +pushed+, unless a door or an earlier
    # wall that moves has it.
    def claim(base, x, y, pushed)
      held = world_at(cell_at(base, x, y))
      write_world(cell_at(base, x, y), ThisFloor::PUSH + pushed) unless held >= ThisFloor::DOOR && held < ThisFloor::LIFT
    end

    # Level#solid?, on the unpacked plane: outside the map, or a wall that is not a door or an ambush.
    def solid?(base, x, y)
      x < 0 || y < 0 || x >= WIDTH || y >= WIDTH || solid_code?(wall_code(cell_at(base, x, y)))
    end

    def solid_code?(code) = code < Level::FLOOR && !door?(code) && code != Level::AMBUSH

    def door?(code) = any_of?(code, Level::DOORS)

    # Is +value+, a number the routine reads, one of +numbers+? One comparison each, as it runs.
    def any_of?(value, numbers) = numbers.map { |number| value == number }.reduce(:|)

    def wall_code(at) = @pack[:wall_plane][at]
    def thing_code(at) = @pack[:thing_plane][at]
    def world_at(at) = @pack[:world][at]

    # A cell counted along the rows of a floor, as its column and row; and back again, in the floor
    # at +base+.
    def cell_x(cell) = cell % WIDTH
    def cell_y(cell) = cell / WIDTH
    def cell_at(base, x, y) = base + (y * WIDTH) + x

    def write_world(at, number)
      @pack[:world][at] = number
      @copy.count_written 2
    end
  end
end
