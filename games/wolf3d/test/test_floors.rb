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

  WALLS = (EL::PULLED * 2) + 2

  # The cross, in the original's own list of pieces. Scenery::BONUSES says what it is worth.
  CROSS = 29
  GOLD_KEY = Wolf3D::Scenery::GOLD_KEY

  def fixture = @fixture ||= Release.new(walls: WALLS)

  # A room with a lift, and the player standing in the car facing east at the lever. +start+ says
  # where the player stands, so two floors can be told apart by where you arrive.
  #
  # +in_the_car+ lays that piece in the car instead and starts the player one cell back from it,
  # so walking up to the lever picks it up.
  #
  # +guards+, +crosses+ and +secrets+ put that many of each along the bottom of the room, out of
  # the way: the guards facing the wall, so none of them sees a player who never goes near.
  # +harder+ adds that many guards who turn up only on the hardest setting.
  def a_floor(name:, start_x:, start_y:, secret_car: false, lift: true, door_at: nil,
              in_the_car: nil, guards: 0, harder: 0, crosses: 0, secrets: 0)
    cells = {}
    if lift
      cells[[start_x + 1, start_y]] = EL::SWITCH
      cells[[start_x, start_y]] = secret_car ? EL::SECRET_CAR : FLOOR + 1
    end
    cells[door_at] = Wolf3D::Level::DOORS.first if door_at
    things = {}
    things[[start_x, start_y]] = Wolf3D::Scenery::FIRST_CODE + in_the_car if in_the_car
    guards.times { |n| things[[2 + (2 * n), 13]] = FACING_THE_WALL }
    harder.times { |n| things[[2 + (2 * (guards + n)), 13]] = ONLY_ON_HARD }
    crosses.times { |n| things[[2 + (2 * n), 11]] = Wolf3D::Scenery::FIRST_CODE + CROSS }
    sliding = Array.new(secrets) { |n| [9 + (2 * n), 14] }
    sliding.each { |cell| things[cell] = Wolf3D::Level::PUSHWALL }
    arena(name: name, floor: FLOOR + 1, player: [in_the_car ? start_x - 1 : start_x, start_y],
          walls: sliding, cells: cells, things: things)
  end

  FACING_THE_WALL = Wolf3D::Guards::STANDING + Wolf3D::Guards::FACINGS.index(:south)
  # ...and the same man in the third block of his codes, which is the hardest setting's.
  ONLY_ON_HARD = FACING_THE_WALL + (2 * Wolf3D::Enemy::GUARD.harder)

  # +standing+ reads each floor's guards and scenery too, which most of these leave out: a floor
  # with nobody on it is a quicker game to play, and the lift does not care.
  def floors_of(*levels, standing: false) = super

  def program(floors, drawing: false) = cartridge_of(floors, drawing: drawing)

  # How long after the lever a lift has arrived and its screen is up, and so when pressing on
  # from that screen takes you to the next floor.
  PRESS_ON = FP::LIFT_WAIT + 4

  # What the first floor of an episode pays for being left inside its first second: every one of
  # its ninety seconds of par, at five hundred points each.
  WHOLE_PAR = 45_000

  # Leaving that screen is two presses: one finishes the figures and the other moves on. This says
  # when they fall after a lever pulled on frame +lever+.
  def leave_screen(lever) = [lever + PRESS_ON, lever + PRESS_ON + 2]

  # Pull the lever, ride the lift, and press on from the screen at the bottom of it.
  def take_the_lift(floors, frames: FP::LIFT_WAIT + 12, press: 2)
    Reference.new.input_each_frame { |f| [press, *leave_screen(press)].include?(f) ? [:a] : [] }
             .run(program(floors), frames: frames)
  end

  # ...and the same with no press to leave the screen, and +pressing+ held once the lift is in.
  def arrive_at_the_screen(floors, pressing: [], drawing: false, **)
    arrived = 2 + FP::LIFT_WAIT
    Reference.new.input_each_frame { |f| f == 2 ? [:a] : (f > arrived ? pressing : []) }
             .run(cartridge_of(floors, drawing: drawing, **), frames: PRESS_ON + 12)
  end

  def two_floors_with_a_lift
    floors_of(a_floor(name: "one", start_x: 4, start_y: 8), a_floor(name: "two", start_x: 9, start_y: 3))
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

  # --- the screen at the bottom of the lift ---
  #
  # What it adds up is in test_end_of_floor.rb. These are that the lift really stops there.

  def test_the_lift_stops_at_a_screen_rather_than_at_the_next_floor
    run = arrive_at_the_screen(two_floors_with_a_lift)

    assert_equal 1, run[:_tally_showing], "the screen is up"
    assert_equal 0, run[:floor], "and you are still on the first floor"
  end

  def test_nothing_moves_while_the_screen_is_up
    run = arrive_at_the_screen(two_floors_with_a_lift, pressing: [:down])

    assert_equal [4.5, 8.5], at(run), "standing where the lever left you, however long down is held"
  end

  # On the clock as well as on the pass: on that pacing the world moves outside the pass, so the
  # screen has to stop it there too.
  def test_nothing_moves_while_the_screen_is_up_on_the_clock_either
    run = arrive_at_the_screen(two_floors_with_a_lift, pressing: [:down], pacing: :by_the_frame)

    assert_equal 1, run[:_tally_showing]
    assert_equal [4.5, 8.5], at(run)
  end

  # THE LEVER STOPS THE WORLD, not the screen after it: Cmd_Use plays the lift's sound and waits for
  # it to finish (wl_agent.cpp) before anything else in the game runs. A world left running is a
  # guard shooting you dead in a lift that then carries the body down.
  def lever_then_down(pacing)
    Reference.new.input_each_frame { |f| f == 2 ? [:a] : (f > 2 ? [:down] : []) }
             .run(cartridge_of(two_floors_with_a_lift, drawing: false, pacing: pacing), frames: FP::LIFT_WAIT / 2)
  end

  def test_nothing_moves_while_the_lift_is_on_its_way
    run = lever_then_down(:by_the_pass)

    assert_operator run[:lift_wait], :>, 0, "the lift is still on its way"
    assert_equal [4.5, 8.5], at(run)
  end

  def test_nothing_moves_while_the_lift_is_on_its_way_on_the_clock_either
    assert_equal [4.5, 8.5], at(lever_then_down(:by_the_frame))
  end

  # The secret lever still goes where it went: the screen is in between and forgets nothing.
  def test_the_screen_remembers_which_lever_called_the_lift
    assert_equal 9, take_the_lift(an_episode(secret_car_on_first: true))[:floor]
  end

  # The ninth and tenth maps of an episode have no percentages, only a flat bonus. Only the tenth
  # has a lever, and the original words the screen for it (wl_inter.cpp, `mapon < 8`).
  def test_the_secret_floor_is_worth_a_flat_bonus
    floors = an_episode(secret_car_on_first: true)
    second_lever = leave_screen(2).last + 4
    run = Reference.new.input_each_frame { |f| [2, *leave_screen(2), second_lever].include?(f) ? [:a] : [] }
                   .run(program(floors), frames: second_lever + PRESS_ON + 4)

    assert_equal 9, run[:floor], "still on the secret floor"
    assert_equal 1, run[:_tally_showing]
    assert_equal WHOLE_PAR + 15_000, run[:score], "the first floor's par, and nothing on this one counted"
  end

  # THE PICTURE, which is the half no variable can show: the view has gone and the bar has not.
  def test_the_screen_covers_the_view_and_leaves_the_bar
    run = arrive_at_the_screen(two_floors_with_a_lift, drawing: true)
    ground = Wolf3D::Palette.game[Wolf3D::Tally::GROUND]

    assert_equal ground, run.screen.pixel(2, 2), "the top corner of the view"
    assert_equal ground, run.screen.pixel(2, FP::VIEW_H - 1), "and the bottom one"
    refute_equal ground, run.screen.pixel(2, FP::VIEW_H + 1), "and the bar is still there"
    written = (0...FP::VIEW_H).sum { |y| (0...FP::ACROSS).count { |x| run.screen.pixel(x, y) != ground } }

    assert_operator written, :>, 0, "and something is written on it"
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
    Reference.new.input_each_frame { |f| f == 2 ? [:b] : ([lever, *leave_screen(lever)].include?(f) ? [:a] : []) }
             .run(program(floors), frames: lever + FP::LIFT_WAIT + 12)
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
    run = Reference.new.input_each_frame { |f| f == 2 ? [:select] : ([lever, *leave_screen(lever)].include?(f) ? [:a] : []) }
                       .run(program(two_floors), frames: lever + FP::LIFT_WAIT + 12)

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
    frames = lever ? walked + FP::LIFT_WAIT + 14 : walked
    Reference.new.input_each_frame { |f| f < walked ? [:up] : ([walked + 2, *leave_screen(walked + 2)].include?(f) ? [:a] : []) }
             .run(program(floors), frames: frames)
  end

  # ...AND SO DO THE POINTS. Finishing a floor moves the score the next one puts back to
  # (`gamestate.oldscore = gamestate.score` in the same branch), so what you scored comes with you.
  def test_the_points_scored_on_one_floor_are_still_yours_on_the_next
    run = walk_into_the_car(a_piece_in_the_car(CROSS))
    worth = Wolf3D::Scenery::BONUSES.fetch(CROSS).last

    assert_equal 1, run[:floor], "on the second floor"
    assert_equal worth + Wolf3D::Tally::FOR_A_HUNDRED_PER_CENT + WHOLE_PAR, run[:score],
                 "the cross counted, and as the floor's only treasure it was a hundred per cent of them"
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

  # --- how much there is to find ---

  # EACH FLOOR'S OWN, which is what makes the tally at the end of a floor a share of THAT floor.
  # The original counts all three afresh as it sets each floor up: SetupGameLevel zeroes them, and
  # then ScanInfoPlane counts a wall that slides, SpawnStatic a treasure and each Spawn a man
  # (wl_game.cpp, wl_act1.cpp, wl_act2.cpp).
  def test_what_there_is_to_find_is_the_floor_you_are_on
    floors = floors_of(a_floor(name: "one", start_x: 4, start_y: 8, guards: 1, crosses: 1, secrets: 1),
                       a_floor(name: "two", start_x: 9, start_y: 3, guards: 2, crosses: 3, secrets: 2),
                       standing: true)
    run = take_the_lift(floors)

    assert_equal 1, run[:floor], "on the second floor"
    assert_equal 2, run[:kill_total], "its two guards"
    assert_equal 2, run[:secret_total], "its two walls that slide"
    assert_equal 3, run[:treasure_total], "its three crosses"
  end

  # ...AND ONLY THE MEN THIS GAME STANDS UP. One put down for the hardest setting alone is never
  # spawned on an easier one, and the original counts a man as it spawns him — ScanInfoPlane's
  # `if (gamestate.difficulty<gd_hard) break;` comes before the Spawn that would count him. Read
  # at the setting a game plays at until somebody picks, on the floor the game powers on to and
  # on the one the lift brings you to, because the two are set up by different code.
  def test_a_guard_only_a_harder_game_meets_is_not_one_to_kill
    floors = floors_of(a_floor(name: "one", start_x: 4, start_y: 8, guards: 1, harder: 1),
                       a_floor(name: "two", start_x: 9, start_y: 3, guards: 2, harder: 1),
                       standing: true)
    powered_on = Reference.new.run(program(floors), frames: 3)
    arrived = take_the_lift(floors)

    assert_equal 1, powered_on[:kill_total], "the first floor's one"
    assert_equal 2, arrived[:kill_total], "and the second floor's two"
  end

  # --- where the lift goes ---
  #
  # The rules of where it goes are the playthrough's, tested in test_playthrough.rb. This is the
  # test that the view tells it which lever called the lift: the cell you stand on in the car.

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
    assert_equal 9, secret[:floor], "a secret one goes to the last of the ten"
  end

  # ONE PULL OF THE LEVER IS ONE RIDE: the lift arriving puts the lever back up, so waiting long
  # enough for a second ride does not take one.
  def test_one_pull_of_the_lever_is_one_ride
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
