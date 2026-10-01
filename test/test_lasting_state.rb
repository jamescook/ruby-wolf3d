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

  # EVERYTHING THE GAME DECLARES IS KEPT, OR LEFT OUT ON PURPOSE. A variable whose name has no
  # underscore lasts, and a save that missed one would load a game that is not the one saved:
  # the keys you carried, gone, or the lift's lever still down.
  #
  # Read over a cartridge holding one of every part that is only sometimes there: a floor with a
  # lift and a way out, the fixture's floor with a door, a locked door and its key, a wall that
  # slides and a guard, and the menus.
  def test_every_lasting_variable_is_kept_or_left_out_on_purpose
    names = []
    run = Reference.new.run(whole_game(names), frames: 1)
    lasting = run.vars.keys.reject { |name| name.start_with?("_") }
    missing = lasting - names - LastingState::LEFT_OUT.keys

    assert_empty missing, "A saved game does not keep these. Declare each through LastingState, " \
                          "or put it in LastingState::LEFT_OUT and say why."
    assert_empty LastingState::LEFT_OUT.keys - lasting, "and what is left out is all still declared"
  end

  # A GAME SAVED PARTWAY THROUGH A FLOOR LOADS AS IT WAS SAVED. On the second floor, take the key,
  # open a door and fire a shot that brings the guard round; save; turn the console off and on;
  # load. Everything kept is back as it was at the save, and each table is pointed at the second
  # floor again rather than at the first, which is where the console powers on.
  #
  # The world is held still while a test saves or loads (see #round_trip), so what came back can
  # be held against the moment of the save. The original's LoadTheGame (wl_main.cpp) is the same
  # three things in the same order: set the floor up, read the save over it, and work out again
  # what follows from where the player stands.
  def test_a_game_saved_on_the_second_floor_loads_as_it_was_saved
    program, names = round_trip
    store = {}
    saved = Reference.new(save: store).input_each_frame { |f| saving(f) }.run(program, frames: SAVED_BY)
    loaded = Reference.new(save: store).input_each_frame { |f| loading(f) }
                      .run(program, frames: WRITTEN_BY)
    powered_on = Reference.new.input_each_frame { STILL }.run(program, frames: 2)

    assert_equal 1, saved[:floor], "the game was saved on the second floor"
    refute_equal 0, saved[:keys], "with the key taken"
    assert saved.list(:door_open).any?(&:positive?), "and a door open"
    before = kept_state(saved, names)
    after = kept_state(loaded, names)
    assert before == after, "these came back changed: #{differences(before, after)}"
    refute_equal cursors(powered_on), cursors(saved), "the second floor's tables are not the first's"
    assert_equal cursors(saved), cursors(loaded), "and they point at the second floor again"
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

  ABOUT_TURN = ((FP::TURN / 2) / FP::TURN_SPEED.to_f).ceil

  # WHAT THE PLAYER DOES ON THE SECOND FLOOR, a pass at a time, and then saves. They start in the
  # fixture's room facing north with the key one cell ahead: turn to face the door behind, back
  # over the key, walk to the door and open it, fire once, and let the door start to move.
  PLAYED = [[], NEW_GAME] + ([[:left]] * ABOUT_TURN) + ([[:down]] * 20) + ([[:up]] * 69) +
           [%i[up a], [:b]] + ([[]] * 8) + [SAVE]
  SAVED_BY = PLAYED.length + WRITTEN_BY

  def saving(pass) = PLAYED[pass] || STILL
  def loading(pass) = pass == 1 ? LOAD : STILL

  # THE CARTRIDGE THE ROUND TRIP PLAYS: the whole view over the two floors, its LastingState
  # handed to a save record, and test buttons to start a new game on the second floor, to save
  # and to load. With the names it keeps.
  def round_trip
    @round_trip ||= begin
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
          end.else { view.play }
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

  # THE WHOLE GAME, wired the way the real cartridge wires it, with the names its LastingState
  # keeps written into +names+.
  def whole_game(names)
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
      names.concat(view.lasting.names)
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
      [a_floor_with_a_lift_and_a_way_out, fixture_level].each_with_index.map do |level, n|
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
  ROOM = 6

  # A small room in the corner of the map, with a lift's lever in its east wall, the way out on
  # its floor, and a guard. The guard is there because dying needs something that can kill you on
  # the floor a cartridge boots on.
  def a_floor_with_a_lift_and_a_way_out
    cells = Array.new(GRID * GRID, Wolf3D::Fixture::Release::WALL)
    things = Array.new(GRID * GRID, 0)
    (1..ROOM).each { |y| (1..ROOM).each { |x| cells[(y * GRID) + x] = Wolf3D::Level::FLOOR } }
    cells[(2 * GRID) + ROOM + 1] = Wolf3D::Elevator::SWITCH
    things[(2 * GRID) + 3] = Wolf3D::Level::FACINGS.key(:east)
    things[(2 * GRID) + 1] = Wolf3D::Level::EXIT
    things[(5 * GRID) + 5] = Wolf3D::Guards::STANDING + Wolf3D::Guards::FACINGS.index(:south)
    Wolf3D::Level.new(name: "Lift", width: GRID, height: GRID, walls: cells, things: things)
  end
end
