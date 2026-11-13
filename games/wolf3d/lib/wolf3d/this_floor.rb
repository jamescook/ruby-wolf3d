# frozen_string_literal: true

module Wolf3D
  # THE FLOOR BEING PLAYED: where its slice of each table begins, and what a number in the map
  # means. Floors is every floor the cartridge holds, worked out while building; this is the one
  # the game is on, as it runs.
  #
  # WHERE A SLICE BEGINS. Every table in the cartridge holds all the floors end to end, and reading
  # one is the same read with the matching number below added — set once when a floor starts,
  # unchanged while it is played. In the walk that reads the map thousands of times a frame that is
  # a single add. They are set from an arm per floor rather than looked up in yet more tables,
  # because starting a floor happens a handful of times in a whole game: a great deal of code that
  # never runs while anybody is playing. See #go_to.
  #
  # THEY START AT THE FIRST FLOOR'S OWN NUMBERS, not at nothing, because at boot no floor has been
  # STARTED — the game simply begins on the first one. Left at nothing the game would come up on a
  # floor with no doors and no walls that move, until something sent the player back to the
  # beginning and quietly fixed it.
  #
  # EVERYTHING HERE IS WRITTEN INTO WHATEVER CALLS IT, because a plain Ruby method is emitted at
  # every call site. These are all one add or one comparison, so that is what a caller pays and
  # exactly what it would pay writing them out by hand.
  class ThisFloor
    # Where this floor's slice of each table starts, and how many it has of the doors, the walls
    # that slide and the pieces; and the cell of its secret lift. #go_to writes them as a floor
    # starts, and a load works them out again from which floor it is, so a save keeps none.
    game_variables :map_base, :door_first, :push_first, :piece_first, :door_count, :pushwall_count,
                   :piece_count, :secret_car, saved: false

    # Where the map table stops naming walls and starts naming the things that are more than a
    # wall. Each is above every picture a level could hold, so none of them can be confused.
    #
    # THEY ARE TESTED FROM THE TOP DOWN, biggest first, which is why LIFT sits above the other
    # two rather than below them: a lever is a wall you cannot walk into and cannot shove, so
    # anything that asks "can I stand here" or "did I just shove this" has to rule it out before
    # it reaches the tests for the two that move. One comparison, and only on a cell that already
    # holds something — the walk's own step is untouched.
    DOOR = 512
    PUSH = 1024
    LIFT = 2048

    # +floors+ is every floor the cartridge holds. +tables+ is where its per-floor tables come from
    # (FloorTables).
    def initialize(build:, floors:, tables:)
      @b = build
      @floors = floors
      @tables = tables
      @width = floors.width
      @height = floors.height
      declare
    end

    # How many of each thing this floor has, for a walk over them.
    attr_reader :door_count, :pushwall_count

    # ...the pieces' a plain number in a cartridge of one floor, which knows it while building.
    def piece_count = @tables.one_floor? ? @tables.fetch_floor_value(:pieces, 0) : @piece_count

    # The cell that means the secret lift on this floor, or minus one where it has none.
    attr_reader :secret_car

    # Where every part of the game gets its per-floor tables (FloorTables): the view, the pickups
    # and the drawing of what stands in the rooms all ask.
    attr_reader :tables

    # How many cells across a floor is, and down: every floor of a build is the same size
    # (Floors#refuse_mixed_sizes!).
    attr_reader :width, :height

    # POINT EVERYTHING AT FLOOR +n+, a number known while building: this writes that floor's own
    # numbers in. The caller picks which arm runs — see FirstPerson#select_floor.
    def go_to(n)
      @map_base = @tables.map_base(n)
      @door_first = @tables.run_start(:doors, n)
      @door_count = @tables.fetch_floor_value(:doors, n)
      @push_first = @tables.run_start(:pushwalls, n)
      @pushwall_count = @tables.fetch_floor_value(:pushwalls, n)
      @secret_car = @tables.fetch_floor_value(:secret_car, n)
      return if @tables.one_floor?

      @piece_first = @tables.run_start(:pieces, n)
      @piece_count = @tables.fetch_floor_value(:pieces, n)
    end

    # --- finding a slice -----------------------------------------------------------------

    # Where cell +x+, +y+ of this floor sits in any table laid out like the map.
    def map_index(x, y) = @map_base + (y * @width) + x

    # ...for a cell already worked out as a number within its own floor.
    def map_index_of(cell) = @map_base + cell

    # What the map says at a cell.
    def cell_at(x, y) = @world[map_index(x, y)]
    def cell(number) = @world[map_index_of(number)]

    # Where this floor's door, sliding wall or piece of scenery number +n+ sits in the tables that
    # hold every floor's. A one-floor cartridge has nothing to add for a piece.
    def door(n) = @door_first + n
    def pushwall(n) = @push_first + n
    def piece(n) = @tables.one_floor? ? n : @piece_first + n

    # DOES SOMETHING STANDING IN THIS CELL STOP A FOOT? Runs the block if so. A cartridge with
    # nothing of the kind on any floor has no table and emits no test.
    def when_blocked(cell)
      return unless @blocked

      yield if @blocked[map_index_of(cell)] == 1
    end

    # --- what a number in the map means --------------------------------------------------

    def lever?(cell) = cell >= LIFT
    def no_lever?(cell) = cell < LIFT

    # Which door or sliding wall a number in the map names, within its own floor.
    def door_in(cell) = cell - DOOR
    def pushwall_in(cell) = cell - PUSH

    # The number the map holds for this floor's door +n+.
    def cell_of_door(n) = DOOR + n

    # WHICH OF THE THREE IT IS, for a number already known not to be a lever: a block for each kind
    # the caller cares about, and a kind with none is passed over. Only ever asked of a cell that
    # holds something, so plain floor never gets this far.
    #
    # A caller that only wants doors, which is the commonest, tests for a door first: nearly every
    # number is neither, and then it pays the one comparison.
    def sort_out(cell, door: nil, pushwall: nil, wall: nil)
      if pushwall.nil? && wall.nil?
        door.call if cell >= DOOR && cell < PUSH
        return
      end

      rest = lambda do
        if wall
          if cell >= DOOR
            door.call
          else
            wall.call
          end
        elsif cell >= DOOR
          door.call
        end
      end

      if pushwall.nil?
        rest.call if cell < PUSH
      elsif cell >= PUSH
        pushwall.call
      else
        rest.call
      end
    end

    private

    def declare
      # THE MAP AS ONE FLAT TABLE, and it says three things in one number so that the walk asks
      # one question per step rather than two. 0 is open floor. Anything up to DOOR is a wall,
      # and the number is where its lit picture sits in the row of pictures, counting from one —
      # so the walk adds which way the face turns and has the picture. DOOR and above is a
      # doorway, and what is left over is which door.
      #
      # Keeping doors in the same table is what makes them nearly free: the walk already tests
      # "is there anything here", and that test is false almost every step. Only when something
      # IS here does it go on to ask which kind, and by then the ray has stopped anyway.
      @world = @tables.declare_world

      # WHICH CELLS HOLD SOMETHING A FOOT CANNOT PASS, and it is a table of its own rather than
      # a fifth meaning in the one above. A barrel is the first thing in this game that stops
      # you without being made of wall: your feet must not go there, and a ray MUST — you can
      # see past a barrel, and a ray that stopped at one would leave a barrel-shaped hole of
      # nothing in the room behind it.
      #
      # The walk over the map is by far the hottest thing here and it reads the table above
      # thousands of times a frame. Keeping this apart means the walk never learns the
      # difference, and the cost lands where it belongs: on the two questions a pair of feet
      # asks each frame. A baked build with nothing in the way anywhere has no table and emits no
      # test.
      @blocked = @tables.declare_blocked

      @map_base = @tables.map_base(0)
      @door_first = @tables.run_start(:doors, 0)
      @door_count = @tables.fetch_floor_value(:doors, 0)
      @push_first = @tables.run_start(:pushwalls, 0)
      @pushwall_count = @tables.fetch_floor_value(:pushwalls, 0)
      @secret_car = @tables.fetch_floor_value(:secret_car, 0)
      # A cartridge of one floor has its pieces from nought and knows how many while building, so
      # the walk over them is counted by a plain number and needs neither variable (#piece,
      # #piece_count).
      return if @tables.one_floor?

      @piece_first = @tables.run_start(:pieces, 0)
      @piece_count = @tables.fetch_floor_value(:pieces, 0)
    end
  end
end
