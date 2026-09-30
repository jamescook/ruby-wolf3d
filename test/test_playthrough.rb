# frozen_string_literal: true

require_relative "test_helper"

# STARTING PLAY, for each of the reasons play starts: a new game, another life after a death,
# and the next floor at the bottom of the lift.
#
# What each reason puts back, and in what order, is the whole of the playthrough's job; doing
# the putting back belongs to the parts of the game that own each thing. So these tests hand it
# a world that does nothing but COUNT: each step it is asked for writes its own number onto the
# end of a trail, and the trail read back says which steps ran and in what order. What the steps
# really do to a floor is tested against the real view, in test_lives.rb and test_floors.rb.
class TestPlaythrough < Minitest::Test
  include Wolf3DTest

  Playthrough = Wolf3D::Playthrough

  # THE SECOND WORLD, beside the real view. Each step appends its number, one to five, to the
  # trail: another life that ran steps two and four and nothing else reads 24.
  class CountingWorld
    STEPS = %i[reset_game reset_player select_floor place_player reset_floor].freeze

    def initialize(build)
      @trail = build.var :trail, 0
    end

    def reset_game = step(:reset_game)
    def reset_player = step(:reset_player)
    def select_floor = step(:select_floor)
    def place_player = step(:place_player)
    def reset_floor = step(:reset_floor)

    private

    def step(name) = @trail.set!((@trail * 10) + STEPS.index(name) + 1)
  end

  # --- which steps each reason runs, and in what order ---

  def test_another_life_resets_the_player_and_the_floor
    run = played(:death)

    assert_equal trail_of(:reset_player, :select_floor, :place_player,
                          :reset_floor), run[:trail]
  end

  # A NEW GAME is another life with the game's own counts put back first: the lives and whether
  # an episode was won (wl_main.cpp, NewGame, which zeroes the whole of gamestate).
  def test_a_new_game_resets_the_game_before_the_player
    run = played(:new_game)

    assert_equal trail_of(:reset_game, :reset_player, :select_floor, :place_player,
                          :reset_floor), run[:trail]
  end

  # THE NEXT FLOOR hands you no fresh player: health, ammunition and guns go down the lift with you
  # (wl_game.cpp, GameLoop's ex_completed branch).
  def test_the_next_floor_leaves_the_player_alone
    run = played(:lift, count: 2)

    assert_equal trail_of(:select_floor, :place_player, :reset_floor), run[:trail]
    assert_equal 1, run[:floor], "on the second floor"
  end

  # --- the score ---
  #
  # The original keeps two scores: the one on the bar, and `oldscore`, the one you walked onto the
  # floor with. Every floor starts with `gamestate.score = gamestate.oldscore` (wl_game.cpp, the
  # top of GameLoop's loop), and only finishing a floor moves oldscore on (`gamestate.oldscore =
  # gamestate.score`, the ex_completed branch). NewGame zeroes both (wl_main.cpp).

  def test_a_death_takes_back_the_points_scored_on_the_floor
    run = played(:score, :lift, :score, :score, :death, count: 2)

    assert_equal POINTS, run[:score], "what the first floor scored, and nothing of the second's"
  end

  def test_the_lift_keeps_the_points
    run = played(:score, :lift, count: 2)

    assert_equal POINTS, run[:score]
  end

  # ...and a new game zeroes BOTH, which takes two readings to see: the score on the bar, and the
  # one the new game's first death would put back.
  def test_a_new_game_starts_the_score_from_nothing
    begun = played(:score, :lift, :score, :new_game, count: 2)
    then_died = played(:score, :lift, :score, :new_game, :score, :death, count: 2)

    assert_equal 0, begun[:score]
    assert_equal 0, then_died[:score], "not the score the last game walked onto a floor with"
  end

  # --- which floor ---

  # THE MENU PICKS THE FLOOR: the first of the episode you chose, which it writes into a variable
  # of its own before the game starts. In the original, NewGame clears the whole of gamestate
  # (wl_main.cpp, `memset (&gamestate,0,sizeof(gamestate))`), so the floor is the first of
  # `gamestate.episode`.
  def test_a_new_game_begins_on_the_floor_it_is_asked_for
    run = played(:new_game, on: 2, count: 3)

    assert_equal 2, run[:floor]
  end

  # ...AND START AFTER A GAME ENDS BEGINS ANOTHER WHERE THAT ONE BEGAN, not on the floor it ended
  # on. The original has no such restart: GameLoop's ex_died and ex_victorious branches
  # (wl_game.cpp) end with `return`, back to the menus, where NEW GAME begins on the first floor of
  # an episode. So a cartridge without the menus begins again on that same floor.
  def test_starting_again_begins_where_the_last_game_began
    run = played(:new_game, :lift, :again, on: 1, count: 3)

    assert_equal 1, run[:floor]
  end

  # --- where the lift goes ---
  #
  # Read off the original (wl_game.cpp, GameLoop's ex_completed branch), and tested there in this
  # order: coming back from the secret floor, then going to it, then the next floor along.

  def test_the_secret_lever_goes_to_the_floor_kept_aside
    plain = played(:lift, count: EPISODE)
    secret = played(:secret_lift, count: EPISODE)

    assert_equal 1, plain[:floor], "an ordinary lever goes to the next floor"
    assert_equal Playthrough::SECRET_FLOOR, secret[:floor], "a secret one goes to the last of the ten"
  end

  # ...and the lever on THAT floor puts you back on the normal run rather than one further along
  # it, which is the original's own rule and the reason it keeps a table of where to come back to.
  def test_the_lever_on_the_secret_floor_comes_back_to_the_normal_run
    run = played(:secret_lift, :lift, count: EPISODE)

    assert_equal Playthrough::BACK_FROM_SECRET, run[:floor]
  end

  # A cartridge shorter than an episode has NO secret floor, so every lever simply goes to the
  # next one.
  def test_a_short_cartridge_has_no_secret_floor_and_every_lever_goes_on
    run = played(:secret_lift, count: 2)

    assert_equal 1, run[:floor]
  end

  # A cartridge that runs out of floors goes round rather than stopping on a lever that does
  # nothing. It is not the original's behaviour — the original ends the episode.
  def test_the_last_floor_goes_back_to_the_first
    run = played(:lift, :lift, count: 2)

    assert_equal 0, run[:floor]
  end

  def test_a_cartridge_of_one_floor_stays_on_it
    run = played(:lift)

    assert_equal 0, run[:floor]
  end

  # --- what it refuses, while the cartridge is built ---

  def test_a_reason_it_does_not_know_is_refused
    error = refused { |play| play.start(:continue) }

    assert_match(/another_life/, error.message, "and it says which reasons it knows")
  end

  # Only a new game begins on a floor you choose: another life is on the floor you died on, and
  # the lift decides where the next floor is.
  def test_a_floor_for_anything_but_a_new_game_is_refused
    error = refused { |play| play.start(:another_life, floor: 0) }

    assert_match(/new game/, error.message)
  end

  # ...and only the lift is called by a lever.
  def test_a_lever_for_anything_but_the_next_floor_is_refused
    error = refused { |play| play.start(:new_game, secret: 1) }

    assert_match(/lift/, error.message)
  end

  # A cartridge with a secret floor cannot choose the next floor without knowing which lever
  # called the lift, and left out it would quietly never go to the secret floor.
  def test_the_lift_must_say_which_lever_where_there_is_a_secret_floor
    error = refused(count: EPISODE) { |play| play.start(:next_floor) }

    assert_match(/secret floor/, error.message)
  end

  def test_a_floor_the_cartridge_does_not_hold_is_refused
    error = refused(count: 3) { |play| play.start(:new_game, floor: 3) }

    assert_match(/holds 3 floors/, error.message)
  end

  # --- in the real game ---

  # WINNING, THEN START, on a cartridge with no menus: START begins another game, and it is one
  # you can play. A new game puts back whether an episode was won, whichever way it is started;
  # left won, the world stays stopped under the words and the player cannot move.
  #
  # Walked backwards onto the way out behind you, so that walking forward afterwards moves you
  # away from it rather than winning again.
  def test_start_after_winning_begins_a_game_you_can_play
    run = Reference.new.input_each_frame do |f|
      next [:down] if f < WON_BY
      next [:start] if f == WON_BY + 10

      f > WON_BY + 20 ? [:up] : []
    end.run(program_of(way_out_level), frames: WON_BY + 50)

    assert_equal 0, run[:episode_won], "the new game has not been won"
    assert_operator run[:px] / ONE, :>, START_X + 0.5 + 0.5, "and the player walks"
  end

  # THE GAME AT POWER-ON IS A NEW GAME ON THE FIRST FLOOR. Nothing runs to start it — every
  # variable simply begins at the value it was declared with — so this is the test that those
  # values and what a new game writes agree.
  #
  # Read over two floors between them holding one of everything that changes: the fixture's, with
  # a door, a locked door and its key, a wall that slides and a guard; and one with a lift and a
  # way out, for the lever's state and whether an episode was won.
  def test_the_game_at_power_on_is_a_new_game_on_the_first_floor
    [fixture_level, way_out_level].each do |level|
      booted = state_of(at_power_on(level, new_game: false))
      begun = state_of(at_power_on(level, new_game: true))

      assert booted == begun, "on the floor #{level.name.inspect}, these differ: #{differences(booted, begun)}"
    end
  end

  private

  # Which of the things a state holds differ between two, by name.
  def differences(one, other)
    one.flat_map { |part, values| values.keys.reject { |name| values[name] == other[part][name] } }
  end

  FP = Wolf3D::FirstPerson

  # EVERYTHING THE GAME KEEPS: each variable but the framework's own, and each list and the
  # guards' pool by name.
  #
  # Less one: how many guards have stood up so far while a floor is filled, which is working room
  # for that and read by nothing after it.
  def state_of(run)
    vars = run.vars.reject { |name, _| name.to_s.start_with?("__") || name == :_stood }
    lists = LISTS.to_h { |name| [name, run.list(name)] }
    guards = GUARD_FIELDS.to_h { |field| [field, run.pool(:guard, field)] }
    { vars: vars, lists: lists, guards: guards }
  end

  LISTS = %i[door_open door_linger push_step push_gone push_wait thing_gone].freeze
  GUARD_FIELDS = %i[x y dir state ticks wait togo hp shown awake turn dropped ambush].freeze

  # +level+ with nothing played: the loop only begins a new game on A, if +new_game+.
  def at_power_on(level, new_game:)
    Reference.new.input_each_frame { |f| new_game && f == 1 ? [:a] : [] }
             .run(program_of(level, only_new_game: true), frames: 3)
  end

  # A cartridge of +level+ alone, with every part of the view a floor can hold read off it. Its
  # loop plays and draws the floor, or with +only_new_game+ does nothing but begin a new game on A.
  def program_of(level, only_new_game: false)
    @programs ||= {}
    @programs[[level.name, only_new_game]] ||= begin
      doors = Wolf3D::Doors.new(level, vswap)
      lifts = Wolf3D::Elevator.new(level)
      guards = Wolf3D::Guards.new(level)
      scenery = Wolf3D::Scenery.new(level)
      atlas = Wolf3D::WallAtlas.new(vswap, Wolf3D::Palette.game, level, doors: doors, lifts: lifts)
      things = Wolf3D::ThingAtlas.new(vswap, Wolf3D::Palette.game,
                                      (guards.pictures + scenery.pictures).uniq.sort)
      RubyGBA.game("VIEW") do
        screen :bitmap, tear_free: true
        view = FP.new(build: self, level: level, atlas: atlas, doors: doors, lifts: lifts,
                      pushwalls: Wolf3D::Pushwalls.new(level), guards: guards, things: things,
                      scenery: scenery)
        game_loop do
          if only_new_game
            pressed(:a).then { view.playthrough.start(:new_game, floor: 0) }
          else
            view.update
          end
        end
      end.program
    end
  end

  # The player stands facing east, and the way out is the cell behind them.
  START_X = 4
  ROW = 4
  SIDE = 16
  WON_BY = 20 # passes of walking backwards, which is further than one cell
  ONE = (1 << Fraction::DEFAULT_BITS).to_f

  # A release whose walls reach as far as the lift's lever, pulled and not.
  def fixture = @fixture ||= Wolf3D::Fixture::Release.new(walls: (Wolf3D::Elevator::PULLED * 2) + 2)
  def vswap = @vswap ||= Wolf3D::Vswap.new(fixture.files["VSWAP"])

  def fixture_level
    @fixture_level ||= Wolf3D::Maps.new(maphead: fixture.files["MAPHEAD"],
                                        gamemaps: fixture.files["GAMEMAPS"])[0]
  end

  # A room with the way out behind the player and a lift's lever in the far wall, and a guard shut
  # in a room of his own below it. The guard is there because a game needs something that can kill
  # you before it counts lives at all, and it is the count of lives that answers START.
  def way_out_level
    @way_out_level ||= begin
      cells = Array.new(SIDE * SIDE, Wolf3D::Level::FLOOR)
      things = Array.new(SIDE * SIDE, 0)
      SIDE.times do |y|
        SIDE.times do |x|
          wall = x.zero? || y.zero? || x == SIDE - 1 || y == SIDE - 1 || y == SIDE / 2
          cells[(y * SIDE) + x] = Wolf3D::Fixture::Release::WALL if wall
        end
      end
      cells[(2 * SIDE) + SIDE - 1] = Wolf3D::Elevator::SWITCH
      things[(ROW * SIDE) + START_X] = Wolf3D::Level::FACINGS.key(:east)
      things[(ROW * SIDE) + START_X - 1] = Wolf3D::Level::EXIT
      things[(12 * SIDE) + 10] = Wolf3D::Guards::STANDING + Wolf3D::Guards::FACINGS.index(:south)
      Wolf3D::Level.new(name: "Way out", width: SIDE, height: SIDE, walls: cells, things: things)
    end
  end

  # The error building a cartridge raises when +asking+ is what it asks of the playthrough.
  def refused(count: 1, &asking)
    floors = floors_of(count)
    assert_raises(ArgumentError) do
      RubyGBA.game("PLAY") do
        screen :bitmap
        play = Playthrough.new(build: self, floors: floors, score: var(:score, 0),
                               world: CountingWorld.new(self))
        game_loop { asking.call(play) }
      end.program
    end
  end

  EPISODE = Wolf3D::Floors::PER_EPISODE

  # WHAT A TEST CAN DO, each on a button of its own: score some points, or start play for one of
  # the reasons. A test says what happens in the order it happens. :new_game is the menu's, which
  # says which floor; :again is START after a game has ended, which does not. :secret_lift is the
  # lift a secret lever calls.
  EVENTS = { score: :l, new_game: :a, again: :start, death: :b, lift: :r, secret_lift: :select }.freeze
  POINTS = 100 # what one :score is worth

  # What the trail reads after +steps+, in that order.
  def trail_of(*steps) = steps.reduce(0) { |trail, step| (trail * 10) + CountingWorld::STEPS.index(step) + 1 }

  # A cartridge of +count+ floors over the counting world, played through +events+ one after
  # another, and read a pass after the last of them. A pass with nothing pressed between each, so
  # every press is a fresh one.
  #
  # +on+ is the floor a :new_game is asked to begin on, written into a variable the way the menu
  # writes it; nil asks for none.
  def played(*events, count: 1, on: nil)
    presses = events.map { |event| EVENTS.fetch(event) }
    Reference.new.input_each_frame { |f| f.odd? ? [presses[f / 2]].compact : [] }
             .run(counting_program(count, on), frames: (presses.length * 2) + 2)
  end

  def counting_program(count, on)
    floors = floors_of(count)
    @counting_programs ||= {}
    @counting_programs[[count, on]] ||= RubyGBA.game("PLAY") do
      screen :bitmap
      score = var :score, 0
      picked = on && var(:picked, on)
      secret = var :secret, 0
      play = Playthrough.new(build: self, floors: floors, score: score, world: CountingWorld.new(self))
      game_loop do
        pressed(EVENTS[:score]).then { score.add! POINTS }
        pressed(EVENTS[:new_game]).then { play.start(:new_game, floor: picked) }
        pressed(EVENTS[:again]).then { play.start(:new_game) }
        pressed(EVENTS[:death]).then { play.start(:another_life) }
        pressed(EVENTS[:lift]).then { secret.set! 0; play.start(:next_floor, secret: secret) }
        pressed(EVENTS[:secret_lift]).then { secret.set! 1; play.start(:next_floor, secret: secret) }
      end
    end.program
  end

  # +count+ floors with nothing on them. The playthrough asks a cartridge's floors only how many
  # there are, so an empty room will do for every one.
  def floors_of(count)
    Wolf3D::Floors.new(Array.new(count) do |n|
      Wolf3D::Floors::Floor.new(index: n, level: empty, doors: nil, pushwalls: nil, lifts: nil,
                                guards: nil, scenery: nil)
    end)
  end

  def empty = Wolf3D::Level.new(name: "empty", width: 4, height: 4,
                                walls: Array.new(16, Wolf3D::Level::FLOOR), things: Array.new(16, 0))
end
