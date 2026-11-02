# frozen_string_literal: true

require_relative "test_helper"

# THE FOUR BOSSES WHO DO NOT END THEIR FLOORS WITH A KEY, and the fake Hitlers, and what they throw.
#
# The numbers here are read out of the original (wl_act2.cpp, wl_state.cpp, wl_game.cpp) and written
# out, so a change to the tables has something to disagree with.
class TestThrowingBosses < Minitest::Test
  include Wolf3DTest

  Enemy = Wolf3D::Enemy
  Guards = Wolf3D::Guards
  Behaviour = Wolf3D::Behaviour
  Release = Wolf3D::Fixture::Release
  Thrown = Wolf3D::Thrown

  ROW = 12
  PLAYER_X = 3

  # --- read off a floor ------------------------------------------------------------------------

  def test_each_boss_answers_to_the_originals_code
    { schabbs: 196, fake: 160, mecha: 178, gift: 215, fat: 179 }.each do |name, code|
      assert_equal name, Guards.new(with_things({ [8, ROW] => code })).guards.first.kind
    end
  end

  def test_no_two_kinds_answer_to_the_same_code
    assert_empty Guards.overlapping_codes
  end

  # A CARTRIDGE'S STATES GO PAST 255 once all of these are on it, and a state number is what says
  # which kind a thing is, so every table holding one has to reach that far.
  def test_a_cartridge_with_every_kind_is_built_and_plays
    run = Reference.new.run(view_of(every_kind_level, drawing: false), frames: 30)

    assert_operator Behaviour.for(Enemy::ALL.map(&:name)).length, :>, 255, "that is the point of this test"
    assert_equal Wolf3D::FirstPerson::START_HEALTH, run[:health]
  end

  def test_each_boss_takes_the_originals_own_killing
    { schabbs: [850, 950, 1550, 2400], fake: [200, 300, 400, 500], mecha: [800, 950, 1050, 1200],
      hitler: [500, 700, 800, 900], gift: [850, 950, 1050, 1200], fat: [850, 950, 1050, 1200] }
      .each { |name, hits| assert_equal hits, Enemy[name].hit_points, name }
  end

  def test_killing_each_is_worth_the_originals_points
    { schabbs: 5000, fake: 2000, mecha: 5000, hitler: 5000, gift: 5000, fat: 5000 }
      .each { |name, points| assert_equal points, Enemy[name].points, name }
  end

  # Checked by drawing every sprite of a real copy: each run starts where its kind's first
  # walking picture is.
  def test_each_kinds_pictures_start_where_a_real_copy_has_them
    { schabbs: 307, fake: 321, mecha: 334, hitler: 345, gift: 360, fat: 396 }
      .each { |name, first| assert_equal first, Enemy[name].first_picture, name }
  end

  def test_none_of_them_leaves_the_key
    %i[schabbs fake mecha hitler gift fat].each { |name| assert_nil Enemy[name].leaves, name }
  end

  # Hitler runs at five times a guard's walk and the machine at three (FirstSighting, A_HitlerMorph).
  def test_the_man_runs_faster_than_the_machine
    assert_in_delta Enemy[:guard].speed * 3, Enemy[:mecha].speed(chasing: true), 0.0001
    assert_in_delta Enemy[:guard].speed * 5, Enemy[:hitler].speed(chasing: true), 0.0001
  end

  def test_how_many_of_each_a_burst_holds
    fires = ->(kind, what) { Enemy[kind].states.count { |s| s.fires == what } }

    assert_equal 1, fires.call(:schabbs, :needle)
    assert_equal 1, fires.call(:gift, :rocket)
    assert_equal 1, fires.call(:fat, :rocket)
    assert_equal 4, fires.call(:fat, :gun), "a rocket and then the chaingun"
    assert_equal 8, fires.call(:fake, :flame)
    assert_equal 5, fires.call(:mecha, :gun)
    assert_equal 5, fires.call(:hitler, :gun)
  end

  # --- what is inside the machine ----------------------------------------------------------------

  # THE MAN IS ON THE FLOOR FROM THE START, hidden in the machine, because a pool cannot make a new
  # kind of thing out of nothing. He is one of the floor's men and not one of those to kill.
  def test_the_machine_carries_the_man_inside_it
    guards = Guards.new(with_things({ [8, ROW] => Enemy[:mecha].standing }))

    assert_equal %i[mecha hitler], guards.guards.map(&:kind)
    assert_equal 1, guards.to_kill(:medium), "SpawnHitler adds one to killtotal and A_HitlerMorph none"
  end

  def test_the_man_is_not_drawn_until_he_comes_out
    run = Reference.new.run(view_of(with_things({ [8, ROW] => Enemy[:mecha].standing })), frames: 3)
    man = slot_of(run, :hitler)

    assert_equal Behaviour.for(%i[mecha hitler]).number_of(:hitler, :inside), run.pool(:guard, :state)[man]
    assert_equal 0, run.pool(:guard, :shown)[man]
  end

  def test_only_the_machine_counts_toward_the_floors_total
    run = Reference.new.run(view_of(with_things({ [8, ROW] => Enemy[:mecha].standing }), drawing: false), frames: 2)

    assert_equal 1, run[:kill_total]
  end

  # --- played --------------------------------------------------------------------------------

  # A SYRINGE TAKES TWENTY AND UP, and it is the first thing he does once he has seen you.
  def test_schabbs_throws_a_syringe_and_it_hurts
    run = play(:schabbs, frames: 600)

    assert_operator run[:health], :<=, Wolf3D::FirstPerson::START_HEALTH - Thrown::NEEDLE_HITS
  end

  # IT FLIES, in a straight line, at the original's speed.
  def test_what_is_thrown_flies_at_the_player_a_step_at_a_time
    start, first = first_in_the_air(:schabbs)
    later = play(:schabbs, frames: start + 10).pool(:thrown, :x).compact.first
    pace = Thrown.speed_of(0x2000)

    assert_in_delta(-pace * 10, (later - first) / ONE, pace * 2)
  end

  # IT IS STOPPED BY WHAT WOULD STOP A MAN, which a line of sight is not: a barrel hides nobody.
  def test_a_rocket_bursts_on_a_barrel_and_leaves_smoke_behind_it
    seen = rows_seen(:gift, things: { [8, ROW] => BARREL }, frames: 400)

    assert_includes seen, :rocket
    assert_includes seen, :smoke1
    assert_includes seen, :boom1
  end

  def test_a_burst_does_not_reach_you
    run = play(:gift, things: { [8, ROW] => BARREL }, frames: 300)

    assert_equal Wolf3D::FirstPerson::START_HEALTH, run[:health]
  end

  def test_a_syringe_on_a_barrel_is_simply_gone
    refute_includes rows_seen(:schabbs, things: { [8, ROW] => BARREL }, frames: 300), :boom1
  end

  # A FAKE HITLER'S FIRE IS WEAK AND THERE IS A LOT OF IT, with nothing fixed under what it rolls.
  def test_fire_comes_in_a_stream_and_hurts_a_little_at_a_time
    assert_includes rows_seen(:fake, frames: 600), :fire1
    assert_equal 0, Thrown::ROWS.find { |row| row.name == :fire1 }.hits
  end

  # FIRE CREEPS. T_Projectile hangs on the end of its pictures, so it takes one step in six units
  # where a rocket steps every unit (wl_act2.cpp:2713).
  def test_fire_takes_a_step_as_each_picture_ends
    start, first = first_in_the_air(:fake)
    later = play(:fake, frames: start + 12).pool(:thrown, :x).compact.first

    assert_in_delta 0, (later - first) / ONE, Thrown.speed_of(0x1200) * 3, "two or three steps, no more"
  end

  # A BOSS HAS NO MOMENT OF REACTION (SightPlayer, wl_state.cpp:1521), where a guard has up to 64.
  def test_who_takes_how_long_to_react
    { guard: [1, 4], officer: [2, 0], mutant: [1, 6], ss: [1, 6], dog: [1, 8], hans: [1, 0], schabbs: [1, 0] }
      .each { |name, reaction| assert_equal reaction, Enemy[name].reaction, name }
  end

  # THE SECOND PICTURE OF THEIR FALL IS THE TIME THEIR LAST WORDS TAKE (wl_act2.cpp:2218).
  def test_the_four_take_their_time_going_down
    %i[schabbs gift fat hitler].each do |name|
      assert_equal 140 * Enemy::SCALE, Enemy[name].states.find { |s| s.name == :fall2 }.ticks, name
    end
  end

  # HE KEEPS HIS DISTANCE. Inside four cells he goes the other way, which no other kind does.
  def test_a_thrower_backs_away_from_you
    run = play(:schabbs, at: PLAYER_X + 3, frames: 120)
    x = run.pool(:guard, :x).compact.first / ONE

    assert_operator x, :>, PLAYER_X + 3.6, "he should have backed down the room"
  end

  # EVERYTHING IN THE AIR GOES when the floor is started again.
  # Read one frame after the floor starts again, which is only known by playing it. The rocket that
  # killed you has its smoke hanging in the air right up to then, so a stale number fails loudly.
  LIFE_LOST_AT = 229

  def test_what_is_in_the_air_is_gone_when_a_life_is_lost
    run = Reference.new.run(view_of(with_things({ [6, ROW] => Enemy[:gift].standing })), frames: LIFE_LOST_AT)

    assert_operator run[:lives], :<, Wolf3D::Lives::START, "he has killed you by now"
    assert_empty run.pool(:thrown, :row).compact
  end

  # HE COMES OUT WHERE THE MACHINE FELL, and the wreck stays. Played with a gun that can do it, from
  # far enough off that the machine does not win first.
  def test_the_man_comes_out_of_the_fallen_machine
    run = Reference.new.input_each_frame { [:b] }.run(machine_in_your_sights, frames: 500)
    states = run.pool(:guard, :state).compact.map { |state| machine_states.state_at(state).name }

    assert_includes states, :dead, "the wreck, which is what is left of the machine"
    refute_includes states, :inside, "and the man is out of it"
  end

  private

  ONE = (1 << Fraction::DEFAULT_BITS).to_f

  # A barrel, by its place in the original's list of pieces.
  BARREL = Wolf3D::Scenery::FIRST_CODE + 35

  def play(boss, at: 18, things: {}, frames: 300)
    Reference.new.run(game_with(boss, at, things), frames: frames)
  end

  def game_with(boss, at, things)
    @games ||= {}
    @games[[boss, at, things]] ||= view_of(with_things({ [at, ROW] => Enemy[boss].standing }.merge(things)), drawing: false)
  end

  # The first frame anything is in the air, looked for in steps, and where it was.
  def first_in_the_air(boss)
    (10..800).step(5).each do |frames|
      xs = play(boss, frames: frames).pool(:thrown, :x).compact
      return [frames, xs.first] unless xs.empty?
    end
    flunk "#{boss} never threw anything"
  end

  def rows_seen(boss, frames:, things: {})
    (20..frames).step(9).flat_map { |at|
      play(boss, things: things, frames: at).pool(:thrown, :row).compact.map { |n| Thrown::ROWS[n].name }
    }.uniq
  end

  # A man in the machine, and a chain gun with plenty.
  def machine_in_your_sights
    @machine_in_your_sights ||= view_of(with_things({ [PLAYER_X + 9, ROW] => Enemy[:mecha].standing }, corridor: true),
                                        armed_with: Wolf3D::Weapons::NUMBERS[:chain_gun], ammo: 99)
  end

  def machine_states = Behaviour.for(%i[mecha hitler])

  def slot_of(run, kind)
    table = Behaviour.for(%i[mecha hitler])
    run.pool(:guard, :state).index { |state| state && table.kind_at(state).name == kind }
  end

  def every_kind_level
    codes = Enemy::ALL.reject { |kind| kind.standing.nil? }.map(&:standing)
    with_things(codes.each_with_index.to_h { |code, n| [[9 + n, 20], code] })
  end

  SPRITES = Enemy::ALL.flat_map(&:pictures).max + 1 + Wolf3D::WeaponAtlas::COUNT

  def fixture = @fixture ||= Release.new(sprites: SPRITES)

  # +corridor+ walls in the row, for a test about something other than where he sidesteps to.
  def with_things(things, side: 24, corridor: false)
    rows = corridor ? (0...side).to_a - [ROW] : []
    arena(side: side, player: [PLAYER_X, ROW], things: things, walls: (0...side).to_a.product(rows))
  end
end
