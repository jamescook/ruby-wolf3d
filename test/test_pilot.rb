# frozen_string_literal: true

require_relative "test_helper"

# THE PILOT'S PARTS ON FLOORS MADE FOR ONE QUESTION, with no copy of the game. A RunningGame says what
# the cartridge would: where the player is and who is about. The whole bot on the real shareware is
# test_play_shareware.rb.
class TestPilot < Minitest::Test
  include Wolf3DTest

  Pilot = Wolf3D::Pilot
  Sight = Pilot::Sight
  SCALE = Sight::FIXED_POINT_SCALE
  ROW = 8
  THING = Wolf3D::Scenery::FIRST_CODE
  FIRST_AID = THING + 25
  CLIP = THING + 26
  MACHINE_GUN = THING + 27
  CHAIN_GUN = THING + 28
  CROSS = THING + 29
  ONE_UP = THING + 33
  BARREL = THING + 1
  PISTOL = Wolf3D::Weapons::PISTOL
  BOSS_HIT_POINTS = 1200
  FULL_HEALTH = Wolf3D::Pickups::FULL_HEALTH

  # What the cartridge would answer. +men+ are [x, y, hit points], and +at+ is a cell the player
  # stands in the middle of.
  class RunningGame
    STANDING_START = { screen: Wolf3D::Menus::PLAYING, floor: 0, lives: 3, game_over: 0, episode_won: 0, score: 0,
                       view: 0, health: 100, ammo: 50, keys: 0, weapon: 1, weapon_best: 1, weapon_stage: -1,
                       _gturn: 0, _tally_showing: 0 }.freeze

    def initialize(at: [3, 3], men: [], doors_open: [], gone: [], **player)
      @vars = STANDING_START.merge(player, px: (at[0] + 0.5) * SCALE, py: (at[1] + 0.5) * SCALE)
      @men = men
      @doors_open = doors_open
      @gone = gone
    end

    def var(name) = @vars.fetch(name)

    def list(name) = name == :door_open ? @doors_open : @gone

    def pool(_name, field)
      case field
      when :x then @men.map { |x, _, _| x * SCALE }
      when :y then @men.map { |_, y, _| y * SCALE }
      when :hp then @men.map { |_, _, hit_points| hit_points }
      else @men.map { 0 }
      end
    end
  end

  def read_game(sight, pass: 2, **game)
    sight.read(RunningGame.new(**game), pass: pass)
    sight
  end

  def sight_on(level, **game) = read_game(Sight.new(level, Wolf3D::FloorReport.new(level).doors), **game)

  def walker_on(level, sight)
    Pilot::Walker.new(level, Wolf3D::Scenery.new(level), sight, before_step: ->(_cell) {})
  end

  def supplies_on(level, sight)
    Pilot::Supplies.new(Wolf3D::Scenery.new(level), sight, walker_on(level, sight))
  end

  def wall_down_column_seven(except:) = (0...SIDE).map { |y| [7, y] } - [except].compact

  # --- the floor search ---------------------------------------------------------------------

  def test_steps_are_counted_round_a_wall
    level = arena(walls: wall_down_column_seven(except: [7, ROW]), player: [3, 3])
    sight = sight_on(level, at: [3, 3])

    assert_equal 17, walker_on(level, sight).steps_from_here[[10, 3]]
  end

  def test_a_path_steps_one_cell_at_a_time_through_the_only_gap
    level = arena(walls: wall_down_column_seven(except: [7, ROW]), player: [3, 3])
    path = walker_on(level, sight_on(level, at: [3, 3])).path_to([10, 3])

    assert_includes path, [7, ROW]
    path.each_cons(2) { |(ax, ay), (bx, by)| assert_equal 1, (ax - bx).abs + (ay - by).abs }
  end

  def test_a_barrel_is_walked_round
    level = arena(things: { [5, 3] => BARREL }, player: [3, 3])

    refute_includes walker_on(level, sight_on(level, at: [3, 3])).path_to([8, 3]), [5, 3]
  end

  def test_a_locked_door_is_a_wall_until_the_key_is_held
    gold_door = Wolf3D::Level::LOCKED_DOORS.first
    level = arena(walls: wall_down_column_seven(except: nil), cells: { [7, ROW] => gold_door }, player: [3, ROW])

    assert_nil walker_on(level, sight_on(level, at: [3, ROW])).path_to([10, ROW])
    assert_includes walker_on(level, sight_on(level, at: [3, ROW], keys: 1)).path_to([10, ROW]), [7, ROW]
  end

  # A pass takes a different number of frames on each way of running, so this is counted in passes.
  def test_with_no_way_to_the_goal_it_presses_use_every_few_passes
    level = arena(walls: wall_down_column_seven(except: nil), player: [3, ROW])
    sight = sight_on(level, at: [3, ROW])
    walker = walker_on(level, sight)
    every = Sight::PRESS_EVERY_PASSES

    presses = (every..(every * 3) - 1).select do |pass|
      read_game(sight, pass: pass, at: [3, ROW])
      walker.follow_path_to([10, ROW]) == [:a]
    end

    assert_equal [every, every * 2], presses
  end

  def test_the_nearest_cell_search_stops_at_its_limit
    level = arena(player: [3, 3])
    walker = walker_on(level, sight_on(level, at: [3, 3]))
    goal = ->(cell) { cell == [6, 3] }

    assert_nil walker.first_step_towards_nearest(within: 2, avoiding: nil, &goal)
    assert_equal [4, 3], walker.first_step_towards_nearest(within: 3, avoiding: nil, &goal)
  end

  def test_the_nearest_cell_search_goes_round_what_it_avoids
    level = arena(player: [3, 3])
    walker = walker_on(level, sight_on(level, at: [3, 3]))

    first_step = walker.first_step_towards_nearest(within: 5, avoiding: ->(cell) { cell == [4, 3] }) { |cell| cell == [6, 3] }

    assert_equal [3, 4], first_step
  end

  # --- the pickup table ---------------------------------------------------------------------

  def detour_on(level, **game)
    supplies_on(level, sight_on(level, **game)).choose_detour
  end

  def test_a_first_aid_box_is_a_detour_only_when_hurt
    level = arena(things: { [6, 3] => FIRST_AID }, player: [3, 3])

    assert_nil detour_on(level, at: [3, 3], health: FULL_HEALTH)
    assert_equal [6, 3], detour_on(level, at: [3, 3], health: 60)
  end

  def test_a_clip_is_a_detour_until_full
    level = arena(things: { [6, 3] => CLIP }, player: [3, 3])

    assert_nil detour_on(level, at: [3, 3], ammo: Wolf3D::Pickups::MOST_AMMO)
    assert_equal [6, 3], detour_on(level, at: [3, 3], ammo: 98)
  end

  def test_a_badly_hurt_player_walks_any_distance_for_health
    level = arena(side: 48, things: { [44, 3] => FIRST_AID }, player: [3, 3])

    assert_nil detour_on(level, at: [3, 3], health: 60)
    assert_equal [44, 3], detour_on(level, at: [3, 3], health: 40)
  end

  def test_a_one_up_is_always_a_detour_and_a_cross_never
    assert_equal [6, 3], detour_on(arena(things: { [6, 3] => ONE_UP }, player: [3, 3]), at: [3, 3])
    assert_nil detour_on(arena(things: { [6, 3] => CROSS }, player: [3, 3]), at: [3, 3])
  end

  def test_a_gun_is_a_detour_only_if_it_is_better
    level = arena(things: { [6, 3] => MACHINE_GUN }, player: [3, 3])

    assert_equal [6, 3], detour_on(level, at: [3, 3], weapon_best: PISTOL)
    assert_nil detour_on(level, at: [3, 3], weapon_best: Wolf3D::Weapons::MACHINE_GUN)
  end

  def test_a_piece_the_player_stands_on_is_no_detour
    level = arena(things: { [6, 3] => CLIP }, player: [3, 3])

    assert_nil detour_on(level, at: [6, 3])
  end

  # A FULL PLAYER LEAVES IT WHERE IT IS (Pickups): only the game's own list says it has gone.
  def test_a_piece_walked_over_at_full_health_is_still_a_detour_once_hurt
    level = arena(things: { [6, 3] => FIRST_AID }, player: [3, 3])
    sight = sight_on(level, at: [6, 3], health: FULL_HEALTH)
    read_game(sight, at: [3, 3], health: 60)

    assert_equal [6, 3], supplies_on(level, sight).choose_detour
  end

  def test_a_piece_the_game_has_taken_is_no_detour
    level = arena(things: { [6, 3] => FIRST_AID }, player: [3, 3])

    assert_nil detour_on(level, at: [3, 3], health: 60, gone: [1])
  end

  def test_a_detour_ends_when_the_piece_goes
    level = arena(things: { [6, 3] => FIRST_AID }, player: [3, 3])
    sight = sight_on(level, at: [3, 3], health: 60)
    supplies = supplies_on(level, sight)

    assert_equal [6, 3], supplies.choose_detour
    read_game(sight, at: [4, 3], health: 60, gone: [1])

    assert_nil supplies.choose_detour
  end

  # The gun in hand can be the pistol with the bullets gone, or the knife, whatever it owns.
  def test_only_a_better_gun_than_the_best_it_owns_is_stock
    level = arena(things: { [6, 3] => MACHINE_GUN }, player: [3, 3])
    sight = sight_on(level, at: [3, 3], weapon: PISTOL, weapon_best: Wolf3D::Weapons::MACHINE_GUN)
    supplies = supplies_on(level, sight)

    refute supplies.stock?(supplies.pieces.first)
  end

  # --- the secret plan ----------------------------------------------------------------------

  def floor_behind_a_secret_wall(things)
    arena(walls: wall_down_column_seven(except: nil), player: [3, ROW],
          things: { [7, ROW] => Wolf3D::Level::PUSHWALL }.merge(things))
  end

  def plan_on(level, sight, ends_at: :lever)
    report = Wolf3D::FloorReport.new(level)
    walker = walker_on(level, sight)
    route = Wolf3D::FloorReport::Route.new(cells: [], ends_at: ends_at)
    Pilot::SecretPlan.new(report, route, sight, walker, Pilot::Supplies.new(Wolf3D::Scenery.new(level), sight, walker))
  end

  def goal_of(plan)
    plan.update
    plan.goal
  end

  def test_a_better_gun_behind_a_wall_sends_it_to_the_wall
    level = floor_behind_a_secret_wall({ [12, ROW] => MACHINE_GUN })

    assert_equal [6, ROW], goal_of(plan_on(level, sight_on(level, at: [3, ROW])))
  end

  def test_a_gun_it_has_is_not_worth_opening_a_wall_for
    level = floor_behind_a_secret_wall({ [12, ROW] => MACHINE_GUN })

    assert_nil goal_of(plan_on(level, sight_on(level, at: [3, ROW], weapon_best: Wolf3D::Weapons::MACHINE_GUN)))
  end

  def test_a_wall_opens_for_a_stash_only_when_short
    stash = { [10, ROW] => CLIP, [11, ROW] => CLIP, [12, ROW] => CLIP }
    level = floor_behind_a_secret_wall(stash)

    assert_nil goal_of(plan_on(level, sight_on(level, at: [3, ROW], ammo: 60)))
    assert_equal [6, ROW], goal_of(plan_on(level, sight_on(level, at: [3, ROW], ammo: 10)))
  end

  def test_two_pieces_are_no_stash
    level = floor_behind_a_secret_wall({ [10, ROW] => CLIP, [11, ROW] => CLIP })

    assert_nil goal_of(plan_on(level, sight_on(level, at: [3, ROW], ammo: 10)))
  end

  def test_after_the_push_it_goes_for_what_was_behind_the_wall
    level = floor_behind_a_secret_wall({ [12, ROW] => MACHINE_GUN })
    sight = sight_on(level, at: [6, ROW])
    plan = plan_on(level, sight)

    assert_equal :push_wall, goal_of(plan)
    (Pilot::SecretPlan::PUSH_PASSES + 1).times { plan.push_wall }

    assert_equal [12, ROW], goal_of(plan)
  end

  # --- a fight ------------------------------------------------------------------------------

  # A long fight that hurts nobody means a man behind something, from a corner as much as standing.
  def test_a_futile_fight_from_a_corner_is_given_up
    level = arena(player: [3, ROW])
    sight = sight_on(level, at: [3, ROW], men: [[9.5, ROW + 0.5, 25]])
    gunfight = Pilot::Gunfight.new(sight, walker_on(level, sight))
    gunfight.update

    assert gunfight.target
    (Pilot::Gunfight::FUTILE_FIGHT_PASSES + 1).times { gunfight.fight_from_corner(9.5, ROW + 0.5) }
    gunfight.update

    assert_nil gunfight.target
  end

  # --- a boss -------------------------------------------------------------------------------

  def boss_fight_on(level, sight, hardest: true)
    walker = walker_on(level, sight)
    gunfight = Pilot::Gunfight.new(sight, walker)
    supplies = Pilot::Supplies.new(Wolf3D::Scenery.new(level), sight, walker)
    Pilot::BossFight.new(sight, walker, gunfight, supplies, hardest: hardest)
  end

  def fight_pass(boss_fight, sight)
    boss_fight.note(sight.guards)
    boss_fight.update
    boss_fight.fight
  end

  HANS = [[12.5, ROW + 0.5, BOSS_HIT_POINTS]].freeze

  def floor_with_a_gap_at_his_row = arena(walls: wall_down_column_seven(except: [7, ROW]), player: [3, ROW])

  def noted_boss(level, sight)
    boss_fight_on(level, sight).tap do |boss_fight|
      boss_fight.note(sight.guards)
      boss_fight.update
    end
  end

  def floor_with_him_walled_off = arena(walls: wall_down_column_seven(except: nil), player: [3, ROW])

  def test_a_boss_it_can_see_starts_the_fight
    level = floor_with_a_gap_at_his_row
    close = [[9.5, ROW + 0.5, BOSS_HIT_POINTS]]

    assert_predicate noted_boss(level, sight_on(level, at: [3, ROW], men: close)), :awake?
  end

  def test_a_boss_walking_about_behind_a_wall_starts_nothing
    level = floor_with_him_walled_off
    sight = sight_on(level, at: [3, ROW], men: HANS)
    boss_fight = noted_boss(level, sight)
    read_game(sight, at: [3, ROW], men: [[10.5, 3.5, BOSS_HIT_POINTS]])
    boss_fight.note(sight.guards)
    boss_fight.update

    refute_predicate boss_fight, :awake?
  end

  def test_a_boss_it_has_hit_starts_the_fight_wherever_he_is
    level = floor_with_him_walled_off
    sight = sight_on(level, at: [3, ROW], men: HANS)
    boss_fight = noted_boss(level, sight)
    read_game(sight, at: [3, ROW], men: [[12.5, ROW + 0.5, BOSS_HIT_POINTS - 1]])
    boss_fight.note(sight.guards)
    boss_fight.update

    assert_predicate boss_fight, :awake?
  end

  def test_a_wound_with_a_clear_line_to_him_starts_the_fight
    level = floor_with_a_gap_at_his_row
    far_off = [[14.5, ROW + 0.5, BOSS_HIT_POINTS]]
    sight = sight_on(level, at: [3, ROW], men: far_off, health: 100)
    boss_fight = noted_boss(level, sight)

    refute_predicate boss_fight, :awake?
    read_game(sight, at: [3, ROW], men: far_off, health: 90)
    boss_fight.update

    assert_predicate boss_fight, :awake?
  end

  def test_a_wound_with_a_wall_between_them_starts_nothing
    level = floor_with_him_walled_off
    sight = sight_on(level, at: [3, ROW], men: HANS, health: 100)
    boss_fight = noted_boss(level, sight)
    read_game(sight, at: [3, ROW], men: HANS, health: 90)
    boss_fight.update

    refute_predicate boss_fight, :awake?
  end

  def test_a_boss_is_shot_from_range_with_the_gun_on_him
    level = floor_with_a_gap_at_his_row
    sight = sight_on(level, at: [3, ROW], men: HANS, view: 0)

    assert_includes fight_pass(boss_fight_on(level, sight), sight), :b
  end

  # The cell it fired from is at range, and the way to him is where his gun does its worst.
  def test_out_of_his_sight_it_goes_back_to_where_it_last_had_a_shot
    level = floor_with_a_gap_at_his_row
    sight = sight_on(level, at: [3, ROW], men: HANS, view: 0)
    boss_fight = boss_fight_on(level, sight)
    fight_pass(boss_fight, sight)

    read_game(sight, at: [3, 6], men: HANS, view: 256)

    assert_includes fight_pass(boss_fight, sight), :up, "south, back to the cell it fired from"
  end

  def test_too_close_to_a_boss_it_backs_away
    level = arena(player: [8, ROW])
    men = [[10.5, ROW + 0.5, BOSS_HIT_POINTS]]
    sight = sight_on(level, at: [8, ROW], men: men, view: 0)

    assert_includes fight_pass(boss_fight_on(level, sight), sight), :down
  end

  def test_short_of_health_it_runs_for_the_stock
    level = arena(walls: wall_down_column_seven(except: [7, ROW]), player: [3, ROW], things: { [3, 3] => FIRST_AID })
    sight = sight_on(level, at: [3, ROW], men: HANS, view: 768, health: 30)

    assert_includes fight_pass(boss_fight_on(level, sight), sight), :up, "north, to the first aid"
  end

  # --- a floor ------------------------------------------------------------------------------

  # What it was holding was for the floor it left, and a pass may not have gone by yet.
  def test_nothing_held_on_one_floor_is_held_on_the_next
    pilot = Pilot.new([way_out_level, way_out_level])

    refute_empty pilot.buttons_for(RunningGame.new(at: [4, 4], floor: 0, _gturn: 1))
    assert_empty pilot.buttons_for(RunningGame.new(at: [4, 4], floor: 1, _gturn: 1))
  end

  # --- the ending ---------------------------------------------------------------------------

  def test_the_ending_reads_each_screen_before_pressing_on
    pilot = Pilot.new([arena])
    summary = RunningGame.new(screen: Wolf3D::Menus::WINNING)
    presses = (1..Pilot::ENDING_SCREEN_FRAMES * 2).select { |frame| pilot.ending_buttons(summary) == [:a] && frame }

    assert_operator presses.each_cons(2).map { |first, second| second - first }.max, :>=, Pilot::ENDING_SCREEN_FRAMES - 2
  end

  def test_the_ending_is_over_past_the_article
    assert_equal :done, Pilot.new([arena]).ending_buttons(RunningGame.new(screen: Wolf3D::Menus::SCORES))
  end
end
