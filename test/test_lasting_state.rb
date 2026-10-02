# frozen_string_literal: true

require_relative "test_helper"

# WHAT A SAVED GAME HOLDS: everything about a game that lasts from one pass to the next and is
# not worked out again from the rest. Declared through LastingState, a thing is kept; a save
# writes it and a load puts it back.
#
# Read the way a player meets it: play a little, save, turn the console off, turn it on again
# with the same save memory, load, and look at what came back.
class TestLastingState < Minitest::Test
  include Wolf3DTest

  LastingState = Wolf3D::LastingState

  # WHAT IS DECLARED THROUGH IT IS KEPT, whether it was declared before the save record was
  # handed over or after. The parts of the game declare their state long before anything saves
  # it, and some after.
  def test_a_value_declared_through_it_comes_back_after_a_load
    store = {}
    played(store, :change, :save)
    run = played(store, :load)

    assert_equal [CHANGED_BEFORE, CHANGED_AFTER], [run[:before], run[:after]]
  end

  # ...AND A LIST AND A POOL come back whole: how far open each door is, and every guard in the
  # slot he stood in.
  def test_a_list_and_a_pool_declared_through_it_come_back_after_a_load
    store = {}
    saved = played(store, :change, :save)
    run = played(store, :load)

    assert_equal [0, CHANGED_AFTER], run.list(:doors)
    assert_includes saved.pool(:men, :hp), CHANGED_BEFORE, "a man was there to save"
    assert_equal saved.pool(:men, :hp), run.pool(:men, :hp), "and he is back in his own slot"
  end

  # --- the real game ---

  # EVERYTHING THE GAME DECLARES IS KEPT, OR LEFT OUT ON PURPOSE. A thing whose name has no
  # underscore lasts, and a save that missed one would load a game that is not the one saved: the
  # keys you carried, gone, or the lift's lever still down.
  #
  # The framework checks it while the cartridge is built (saves_keep_everything): every variable,
  # list and pool, and the random numbers, must be kept by a save record or named as left out, and
  # everything named as left out must be something the game declares. So the test is that the
  # whole game builds. Built over a cartridge holding one of every part that is only sometimes
  # there: a floor with a lift and a way out, the fixture's floor with a door, a locked door and
  # its key, a wall that slides and a guard, and the menus.
  def test_the_whole_game_keeps_everything_but_what_it_leaves_out_on_purpose
    assert whole_game, "it builds"
  end

  # A GAME SAVED PARTWAY THROUGH A FLOOR LOADS AS IT WAS SAVED. On the second floor, shoot the
  # guard, take the key, open a door and stand in it; save; turn the console off and on; load.
  # Everything kept is back as it was at the save, and each table is pointed at the second floor
  # again rather than at the first, which is where the console powers on.
  #
  # The world is held still while a test saves or loads (see #saving_cartridge), so what came back can
  # be held against the moment of the save. The original's LoadTheGame (wl_main.cpp) sets the
  # floor up and then reads the save over it; here the save is read first and the tables pointed
  # at its floor after, which comes to the same thing, because pointing them touches nothing the
  # save holds.
  def test_a_game_saved_on_the_second_floor_loads_as_it_was_saved
    program, names = saving_cartridge
    store = {}
    saved = Reference.new(save: store).input_each_frame { |f| presses_to_save(f) }.run(program, frames: SAVED_BY)
    loaded = Reference.new(save: store).input_each_frame { |f| presses_to_load(f) }
                      .run(program, frames: WRITTEN_BY)
    powered_on = Reference.new.input_each_frame { STILL }.run(program, frames: 2)

    assert_equal 1, saved[:floor], "the game was saved on the second floor"
    assert_operator saved.pool(:guard, :hp).compact.min, :<, Wolf3D::Guards::HIT_POINTS,
                    "with the guard shot"
    refute_equal 0, saved[:keys], "and the key taken"
    assert saved.list(:door_open).any?(&:positive?), "and a door open"
    before = kept_state(saved, names)
    after = kept_state(loaded, names)
    assert before == after, "these came back changed: #{differences(before, after)}"
    refute_equal cursors(powered_on), cursors(saved), "the second floor's tables are not the first's"
    assert_equal cursors(saved), cursors(loaded), "and they point at the second floor again"
  end

  # A GAME SAVED IN A DOORWAY LOADS WITH THE SAME ROOMS OPEN. A doorway is in no room, so the room
  # the player is in is remembered as the last one they were really in, and a load straight into
  # a doorway has nothing else to go on. Not saved, it would still be the room of whatever the
  # console was doing before the load: here, the first floor's. The original saves it too: the
  # player's areanumber goes into the save with the rest of the player (SaveTheGame).
  #
  # Read a pass after the save and a pass after the load, which is when the rooms are next worked
  # out. Which rooms are open does not depend on anything a pass of play can roll.
  def test_a_game_saved_in_a_doorway_loads_with_the_same_rooms_open
    program, = saving_cartridge
    store = {}
    saved = Reference.new(save: store).input_each_frame { |f| f == SAVED_BY ? [] : presses_to_save(f) }
                     .run(program, frames: SAVED_BY + 2)
    loaded = Reference.new(save: store).input_each_frame { |f| f == WRITTEN_BY ? [] : presses_to_load(f) }
                      .run(program, frames: WRITTEN_BY + 2)

    assert_equal DOORWAY_ROW, (saved[:py] / ONE).floor, "the game was saved in the doorway"
    assert_equal saved.list(:_room_open), loaded.list(:_room_open)
  end

  # --- what it refuses, while the cartridge is built ---

  # A NAME STARTING WITH AN UNDERSCORE is working room, or a thing worked out from the rest, and
  # this game never saves either. Declared lasting, one of the two is wrong.
  def test_an_underscore_name_is_refused
    error = refused { |lasting, _| lasting.var :_ray_x, 0 }

    assert_match(/_ray_x/, error.message)
  end

  # TWO THINGS OF ONE NAME are one thing to the framework, which would quietly put the second's
  # starting value over the first's.
  def test_a_name_declared_twice_is_refused
    error = refused do |lasting, _|
      lasting.var :keys, 0
      lasting.var :keys, 0
    end

    assert_match(/keys/, error.message)
  end

  # ONE RECORD HOLDS THE GAME. Handed a second, every save would hold half of it.
  def test_a_second_record_is_refused
    error = refused do |lasting, build|
      lasting.keep_in(build.save_data(:one, copies: 1))
      lasting.keep_in(build.save_data(:two, copies: 1))
    end

    assert_match(/one save record/, error.message)
  end

  private

  CHANGED_BEFORE = 7
  CHANGED_AFTER = 9

  # WHAT A TEST CAN DO, each on a button of its own.
  EVENTS = { change: :l, save: :a, load: :b }.freeze

  WRITTEN_BY = 20 # passes; a save is written a piece each pass

  # The small cartridge played through +events+, a pass apart, over the save memory +store+, and
  # then left long enough for any save to be written.
  def played(store, *events)
    presses = events.map { |event| EVENTS.fetch(event) }
    Reference.new(save: store).input_each_frame { |f| f.odd? ? [presses[f / 2]].compact : [] }
             .run(small_program, frames: (presses.length * 2) + WRITTEN_BY)
  end

  # Two values, one declared before the record is handed over and one after; and a list of two
  # doors and a pool of two men.
  def small_program
    @small_program ||= RubyGBA.game("KEEP") do
      screen :bitmap
      lasting = Wolf3D::LastingState.new(build: self)
      before = lasting.var :before, 0
      doors = lasting.list :doors, capacity: 2
      game = save_data :game, copies: 1
      lasting.keep_in(game)
      after = lasting.var :after, 0
      men = lasting.pool :men, hp: 0, capacity: 2
      2.times { doors << 0 }
      game_loop do
        pressed(EVENTS[:change]).then do
          before.set! CHANGED_BEFORE
          after.set! CHANGED_AFTER
          doors[1] = CHANGED_AFTER
          men.spawn(hp: CHANGED_BEFORE)
        end
        pressed(EVENTS[:save]).then { game[0].save }
        pressed(EVENTS[:load]).then { game[0].load }
      end
    end.program
  end

  # The error building a cartridge raises when +declaring+ is what it does with a LastingState.
  def refused(&declaring)
    assert_raises(ArgumentError) do
      RubyGBA.game("KEEP") do
        screen :bitmap
        declaring.call(Wolf3D::LastingState.new(build: self), self)
        game_loop { nil }
      end.program
    end
  end

  # --- the real game's cartridges ---

  FP = Wolf3D::FirstPerson

  # WHAT THE ROUND TRIP'S TEST BUTTONS DO, all with both shoulders held: the world stands still
  # while they are, so nothing but the test's own action happens on that pass, and nothing at all
  # on the passes after it while they stay held.
  NEW_GAME = %i[l r a].freeze # a new game on the second floor
  SAVE = %i[l r b].freeze
  LOAD = %i[l r select].freeze
  STILL = %i[l r].freeze

  QUARTER_TURN = ((FP::TURN / 4) / FP::TURN_SPEED.to_f).ceil
  ONE = (1 << Fraction::DEFAULT_BITS).to_f

  # The fixture's room, which the second floor is: the player starts in the middle facing north,
  # the key is one cell ahead, the guard two cells to the east facing away, and a door is in the
  # middle of the south wall.
  MIDDLE = Wolf3D::Fixture::Release::GRID / 2
  DOORWAY_ROW = MIDDLE + Wolf3D::Fixture::Release::ROOM

  # HOW LONG EACH PART OF THE WALK TAKES, in passes, and each is generous: one more pass walking
  # into a wall or a shut door changes nothing.
  SHOT_LANDS = 4 * Wolf3D::Weapons::STAGE_PASSES # a pistol's four stages, one round
  OVER_THE_KEY = 20 # backing a cell and more
  TO_THE_DOOR = 70 # from the key to the shut door, and stopped against it
  INTO_THE_DOORWAY = 26 # through a door as it opens, and no further

  # WHAT THE PLAYER DOES ON THE SECOND FLOOR, a pass at a time, and then saves: turn to face the
  # guard and shoot him, turn on to face the door, back over the key, walk to the door, open it,
  # and stop in the doorway.
  PLAYED = [[], NEW_GAME] + ([[:right]] * QUARTER_TURN) + [[:b]] + ([[]] * SHOT_LANDS) +
           ([[:right]] * QUARTER_TURN) + ([[:down]] * OVER_THE_KEY) + ([[:up]] * TO_THE_DOOR) +
           [%i[up a]] + ([[:up]] * INTO_THE_DOORWAY) + [SAVE]
  SAVED_BY = PLAYED.length + WRITTEN_BY

  def presses_to_save(pass) = PLAYED[pass] || STILL
  def presses_to_load(pass) = pass == 1 ? LOAD : STILL

  # THE CARTRIDGE THE ROUND TRIP PLAYS: the whole view over the two floors, its LastingState
  # handed to a save record, and test buttons to start a new game on the second floor, to save
  # and to load. With the names it keeps.
  def saving_cartridge
    @saving_cartridge ||= begin
      floors = two_floors
      atlas, things = atlases_of(floors)
      names = []
      program = RubyGBA.game("SAVED") do
        screen :bitmap, tear_free: true
        view = Wolf3D::FirstPerson.new(build: self, floors: floors, atlas: atlas, things: things)
        game = save_data :game, copies: 1
        view.lasting.keep_in(game)
        names.concat(view.lasting.names)
        game_loop do
          (held(:l) & held(:r)).then do
            pressed(:a).then { view.playthrough.start(:new_game, floor: 1) }
            pressed(:b).then { game[0].save }
            pressed(:select).then do
              game[0].load
              view.playthrough.start(:resume)
            end
          end.else { view.update }
        end
      end.program
      [program, names]
    end
  end

  # Everything +names+ holds in +run+, by name: a variable's value, a list's items, and every field
  # of every slot of the guards.
  def kept_state(run, names)
    names.to_h do |name|
      value = if run.vars.key?(name) then run[name]
              elsif name == :guard then GUARD_FIELDS.to_h { |field| [field, run.pool(:guard, field)] }
              else run.list(name)
              end
      [name, value]
    end
  end

  GUARD_FIELDS = %i[x y dir state ticks wait togo hp shown awake turn dropped ambush].freeze

  def differences(one, other) = one.keys.reject { |name| one[name] == other[name] }

  # WHERE THE FLOOR BEING PLAYED HAS ITS SLICE OF EACH TABLE: of the map, the doors, the walls
  # that slide, the guards and the things lying about, and which cell is its secret lift. None of
  # them is kept; each is worked out again from which floor it is.
  CURSORS = %i[_map_base _door_first _door_count _push_first _push_count _guard_first
               _guard_count _piece_first _piece_count _secret_car].freeze

  def cursors(run) = CURSORS.map { |name| run[name] }

  # THE WHOLE GAME, wired the way the real cartridge wires it, with a save record that keeps what
  # its LastingState holds and the framework's check that nothing else is left out by accident.
  def whole_game
    floors = two_floors
    art = Wolf3D::MenuArt.of(release.pictures)
    atlas, things = atlases_of(floors)
    RubyGBA.game("SAVED") do
      screen :bitmap, tear_free: true
      sound_on = var :sound_on, 1
      view = Wolf3D::FirstPerson.new(build: self, floors: floors, atlas: atlas, things: things,
                                     sound_on: sound_on)
      menus = Wolf3D::Menus.new(build: self, view: view, art: art, palette: Wolf3D::Palette.game,
                                sound_on: sound_on)
      view.lasting.keep_in(save_data(:game, copies: 1))
      saves_keep_everything except: Wolf3D::LastingState::LEFT_OUT.keys
      game_loop { menus.update }
    end.program
  end

  # A release whose walls reach as far as the lift's lever, pulled and not, and which has the
  # menus' pictures.
  def release
    @release ||= Wolf3D::Fixture::Release.new(set: "WL6", walls: (Wolf3D::Elevator::PULLED * 2) + 2)
  end

  def vswap = @vswap ||= Wolf3D::Vswap.new(release.files["VSWAP"])

  # The floor with a lift and a way out, and then the fixture's floor: a door, a locked door and
  # its key, a wall that slides, and a guard.
  def two_floors
    @two_floors ||= Wolf3D::Floors.new(
      [lift_floor, fixture_level].each_with_index.map do |level, n|
        Wolf3D::Floors::Floor.new(index: n, level: level, doors: Wolf3D::Doors.new(level, vswap),
                                  pushwalls: Wolf3D::Pushwalls.new(level),
                                  lifts: Wolf3D::Elevator.new(level), guards: Wolf3D::Guards.new(level),
                                  scenery: Wolf3D::Scenery.new(level))
      end
    )
  end

  def atlases_of(floors)
    palette = Wolf3D::Palette.game
    [Wolf3D::WallAtlas.new(vswap, palette, floors.map(&:level), doors: floors.map(&:doors),
                                                                lifts: floors.map(&:lifts)),
     Wolf3D::ThingAtlas.new(vswap, palette,
                            floors.flat_map { |f| f.guards.pictures + f.scenery.pictures }.uniq.sort)]
  end

  def fixture_level
    Wolf3D::Maps.new(maphead: release.files["MAPHEAD"], gamemaps: release.files["GAMEMAPS"])[0]
  end

  # Every floor of a cartridge is the same size, so this one is the fixture's.
  GRID = Wolf3D::Fixture::Release::GRID
  ROOM = 6 # cells across each of the lift floor's two rooms, and down the first

  # Two small rooms in the corner of the map, one above the other with a door between, which is
  # what makes the game build its rooms at all. The upper one has a lift's lever in its east wall,
  # the way out on its floor, the player, and a guard: dying needs something that can kill you on
  # the floor a cartridge boots on.
  def lift_floor
    cells = Array.new(GRID * GRID, Wolf3D::Fixture::Release::WALL)
    things = Array.new(GRID * GRID, 0)
    at = ->(x, y) { (y * GRID) + x }
    (1..ROOM).each do |x|
      (1..ROOM).each { |y| cells[at.call(x, y)] = Wolf3D::Level::FLOOR }
      (ROOM + 2..(2 * ROOM) + 1).each { |y| cells[at.call(x, y)] = Wolf3D::Level::FLOOR + 1 }
    end
    cells[at.call(3, ROOM + 1)] = Wolf3D::Level::DOORS.first
    cells[at.call(ROOM + 1, 2)] = Wolf3D::Elevator::SWITCH
    things[at.call(3, 2)] = Wolf3D::Level::FACINGS.key(:east)
    things[at.call(1, 2)] = Wolf3D::Level::EXIT
    things[at.call(5, 5)] = Wolf3D::Guards::STANDING + Wolf3D::Guards::FACINGS.index(:south)
    Wolf3D::Level.new(name: "Lift", width: GRID, height: GRID, walls: cells, things: things)
  end
end
