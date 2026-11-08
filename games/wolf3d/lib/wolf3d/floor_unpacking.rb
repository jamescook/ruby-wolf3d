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
  # reads is a loop or a branch in it, and a local it changes is one of its variables.
  class FloorUnpacking
    CELLS = 64 * 64
    FLOORS = Holding::FLOORS
    PLANE_BYTES = CELLS * 2

    # Where a floor's header names its first plane, in GAMEMAPS: three plane starts, four bytes each.
    THINGS_PLANE_AT = 4

    # The slots the floors take, declared on +slots+ (the data pack's).
    def self.declare(slots)
      slots.numbers :floor_count, count: 1, width: :byte, signed: false, layout: :gba
      slots.numbers :wall_plane, count: CELLS * FLOORS, width: :half, signed: false, layout: :gba
      slots.numbers :thing_plane, count: CELLS * FLOORS, width: :half, signed: false, layout: :gba
      slots.numbers :world, count: CELLS * FLOORS, width: :half, signed: false, layout: :gba
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
    # EVERY COUNT HERE IS A VARIABLE OF THE ROUTINE'S (#counter) and every loop a counted `repeat`:
    # a loop on a plain Ruby number would run while the routine is BUILT, writing its body out once
    # a cell.
    def fill
      floors = unpack_planes
      @b.repeat(floors) { |n| fill_world(n) }
    end

    private

    # BOTH PLANES OF EVERY FLOOR THE RELEASE HAS, and how many that is: MAPHEAD's places run until
    # the first that is nought.
    def unpack_planes
      head = @copy.file("MAPHEAD.#{@release}")
      maps = @copy.file("GAMEMAPS.#{@release}")
      floors = counter(:floors)
      level_at = counter(:level_at)
      floors.store!(0)
      @b.repeat(FLOORS, stop_when: head.word(2 + (4 * floors)) == 0) do
        level_at.store!(head.word(2 + (4 * floors)))
        maps.unpack_map_plane at: maps.word(level_at), into: @pack[:wall_plane], start: PLANE_BYTES * floors,
                              tag: head.half(0)
        maps.unpack_map_plane at: maps.word(level_at + THINGS_PLANE_AT), into: @pack[:thing_plane],
                              start: PLANE_BYTES * floors, tag: head.half(0)
        floors.increase!(1)
      end
      @pack[:floor_count][0] = floors
      floors
    end

    # WHAT EACH CELL OF FLOOR +n+ MEANS TO THE WALK (ThisFloor#number_for): a door's number above
    # ThisFloor::DOOR, a wall that moves above PUSH, a lever above LIFT, else a wall's lit picture
    # counting from one, or nought for floor. Doors and levers are numbered in the order the map
    # is read, a row at a time, as Doors and Elevator number them.
    def fill_world(n)
      base = counter(:base)
      doors = counter(:doors)
      levers = counter(:levers)
      code = counter(:code)
      number = counter(:number)
      base.store!(CELLS * n)
      doors.store!(0)
      levers.store!(0)
      @b.repeat(CELLS) do |cell|
        code.store!(wall_code(base + cell))
        number.store!(0)
        if door?(code)
          number.store!(ThisFloor::DOOR + doors)
          doors.increase!(1)
        elsif code == Elevator::SWITCH
          number.store!(ThisFloor::LIFT + levers)
          levers.increase!(1)
        elsif code < Level::FLOOR && code != Level::AMBUSH && code >= 1 && code <= Holding::WALL_PAGES / 2
          number.store!(((code - 1) * 2) + 1)
        end
        write_world(base + cell, number)
      end
      fill_pushwalls(base)
    end

    # A WALL THAT MOVES CLAIMS ITS OWN CELL AND UP TO TWO EACH WAY, while the floor goes on
    # (Pushwalls#reachable_from), and the first in the map's order keeps a cell two of them reach. A
    # door's cell stays the door's.
    def fill_pushwalls(base)
      pushed = counter(:pushed)
      x = counter(:x)
      y = counter(:y)
      pushed.store!(0)
      @b.repeat(CELLS) do |cell|
        if thing_code(base + cell) == Level::PUSHWALL && solid?(base, cell % 64, cell / 64)
          claim(base, cell % 64, cell / 64, pushed)
          [[1, 0], [-1, 0], [0, 1], [0, -1]].each do |dx, dy|
            x.store!((cell % 64) + dx)
            y.store!((cell / 64) + dy)
            unless solid?(base, x, y)
              claim(base, x, y, pushed)
              x.increase!(dx)
              y.increase!(dy)
              claim(base, x, y, pushed) unless solid?(base, x, y)
            end
          end
          pushed.increase!(1)
        end
      end
    end

    # Cell +x+, +y+ of the floor at +base+ for wall that moves +pushed+, unless a door or an earlier
    # wall that moves has it.
    def claim(base, x, y, pushed)
      held = counter(:held)
      held.store!(world_at(base + (y * 64) + x))
      write_world(base + (y * 64) + x, ThisFloor::PUSH + pushed) unless held >= ThisFloor::DOOR && held < ThisFloor::LIFT
    end

    # Level#solid?, on the unpacked plane: outside the map, or a wall that is not a door or an ambush.
    def solid?(base, x, y)
      x < 0 || y < 0 || x >= 64 || y >= 64 || solid_code?(wall_code(base + (y * 64) + x))
    end

    def solid_code?(code) = code < Level::FLOOR && !door?(code) && code != Level::AMBUSH

    # One of Level::DOORS, asked as the routine runs.
    def door?(code) = Level::DOORS.map { |door| code == door }.reduce(:|)

    def wall_code(at) = word(:wall_plane, at)
    def thing_code(at) = word(:thing_plane, at)
    def world_at(at) = word(:world, at)

    def word(slot, at) = @pack[slot][at * 2] | (@pack[slot][(at * 2) + 1] << 8)

    def write_world(at, number)
      @pack[:world][at * 2] = number
      @pack[:world][(at * 2) + 1] = number >> 8
      @copy.count_written 2
    end

    # A variable of the routine's, made the first time it is asked for.
    def counter(name) = (@counters ||= {})[name] ||= @b.var(:"_floor_unpacking_#{name}", 0)
  end
end
