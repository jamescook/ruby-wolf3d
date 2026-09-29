# frozen_string_literal: true

require_relative "test_helper"

# MORE THAN ONE FLOOR IN ONE CARTRIDGE.
#
# Everything the renderer reads is a table built into the ROM, and all of it used to be built for
# one floor and read from nought. Now every table holds all the floors end to end and a number set
# when a floor starts says where this one's slice begins. These are the tests that the number is
# right — which mostly means asserting that a floor is DIFFERENT from the one before it, because
# the failure this design has is reading the first floor's data for ever.
class TestFloors < Minitest::Test
  include Wolf3DTest

  FP = Wolf3D::FirstPerson
  EL = Wolf3D::Elevator
  Release = Wolf3D::Fixture::Release

  SIDE = 16
  FLOOR = Wolf3D::Level::FLOOR
  WALL = Release::WALL

  WALLS = (EL::PULLED * 2) + 2

  # The cross, in the original's own list of pieces. Scenery::BONUSES says what it is worth.
  CROSS = 29
  GOLD_KEY = Wolf3D::Scenery::GOLD_KEY

  def setup
    @vswap = Wolf3D::Vswap.new(Release.new(walls: WALLS).files["VSWAP"])
  end

  # A room with a lift, and the player standing in the car facing east at the lever. +start+ says
  # where the player stands, so two floors can be told apart by where you arrive.
  #
  # +in_the_car+ lays that piece in the car instead and starts the player one cell back from it,
  # so walking up to the lever picks it up.
  def a_floor(name:, start_x:, start_y:, secret_car: false, lift: true, door_at: nil,
              in_the_car: nil)
    cells = Array.new(SIDE * SIDE, FLOOR + 1)
    things = Array.new(SIDE * SIDE, 0)
    SIDE.times do |y|
      SIDE.times do |x|
        edge = x.zero? || y.zero? || x == SIDE - 1 || y == SIDE - 1
        cells[(y * SIDE) + x] = WALL if edge
      end
    end
    if lift
      cells[(start_y * SIDE) + start_x + 1] = EL::SWITCH
      cells[(start_y * SIDE) + start_x] = secret_car ? EL::SECRET_CAR : FLOOR + 1
    end
    cells[(door_at[1] * SIDE) + door_at[0]] = Wolf3D::Level::DOORS.first if door_at
    player = in_the_car ? start_x - 1 : start_x
    things[(start_y * SIDE) + player] = Wolf3D::Level::FACINGS.key(:east)
    things[(start_y * SIDE) + start_x] = Wolf3D::Scenery::FIRST_CODE + in_the_car if in_the_car
    Wolf3D::Level.new(name: name, width: SIDE, height: SIDE, walls: cells, things: things)
  end

  def floors_of(*levels)
    Wolf3D::Floors.new(levels.each_with_index.map do |level, index|
      Wolf3D::Floors::Floor.new(index: index, level: level,
                                doors: Wolf3D::Doors.new(level, @vswap),
                                pushwalls: Wolf3D::Pushwalls.new(level),
                                lifts: EL.new(level),
                                guards: nil, scenery: nil)
    end)
  end

  def program(floors, drawing: false)
    atlas = Wolf3D::WallAtlas.new(@vswap, Wolf3D::Palette.game, floors.map(&:level),
                                  doors: floors.map(&:doors), lifts: floors.map(&:lifts))
    RubyGBA.game("FLOORS") do
      screen :bitmap, tear_free: true
      view = FP.new(build: self, floors: floors, atlas: atlas)
      game_loop { drawing ? view.update : view.play }
    end.program
  end

  # Pull the lever and run on long enough for the lift to arrive.
  def take_the_lift(floors, frames: FP::LIFT_WAIT + 10, press: 2)
    Reference.new.input_each_frame { |f| f == press ? [:a] : [] }
             .run(program(floors), frames: frames)
  end

  def at(run) = [run[:px] / (1 << Fraction::DEFAULT_BITS).to_f,
                 run[:py] / (1 << Fraction::DEFAULT_BITS).to_f]

  # --- what a cartridge of floors is ---

  def test_the_floors_are_held_end_to_end
    floors = floors_of(a_floor(name: "one", start_x: 4, start_y: 8),
                       a_floor(name: "two", start_x: 9, start_y: 3))

    assert_equal 2, floors.count
    assert_equal 0, floors.map_base(0)
    assert_equal SIDE * SIDE, floors.map_base(1), "the second floor's cells start after the first's"
  end

  def test_floors_of_different_sizes_are_a_friendly_error
    small = Wolf3D::Level.new(name: "small", width: 8, height: 8,
                              walls: Array.new(64, FLOOR), things: Array.new(64, 0))
    error = assert_raises(ArgumentError) do
      floors_of(a_floor(name: "one", start_x: 4, start_y: 8), small)
    end

    assert_match(/same size/, error.message)
  end

  # --- taking the lift ---

  def test_the_lift_takes_you_to_the_next_floor
    floors = floors_of(a_floor(name: "one", start_x: 4, start_y: 8),
                       a_floor(name: "two", start_x: 9, start_y: 3))
    run = take_the_lift(floors)

    assert_equal 1, run[:floor], "the second floor"
    assert_equal [9.5, 3.5], at(run), "and standing where THAT floor starts you, not this one"
  end

  # The number that makes the whole thing work: where in the map table this floor's cells begin.
  # Read the first floor's map on the second and every wall is in the wrong place.
  def test_the_map_moves_with_the_floor
    floors = floors_of(a_floor(name: "one", start_x: 4, start_y: 8),
                       a_floor(name: "two", start_x: 9, start_y: 3))
    run = take_the_lift(floors)

    assert_equal SIDE * SIDE, run[:_map_base], "the second floor's slice of the map"
  end

  # A floor with a door and one without: the count of doors has to follow the floor, or the
  # second floor walks a list of doors that are not there.
  def test_the_doors_move_with_the_floor
    floors = floors_of(a_floor(name: "one", start_x: 4, start_y: 8),
                       a_floor(name: "two", start_x: 9, start_y: 3, door_at: [5, 3]))

    before = Reference.new.run(program(floors), frames: 3)
    after = take_the_lift(floors)

    assert_equal 0, before[:_door_count], "the first floor has no door"
    assert_equal 1, after[:_door_count], "the second has one"
    assert_equal 0, after[:_door_first], "and it is the first door in the cartridge"
  end

  # --- what you carry down the lift ---
  #
  # FINISHING A FLOOR TAKES YOUR KEYS AND NOTHING ELSE OF YOURS. In the original that is the
  # ex_completed branch of GameLoop (wl_game.cpp): `gamestate.keys = 0`, the tally, and on to the
  # next map — health, ammunition, guns, lives and score are left exactly as they were, and only
  # SetupGameLevel's per-floor counts start again. It is dying that hands you a fresh player.

  def two_floors = floors_of(a_floor(name: "one", start_x: 4, start_y: 8),
                             a_floor(name: "two", start_x: 9, start_y: 3))

  # One shot on the first floor, then the lever once the gun is at rest again.
  def shoot_then_take_the_lift(floors)
    lever = Wolf3D::Weapons::CYCLE + 4
    Reference.new.input_each_frame { |f| { 2 => [:b], lever => [:a] }.fetch(f, []) }
             .run(program(floors), frames: lever + FP::LIFT_WAIT + 10)
  end

  def test_a_round_spent_on_one_floor_is_still_spent_on_the_next
    run = shoot_then_take_the_lift(two_floors)

    assert_equal 1, run[:floor], "on the second floor"
    assert_equal FP::START_AMMO - 1, run[:ammo], "with the round the first floor cost you still gone"
  end

  # ...and the weapon in your hands. SELECT from the pistol wraps round to the knife, which is the
  # one weapon a fresh player is never holding — so still holding it on the next floor is the
  # lift leaving it alone rather than handing you the pistol back.
  def test_the_weapon_in_your_hands_goes_down_the_lift_too
    lever = 10
    run = Reference.new.input_each_frame { |f| { 2 => [:select], lever => [:a] }.fetch(f, []) }
                       .run(program(two_floors), frames: lever + FP::LIFT_WAIT + 10)

    assert_equal 1, run[:floor], "on the second floor"
    assert_equal Wolf3D::Weapons::NUMBERS.fetch(:knife), run[:weapon], "still holding the knife"
  end

  # A floor with +piece+ lying in the lift car, and a second floor to go to.
  def a_piece_in_the_car(piece) = floors_of(a_floor(name: "one", start_x: 4, start_y: 8, in_the_car: piece),
                                            a_floor(name: "two", start_x: 9, start_y: 3))

  # Walk into the car over whatever lies in it, and — unless +lever+ is false — pull the lever
  # and ride down.
  def walk_into_the_car(floors, lever: true)
    walked = (1 / FP::WALK).ceil + 4
    frames = lever ? walked + FP::LIFT_WAIT + 12 : walked
    Reference.new.input_each_frame { |f| f < walked ? [:up] : (f == walked + 2 ? [:a] : []) }
             .run(program(floors), frames: frames)
  end

  # ...AND SO DO THE POINTS. Finishing a floor moves the score the next one puts back to
  # (`gamestate.oldscore = gamestate.score` in the same branch), so what you scored comes with you.
  def test_the_points_scored_on_one_floor_are_still_yours_on_the_next
    run = walk_into_the_car(a_piece_in_the_car(CROSS))
    worth = Wolf3D::Scenery::BONUSES.fetch(CROSS).last

    assert_equal 1, run[:floor], "on the second floor"
    assert_equal worth, run[:score], "with the cross picked up on the first still counted"
    assert_equal 0, run[:treasures], "while the count of this floor's treasures starts again"
  end

  # THE KEYS ARE THE ONE THING THAT STAYS BEHIND: `gamestate.keys = 0` is the first thing that
  # branch does. A key opens a door on the floor it was found on, and on no other.
  def test_a_key_found_on_one_floor_does_not_go_down_the_lift
    floors = a_piece_in_the_car(GOLD_KEY)
    holding = walk_into_the_car(floors, lever: false)
    arrived = walk_into_the_car(floors)

    assert_operator holding[:keys], :>, 0, "walking into the car should have picked the key up"
    assert_equal 1, arrived[:floor], "on the second floor"
    assert_equal 0, arrived[:keys], "with no keys"
  end

  # --- where the lift goes ---

  # A whole episode: the secret lever goes to the floor kept aside for it, which the original
  # makes the last of the ten.
  def an_episode(secret_car_on_first: false)
    floors_of(*10.times.map do |n|
      a_floor(name: "floor#{n}", start_x: 4, start_y: 2 + n,
              secret_car: secret_car_on_first && n.zero?)
    end)
  end

  def test_the_secret_lever_goes_to_the_floor_kept_aside
    plain = take_the_lift(an_episode)
    secret = take_the_lift(an_episode(secret_car_on_first: true))

    assert_equal 1, plain[:floor], "an ordinary lever goes to the next floor"
    assert_equal FP::SECRET_FLOOR, secret[:floor], "a secret one goes to the last of the ten"
  end

  # ...and the lever on THAT floor puts you back on the normal run rather than one further along
  # it, which is the original's own rule and the reason it keeps a table of where to come back to.
  #
  # Two rides in one run: the secret lever on the first floor, then the ordinary lever waiting on
  # the secret floor when you arrive.
  def test_the_lever_on_the_secret_floor_comes_back_to_the_normal_run
    program = program(an_episode(secret_car_on_first: true))
    again = FP::LIFT_WAIT + 20
    two_rides = Reference.new.input_each_frame { |f| [2, again].include?(f) ? [:a] : [] }

    there = two_rides.run(program, frames: FP::LIFT_WAIT + 10)
    back = Reference.new.input_each_frame { |f| [2, again].include?(f) ? [:a] : [] }
                   .run(program, frames: again + FP::LIFT_WAIT + 10)

    assert_equal FP::SECRET_FLOOR, there[:floor], "the secret lever took you to the last floor"
    assert_equal FP::BACK_FROM_SECRET, back[:floor],
                 "and the lever there puts you back on the normal run, not one further along it"
  end

  # A cartridge shorter than an episode has NO secret floor, so every lever simply goes to the
  # next one. Clamping the rule to a floor it does have was tried and is wrong: the floor a
  # missing one clamps to is the first, which makes "coming back from the secret floor" true at
  # the start of every game.
  def test_a_short_cartridge_has_no_secret_floor_and_every_lever_goes_on
    secret = floors_of(a_floor(name: "one", start_x: 4, start_y: 8, secret_car: true),
                       a_floor(name: "two", start_x: 9, start_y: 3))

    assert_equal 1, take_the_lift(secret)[:floor]
  end

  # A cartridge that runs out of floors goes round rather than stopping on a lever that does
  # nothing. It is not the original's behaviour — the original ends the episode — and there is
  # nowhere to put an ending yet.
  def test_the_last_floor_goes_back_to_the_first
    floors = floors_of(a_floor(name: "one", start_x: 4, start_y: 8),
                       a_floor(name: "two", start_x: 9, start_y: 3))
    twice = take_the_lift(floors, frames: (FP::LIFT_WAIT * 2) + 30, press: 2)

    assert_equal 1, twice[:floor], "still on the second: one lever, one ride"
  end

  # --- a floor with one floor in it is unchanged ---

  def test_a_cartridge_with_one_floor_reads_from_nought
    floors = floors_of(a_floor(name: "only", start_x: 4, start_y: 8))
    run = take_the_lift(floors)

    assert_equal 0, run[:floor]
    assert_equal 0, run[:_map_base]
    assert_equal [4.5, 8.5], at(run), "back at the start of the same floor"
  end
end
