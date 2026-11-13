# frozen_string_literal: true

module Wolf3DTest
  # A FLOOR MADE FOR ONE QUESTION, AND THE GAME BUILT AROUND IT. Nearly every test of how this game
  # plays wants the same two things: a walled field with exactly what the question needs standing
  # in it, and the view over that floor, ready to run on the interpreter.
  #
  # Built straight rather than written out as a release and read back, because what each of these
  # tests needs is one exact arrangement. A place is an [x, y] of cells, and a guard is [x, y, way].
  #
  # A test file names what is particular to it by defining its own +arena+ or +view_of+ and calling
  # +super+. +fixture+ is the one to override for a release with more pictures in it: everything
  # below reads its pictures through it.
  module Field
    SIDE = 16
    FLOOR = Wolf3D::Level::FLOOR
    WALL = Wolf3D::Fixture::Release::WALL

    # How many passes of holding left or right, walking, turn the player +units+ of
    # FirstPerson::TURN. A class constant can ask it too.
    def self.walking_turn_passes(units) = (units / Wolf3D::FirstPerson::TURN_UNITS_WALKING.to_f).ceil

    def fixture = @fixture ||= Wolf3D::Fixture::Release.new
    def vswap = @vswap ||= Wolf3D::Vswap.new(fixture.files["VSWAP"])
    def palette = Wolf3D::Palette.game

    # The fixture's own floor, which is the one with doors, a key and a wall that slides.
    def fixture_level
      @fixture_level ||= Wolf3D::Maps.new(maphead: fixture.files["MAPHEAD"],
                                          gamemaps: fixture.files["GAMEMAPS"])[0]
    end

    # A WALLED FIELD, all one room. +walls+ builds wall on those cells, and +cells+ puts any other
    # code in the map where you say. What stands in it is +level_of+'s to place. +floor+ is the code
    # the room is laid in, which is which room it counts as.
    def arena(side: SIDE, floor: FLOOR, walls: [], cells: {}, player: [8, 8], **standing)
      map = Array.new(side * side) do |at|
        y, x = at.divmod(side)
        [x, y].any? { |n| n.zero? || n == side - 1 } ? WALL : floor
      end
      walls.each { |x, y| map[(y * side) + x] = WALL }
      cells.each { |(x, y), code| map[(y * side) + x] = code }
      level_of(map, side, player: player, **standing)
    end

    # TWO ROOMS SIDE BY SIDE with a wall between them, which is how the game says two places are
    # different rooms: a floor cell's code is 107 plus the room it belongs to. +door+ is a door in
    # the wall and +openings+ are holes in it. A hole is laid in the left room's code, so the right
    # one stays a room of its own: rooms are joined by doors and by nothing else.
    def two_rooms(player: [3, 8], door: [7, 8], openings: [], **standing)
      map = Array.new(SIDE * SIDE, WALL)
      (1..SIDE - 2).each do |y|
        (1..6).each { |x| map[(y * SIDE) + x] = FLOOR }
        (8..SIDE - 2).each { |x| map[(y * SIDE) + x] = FLOOR + 1 }
      end
      map[(door[1] * SIDE) + door[0]] = Wolf3D::Level::DOORS.first if door
      openings.each { |x, y| map[(y * SIDE) + x] = FLOOR }
      level_of(map, SIDE, player: player, **standing)
    end

    # A room with the way out behind the player, who faces east, and a guard shut in a room of his
    # own below it. The guard is there because a game needs something that can kill you before it
    # counts lives at all, and it is the count of lives that answers START. +lever+ adds a lift's
    # lever to the far wall, and that needs a +fixture+ whose walls reach as far as a lever's.
    def way_out_level(lever: false)
      arena(name: "Way out", player: [4, 4], walls: (0...SIDE).map { |x| [x, SIDE / 2] },
            cells: lever ? { [SIDE - 1, 2] => Wolf3D::Elevator::SWITCH } : {},
            things: { [3, 4] => Wolf3D::Level::EXIT, [10, 12] => a_guard(:south) })
    end

    # A LEVEL OUT OF A MAP SOMEBODY HAS ALREADY LAID, with what stands on it. +guards+ stand where
    # they are put and +patrols+ walk a beat. +ahead+ is pieces of scenery, by their place in the
    # original's list, laid on the cells in front of a player facing east. +things+ puts any other
    # code in the things plane, and goes down last.
    def level_of(map, side, player:, facing: :east, guards: [], patrols: [], ahead: [], things: {},
                 name: "Arena")
      standing = Array.new(side * side, 0)
      put = ->(x, y, code) { standing[(y * side) + x] = code }
      x, y = player
      put.call(x, y, Wolf3D::Level::FACINGS.key(facing))
      guards.each { |at_x, at_y, way| put.call(at_x, at_y, a_guard(way)) }
      patrols.each { |at_x, at_y, way| put.call(at_x, at_y, a_guard(way, Wolf3D::Guards::PATROLLING)) }
      ahead.each_with_index { |piece, n| put.call(x + 1 + n, y, Wolf3D::Scenery::FIRST_CODE + piece) }
      things.each { |(at_x, at_y), code| put.call(at_x, at_y, code) }

      Wolf3D::Level.new(name: name, width: side, height: side, walls: map, things: standing)
    end

    def a_guard(way, first = Wolf3D::Guards::STANDING) = first + Wolf3D::Guards::FACINGS.index(way)

    # One floor of a cartridge, and everything the build reads off it. +standing+ off leaves out
    # who and what is standing on it, which is a game of nothing but walls, doors and levers: a
    # floor with nobody on it is quicker to play, and a guard is one more thing that can move.
    def floor_of(level, index: 0, standing: true)
      Wolf3D::Floors::Floor.new(index: index, level: level,
                                doors: Wolf3D::Doors.new(level, vswap),
                                pushwalls: Wolf3D::Pushwalls.new(level),
                                lifts: Wolf3D::Elevator.new(level),
                                guards: (Wolf3D::Guards.new(level) if standing),
                                scenery: (Wolf3D::Scenery.new(level) if standing))
    end

    def floors_of(*levels, standing: true)
      Wolf3D::Floors.new(levels.each_with_index.map do |level, n|
        floor_of(level, index: n, standing: standing)
      end)
    end

    # The walls of these floors, and the pictures of whatever stands on them or nil where nothing
    # does.
    def atlases_of(floors)
      standing = floors.select(&:guards)
      [Wolf3D::WallAtlas.new(vswap, palette, floors.map(&:level), doors: floors.map(&:doors),
                                                                  lifts: floors.map(&:lifts)),
       (Wolf3D::ThingAtlas.new(vswap, palette, pictures_on(standing)) unless standing.empty?)]
    end

    # A CARTRIDGE OF THESE FLOORS, the view over them and nothing else, on the tear-free screen the
    # game itself draws on.
    #
    # +drawing+ off plays the game and skips the picture. Drawing costs about a hundred times
    # playing, so a test that reads a variable can have that for nothing. A test that SHOOTS cannot:
    # a shot goes to a man the renderer put on the screen, so with nothing drawn nobody is ever on
    # it and nothing can be shot.
    #
    # +sound+ is what the sound setting starts at, or nil for a game with no such setting.
    # +sounds_from+ names the readers the sounds are made from, as Recordings::Baked takes them
    # (+vswap:+, +adlib:+), or nil for a silent game. Anything else in +options+ goes to the view as
    # it is. A block is handed the build, the view and the setting, and writes the game loop itself.
    def cartridge_of(floors, drawing: true, sound: nil, sounds_from: nil, **options, &loop_body)
      atlas, things = atlases_of(floors)
      VBlank.game("VIEW", consoles: %i[gba]) do
        screen :bitmap, tear_free: true
        sound_setting = sound && var(:sound_setting, sound)
        recordings = sounds_from && Wolf3D::Recordings::Baked.new(self, **sounds_from)
        view = Wolf3D::FirstPerson.new(build: self, floors: floors, atlas: atlas, things: things,
                                       sound_setting: sound_setting, recordings: recordings, **options)
        if loop_body
          # With `instance_exec`, because that is what reads a test's block as a game's is read.
          instance_exec(self, view, sound_setting, &loop_body)
        else
          game_loop { drawing ? view.update : view.play }
        end
      end.program
    end

    # ...and the same for a single floor, which is nearly every test.
    def view_of(level, standing: true, **, &) = cartridge_of(floors_of(level, standing: standing), **, &)

    private

    def pictures_on(floors)
      floors.flat_map do |floor|
        floor.guards.pictures + floor.scenery.pictures + Wolf3D::Pickups.pictures(floor.guards) +
          Wolf3D::VictoryMarch.pictures([floor], vswap)
      end.uniq.sort
    end
  end
end
