# frozen_string_literal: true

module Wolf3D
  # A PLAYER MADE OF RUBY: asked before each frame what to press, it reads the running game and
  # answers a list of buttons. tools/play_shareware.rb hands it to a playthrough, and every frame
  # goes on the tape, so the tape plays back with none of this present.
  #
  # IT KNOWS THE MAPS AND READS THE REST. FloorReport says how a floor can be finished, and the
  # running game says where the player is and who is alive. Everything is worked out again as it
  # plays, because a guard does what the random numbers say and no list of presses could answer him.
  #
  # IT PLAYS AS A PERSON WOULD, on the easiest setting or the hardest: walk the way out, open the
  # secret wall that hides a better gun, shoot whoever is in sight, fetch what is near and needed. It presses buttons and nothing else, so what it finishes a person
  # can finish.
  #
  # IT TAKES A PERSON'S TIME TO REACT. It has every man's place to the pixel, so left to itself it
  # shoots through the first crack of a door. So it looks through a door only when the door is right
  # open, it walks on for a moment after a man comes into sight, and it fires at once only when he is
  # on top of it or has just hurt it.
  #
  # A BOSS IS BEATEN FROM A STOCK. He carries the key to the way out, so the floor cannot be finished
  # round him, and his floor keeps a secret room for the fight. On the easiest setting it fights him
  # from beside a corner: out to shoot, back in when hurt. On the hardest he outlasts that, so it holds
  # him at range and keeps moving, and runs back to the room when short (#kite_boss).
  class Pilot
    # The game is over and there is nothing left to steer.
    class Lost < StandardError; end

    # What the running game keeps its fractions in, and what a full circle is on `view`.
    FIXED_POINT_SCALE = 1 << VBlank::DSL::Fraction::DEFAULT_BITS
    VIEW_UNITS_PER_TURN = 1024

    KEY_BITS = FirstPerson::KEY_BITS
    LEVER_WALL_CODE = Elevator::SWITCH

    # How far off the line to a cell it still walks, and how far off a lever or wall it still uses
    # one. `view` moves in twelves, so a target narrower than half of that can never be met.
    WALK_AIM_VIEW_UNITS = 16
    WALK_WITHIN_VIEW_UNITS = 80
    USE_AIM_VIEW_UNITS = 12
    FINEST_AIM_VIEW_UNITS = 7
    GUARD_HALF_WIDTH_CELLS = 0.12

    # The turn is held less often near the target, so it does not swing past.
    GENTLE_TURN_VIEW_UNITS = 60

    SIGHT_CELLS = 11.0
    NEAR_CELLS = 6.0

    # On the menus, frames between two presses of a button read on its edge, and how many it stays
    # down. In play, passes between two presses.
    MENU_PRESS_EVERY = 24
    PRESS_FRAMES = 2
    PRESS_EVERY_PASSES = 8

    # IT DECIDES ONCE A PASS, because a pass is what the world moves by, and a pass takes two or three
    # frames on a cartridge and one anywhere else. Counted in passes, what it does is the same on every
    # way of running. A flag that flips every pass says when one has gone by. The world stands still
    # for the lift, so this many frames with no flip counts as a pass as well.
    PASS_FLAG = :_gturn
    MOST_FRAMES_A_PASS = 8

    # The original's four settings, top row first (gd_baby and the rest, in wl_def.h).
    DIFFICULTY_NAMES = %w[baby easy medium hard].freeze
    HARDEST_DIFFICULTY = DIFFICULTY_NAMES.length - 1

    # The difficulty screen starts on its top row, and each row down is one press. It fades in first,
    # and it reads a press on a pass that can take a few frames, so each press is held and spaced.
    DIFFICULTY_SETTLE_FRAMES = 40
    DIFFICULTY_PRESS_FRAMES = 4
    DIFFICULTY_PRESS_SPACING = 24

    # How long a person takes to react, how near a man has to be for it to shoot sooner, and how
    # long a wound keeps it alert.
    REACTION_PASSES = 15
    POINT_BLANK_CELLS = 2.0
    HURT_PASSES = 30
    STUCK_SHOOT_PASSES = 8

    # Below this, every fight is from behind something.
    COVER_BELOW_HEALTH = 70

    # A hurt player walks further for health.
    DETOUR_STEPS_WHEN_HURT = 40
    DETOUR_STEPS_FOR_A_LIFE = 60
    ANY_DISTANCE_STEPS = 1000
    WEAPON_NUMBERS = Ractor.make_shareable({ machine_gun: Weapons::MACHINE_GUN, chain_gun: Weapons::CHAIN_GUN })
    HURT_HEALTH = 50

    # This much shooting that hurts nobody means a man behind something, so it ignores everybody for
    # half as long and walks on.
    FUTILE_FIGHT_PASSES = 300
    IGNORE_MEN_PASSES = 150

    # A detour costs this many steps at most.
    DETOUR_STEPS = 14
    STUCK_PRESS_USE_PASSES = 45
    HEALTH_WORTH_FETCHING = 85
    SCAVENGE_AMMO_BELOW = 60
    LOW_AMMO_ROUNDS = 40
    KEEP_ROUNDS = 15

    # When a door is worth an ambush, how far back it stands, and how long it waits. Nobody through
    # the door for the quiet passes means nobody is coming.
    AMBUSH_ROUNDS = 25
    AMBUSH_MEN = 3
    AMBUSH_CROWD_CELLS = 8.0
    AMBUSH_BACK_STEPS = 4
    AMBUSH_QUIET_PASSES = 120
    AMBUSH_MOST_PASSES = 900

    # THE FEWEST HIT POINTS A BOSS STARTS WITH, on any setting. The pool of guards does not say what
    # kind a man is, but no ordinary man has this many. Pac-Man's ghosts are bosses by the table
    # and have none, for they cannot be shot.
    BOSS_LEAST_HIT_POINTS = Enemy::ALL.select(&:boss?).flat_map(&:hit_points).select(&:positive?).min

    # How long a person stays on each screen after the win. It is long enough to read a page.
    ENDING_SCREEN_FRAMES = 600
    BOSS_SEEN_CELLS = 10.0
    BOSS_MOVED_CELLS = 0.3

    # OUT FOR THIRTY-FIVE PASSES IN EVERY FIFTY-FIVE, once he has hurt it at all, and it looks this
    # far for a corner. It never picks a cell this close to him, for he stops you walking there.
    PEEK_PASSES = 55
    PEEK_OUT_PASSES = 35
    PEEK_FROM_HEALTH = 90
    PEEK_STEPS = 5
    PEEK_NEAREST_CELLS = 1.6

    # The range it holds a boss at, how long one strafe lasts, and when it goes for more stock.
    KITE_NEAR_CELLS = 8.0
    KITE_FAR_CELLS = 11.0
    KITE_STRAFE_PASSES = 20
    KITE_STRAFE_CELLS = 0.7
    KITE_HEALTH_BELOW = 50
    KITE_ROUNDS_BELOW = 25

    # One of the men on the floor, alive. +number+ is his slot in the pool of guards.
    Man = Data.define(:x, :y, :hit_points, :number)

    # A SECRET WALL WORTH OPENING: the one that stands between here and a better gun. +from+ is where
    # to push it, +view+ which way that faces, +opens+ the cells it leaves and +wall_ends+ where it
    # stops, which stays shut. A wall slides two cells, or one with something behind it.
    Secret = Data.define(:wall, :from, :view, :opens, :wall_ends)
    VIEWS = Ractor.make_shareable({ [1, 0] => 0, [0, 1] => 256, [-1, 0] => 512, [0, -1] => 768 })

    PUSH_PASSES = 35

    # When a stash behind a secret wall is worth the walk.
    STASH_AMMO_BELOW = 40
    STASH_HEALTH_BELOW = 70
    STASH_STEPS = 30
    STASH_PIECES = 3

    # +maps+ are the floors of the copy on the cartridge, in the order they are played.
    # +difficulty+ is the row of the difficulty screen, counted from nought.
    def initialize(maps, difficulty: 0)
      @difficulty = difficulty
      @hardest = difficulty == HARDEST_DIFFICULTY
      @levels = Array.new(maps.count) { |n| maps[n] }
      @reports = @levels.map { |level| FloorReport.new(level) }
      @scenery = @levels.map { |level| Scenery.new(level) }
      @frame = 0
      @pass = 0
      @frames_on_pass = 0
      @buttons = []
      @difficulty_frames = 0
    end

    # What to hold for the next frame, or :done on the screen that says you won.
    def buttons_for(game)
      @frame += 1
      screen = game.var(:screen)
      return :done if screen == Menus::WINNING
      return menu_buttons(screen) unless screen == Menus::PLAYING
      return press_periodically(:a) if tally_showing?(game)

      floor = game.var(:floor)
      lives = game.var(:lives)
      raise Lost, "The pilot lost its last life on floor #{floor + 1}, on frame #{@frame}." if lost?(game)

      # Dying puts the floor back as it was, and a life won by score or by a pickup changes nothing.
      if floor != @floor || lives < @lives
        warn format("frame %d: floor %d, %d lives, health %d, ammo %d, gun %d, score %d, last at %s with %d near, gun %d ammo %d",
                    @frame, floor + 1, lives, game.var(:health), game.var(:ammo), game.var(:weapon_best),
                    game.var(:score), @cell.inspect, count_men_near, @best_weapon.to_i, @ammo.to_i)
        begin_floor(floor)
      end
      @lives = lives
      return [] if game.var(:health) <= 0
      return @buttons unless advance_pass(game)

      read_player(game)
      read_people(game) if (@pass % 2).zero? || @people.empty?
      @buttons = choose_buttons
    end

    # What to hold on the screens after the win, which a person reads before pressing on, or :done
    # when they are over: the summary, then each page of the article the episode ends on.
    def ending_buttons(game)
      @frame += 1
      return :done unless [Menus::WINNING, Menus::ARTICLE].include?(game.var(:screen))

      press_periodically(:a, every: ENDING_SCREEN_FRAMES)
    end

    private

    # Counts one frame, and says whether it began a new pass.
    def advance_pass(game)
      flag = game.var(PASS_FLAG)
      @frames_on_pass += 1
      return false if flag == @pass_flag && @frames_on_pass < MOST_FRAMES_A_PASS

      @pass_flag = flag
      @frames_on_pass = 0
      @pass += 1
      true
    end

    # A won game ends through the same flag as a lost one.
    def lost?(game) = game.var(:game_over) != 0 && game.var(:episode_won).zero?

    # A cartridge of one floor has no screen between floors.
    def tally_showing?(game)
      game.var(:_tally_showing) != 0
    rescue ArgumentError
      false
    end

    def menu_buttons(screen)
      return press_periodically(:a) unless screen == Menus::DIFFICULTY && @difficulty.positive?

      @difficulty_frames += 1
      waited = @difficulty_frames - DIFFICULTY_SETTLE_FRAMES
      return [] if waited.negative?
      return press_periodically(:a) if waited >= @difficulty * DIFFICULTY_PRESS_SPACING

      (waited % DIFFICULTY_PRESS_SPACING) < DIFFICULTY_PRESS_FRAMES ? [:down] : []
    end

    def press_periodically(button, every: MENU_PRESS_EVERY) = (@frame % every) < PRESS_FRAMES ? [button] : []
    def press_at_intervals? = (@pass % PRESS_EVERY_PASSES).zero?

    def count_men_near
      return 0 unless @cell

      @people.count { |man| distance_to(man.x, man.y) < NEAR_CELLS }
    end

    def begin_floor(floor)
      @floor = floor
      @level = @levels.fetch(floor)
      @report = @reports.fetch(floor)
      @route = @report.route
      @blocks = @scenery.fetch(floor)
      @way_points = @route.cells.select { |x, y| @level.key_at(x, y) } + [@route.cells.last]
      @people = []
      @drops = []
      @walked = {}
      @path = nil
      @goal = nil
      @detour = nil
      @last_cell = nil
      @trail = []
      @ambush = nil
      @ambushed = {}
      @stuck_passes = 0
      @sight_passes = 0
      @hurt_passes = 0
      @last_health = nil
      @fight_passes = 0
      @ignore_men_passes = 0
      @hit_points_left = nil
      @opened = []
      @wall_ends = []
      @door_numbers = @report.doors.each_with_index.to_h
      @walk_maps = {}
      @firing_cell = nil
      @stash = []
      @searched_from = nil
      @pushing_passes = 0
      @boss = nil
      @boss_at = nil
      @boss_cell = nil
      @boss_home = nil
      @boss_seen = false
      @boss_hp = 0
      @boss_full_hp = 0
      @secret = nil
      @stage = :planning
    end

    def ends_at_exit? = @route.ends_at == :exit

    def read_player(game)
      @x = game.var(:px) / FIXED_POINT_SCALE.to_f
      @y = game.var(:py) / FIXED_POINT_SCALE.to_f
      @view = game.var(:view)
      @health = game.var(:health)
      @ammo = game.var(:ammo)
      @keys = game.var(:keys)
      @weapon = game.var(:weapon)
      @best_weapon = game.var(:weapon_best)
      @attack_stage = game.var(:weapon_stage)
      @hurt_passes = @last_health && @health < @last_health ? HURT_PASSES : [@hurt_passes - 1, 0].max
      @last_health = @health
      @cell = [@x.floor, @y.floor]
      @walked[@cell] = true
      @stuck_passes = @cell == @last_cell ? @stuck_passes + 1 : 0
      @trail << @cell unless @cell == @last_cell
      @last_cell = @cell
    end

    def read_people(game)
      @doors_open = game.list(:door_open)
      xs, ys, hit_points, dropped = %i[x y hp dropped].map { |field| game.pool(:guard, field) }
      @drops = []
      @people = xs.each_index.filter_map do |n|
        next unless xs[n]

        x = xs[n] / FIXED_POINT_SCALE.to_f
        y = ys[n] / FIXED_POINT_SCALE.to_f
        @drops << [x.floor, y.floor] if dropped[n].to_i.nonzero?
        note_boss(n, x, y, hit_points[n].to_i)
        Man.new(x: x, y: y, hit_points: hit_points[n], number: n) if hit_points[n].to_i.positive?
      end
    end

    def note_boss(number, x, y, hit_points)
      @boss = number if @boss.nil? && hit_points >= BOSS_LEAST_HIT_POINTS
      return unless number == @boss

      @boss_at = [x, y]
      @boss_cell = [x.floor, y.floor]
      @boss_hp = hit_points
      @boss_full_hp = [@boss_full_hp, hit_points].max
      @boss_home ||= @boss_at
    end

    def choose_buttons
      target = update_target
      @sight_passes = target ? @sight_passes + 1 : 0
      note_boss_seen
      return fight_boss(*@boss_at) if boss_awake?
      return hold_door(target) if @ambush
      return fight(target) if target && running_past? && blocking_way?(target)
      return travel_firing_at(target) if running_past?
      return travel unless target && reacted_to?(target)

      needs_cover = @health < COVER_BELOW_HEALTH || @men_in_sight.length > 1
      needs_cover ? fight_from_corner(target.x, target.y) : fight(target)
    end

    # ON THE HARDEST SETTING THERE ARE MORE MEN THAN BULLETS, so once it has a gun that can clear a
    # way it stops to shoot only at whoever blocks the way. A moving player is also harder to hit.
    def running_past? = @hardest && @best_weapon >= Weapons::MACHINE_GUN

    # Whoever happens to stand in front of a running gun gets shot, at no cost in time.
    def travel_firing_at(target)
      buttons = travel
      return buttons unless target && @ammo > KEEP_ROUNDS

      target_in_aim?(target) && trigger_down? ? buttons + [:b] : buttons
    end

    def blocking_way?(man) = distance_to(man.x, man.y) < POINT_BLANK_CELLS || @stuck_passes > STUCK_SHOOT_PASSES

    def reacted_to?(man)
      @sight_passes >= REACTION_PASSES || @hurt_passes.positive? || distance_to(man.x, man.y) < POINT_BLANK_CELLS
    end

    # --- seeing and aiming --------------------------------------------------------------------

    # The man to deal with this pass, unless shooting has stopped doing any good.
    def update_target
      start_ignoring_men_after_futile_fight
      if @ignore_men_passes.positive?
        @ignore_men_passes -= 1
        @men_in_sight = []
        return nil
      end
      @men_in_sight = men_with_clear_line
      target = pick_target(@men_in_sight)
      @target_number = target&.number
      target
    end

    def start_ignoring_men_after_futile_fight
      total = @people.sum(&:hit_points)
      @fight_passes = 0 if total != @hit_points_left
      @hit_points_left = total
      return unless @fight_passes > FUTILE_FIGHT_PASSES

      @ignore_men_passes = IGNORE_MEN_PASSES
      @fight_passes = 0
    end

    def men_with_clear_line
      @people.select { |man| distance_to(man.x, man.y) < SIGHT_CELLS && clear_line?(@x, @y, man.x, man.y) }
    end

    # It finishes the man it is shooting: turning to whoever is nearest this moment wastes the gun.
    def pick_target(men)
      men.find { |man| man.number == @target_number } || men.min_by { |man| distance_to(man.x, man.y) }
    end

    def distance_to(x, y) = Math.hypot(x - @x, y - @y)

    def clear_line?(from_x, from_y, x, y)
      steps = (Math.hypot(x - from_x, y - from_y) / 0.15).ceil
      (1...steps).all? do |n|
        cell_x = (from_x + ((x - from_x) * n / steps)).floor
        cell_y = (from_y + ((y - from_y) * n / steps)).floor
        end_of_line = [[from_x.floor, from_y.floor], [x.floor, y.floor]].include?([cell_x, cell_y])
        end_of_line || see_through?(cell_x, cell_y)
      end
    end

    def see_through?(x, y) = !@level.solid?(x, y) && (!@level.door?(x, y) || door_open?(x, y))

    def door_open?(x, y)
      number = @door_numbers[[x, y]]
      return false unless number && @doors_open

      @doors_open[number].to_i >= FirstPerson::DOOR_WIDE * FIXED_POINT_SCALE
    end

    # How far `view` is from pointing at a place, the short way round.
    def view_error_to(x, y)
      wanted = (Math.atan2(y - @y, x - @x) / (2 * Math::PI) * VIEW_UNITS_PER_TURN).round
      view_error_from(wanted)
    end

    def view_error_from(wanted) = ((wanted - @view + (VIEW_UNITS_PER_TURN / 2)) % VIEW_UNITS_PER_TURN) - (VIEW_UNITS_PER_TURN / 2)

    def turn_buttons(error, tolerance)
      return [] if error.abs <= tolerance
      return [] if error.abs < GENTLE_TURN_VIEW_UNITS && (@pass % 2) != 0

      [error.positive? ? :right : :left]
    end

    def aim_tolerance(distance)
      [(Math.atan2(GUARD_HALF_WIDTH_CELLS, distance) / (2 * Math::PI) * VIEW_UNITS_PER_TURN).round, FINEST_AIM_VIEW_UNITS].max
    end

    # A TRIGGER IS READ ON ITS EDGE, so a gun at rest needs the button let go between presses, and an
    # automatic in the middle of its cycle needs it held to go round again (Weapons).
    def trigger_down?
      return @weapon >= Weapons::MACHINE_GUN if @attack_stage >= 0

      @pass.even?
    end

    # --- an ordinary man ----------------------------------------------------------------------

    def fight(man)
      @fight_passes += 1
      distance = distance_to(man.x, man.y)
      error = view_error_to(man.x, man.y)
      tolerance = aim_tolerance(distance)
      buttons = turn_buttons(error, tolerance)
      buttons << :b if error.abs <= tolerance && trigger_down?
      buttons << :up if @ammo.zero? && error.abs < WALK_WITHIN_VIEW_UNITS / 2
      buttons
    end

    # --- a door with a crowd behind it ---------------------------------------------------------

    # A ROOM FULL OF MEN COMES THROUGH A DOOR ONE AT A TIME. So it opens the door, backs off down the
    # way it came with the gun on the opening, and shoots whoever comes through, until nobody has for
    # a while. Then it walks on through what is left.
    def crowded_door?(cell)
      return false unless @level.door?(*cell) && !@ambushed[cell]
      return false unless @best_weapon >= Weapons::CHAIN_GUN && @ammo >= AMBUSH_ROUNDS

      @people.count { |man| Math.hypot(man.x - cell[0], man.y - cell[1]) < AMBUSH_CROWD_CELLS } >= AMBUSH_MEN
    end

    def begin_ambush(door)
      spot = @trail.last(AMBUSH_BACK_STEPS).find { |x, y| clear_line?(x + 0.5, y + 0.5, door[0] + 0.5, door[1] + 0.5) }
      @ambush = { door: door, spot: spot || @cell, stage: :opening, quiet_passes: 0, passes: 0 }
    end

    def finish_ambush
      @ambushed[@ambush[:door]] = true
      @ambush = nil
      @path = nil
      travel
    end

    def hold_door(target)
      @ambush[:passes] += 1
      return finish_ambush if @ambush[:passes] > AMBUSH_MOST_PASSES || @ammo < KEEP_ROUNDS

      case @ambush[:stage]
      when :opening then open_ambush_door
      when :backing then back_to_spot(target)
      else shoot_through_door(target)
      end
    end

    def open_ambush_door
      x, y = @ambush[:door]
      if @doors_open[@door_numbers.fetch(@ambush[:door])].to_i.positive?
        @ambush[:stage] = :backing
        return []
      end
      buttons = turn_buttons(view_error_to(x + 0.5, y + 0.5), WALK_AIM_VIEW_UNITS) + [:up]
      press_at_intervals? ? buttons + [:a] : buttons
    end

    def back_to_spot(target)
      if @cell == @ambush[:spot]
        @ambush[:stage] = :holding
        return []
      end
      x, y = @ambush[:door]
      way = path_to(@ambush[:spot])
      return shoot_through_door(target) unless way && way[1]

      buttons = turn_buttons(view_error_to(x + 0.5, y + 0.5), WALK_AIM_VIEW_UNITS) + step_buttons(way[1])
      target && target_in_aim?(target) && trigger_down? ? buttons + [:b] : buttons
    end

    def shoot_through_door(target)
      if target
        @ambush[:quiet_passes] = 0
        return fight(target)
      end
      @ambush[:quiet_passes] += 1
      return finish_ambush if @ambush[:quiet_passes] > AMBUSH_QUIET_PASSES

      x, y = @ambush[:door]
      turn_buttons(view_error_to(x + 0.5, y + 0.5), WALK_AIM_VIEW_UNITS)
    end

    def target_in_aim?(man) = view_error_to(man.x, man.y).abs <= aim_tolerance(distance_to(man.x, man.y))

    # --- walking ------------------------------------------------------------------------------

    # With the boss dead the floor has nothing left to survive, so it takes his key and leaves.
    def travel
      drop_reached_way_points
      goal = boss_dead? ? way_point : stock_goal || choose_detour || way_point
      return push_secret_wall if goal == :push_wall
      return pull_lever if goal == :lever

      follow_path_to(goal)
    end

    def follow_path_to(goal)
      if goal != @goal || @path.nil? || !@path.include?(@cell)
        @goal = goal
        @path = path_to(goal)
        return press_periodically(:a) unless @path
      end
      ahead = @path[@path.index(@cell) + 1]
      begin_ambush(ahead) if ahead && crowded_door?(ahead)
      return walk_towards(ahead) if ahead

      @path = nil
      [:up]
    end

    def walk_towards(ahead)
      error = view_error_to(ahead[0] + 0.5, ahead[1] + 0.5)
      buttons = turn_buttons(error, WALK_AIM_VIEW_UNITS)
      return buttons unless error.abs <= WALK_WITHIN_VIEW_UNITS

      buttons + [:up] + run_or_open(ahead)
    end

    # A DOES BOTH JOBS: held it runs, and pressed it opens a door. A door reads the press on its edge,
    # so it is let go on the way to one, and when walking has stopped getting anywhere.
    def run_or_open(ahead)
      blocked = @level.door?(*ahead) || @stuck_passes > STUCK_PRESS_USE_PASSES
      return [:a] unless blocked

      press_at_intervals? ? [:a] : []
    end

    def drop_reached_way_points
      @way_points.shift while @way_points.length > 1 && (@walked[@way_points.first] || key_held?(@way_points.first))
    end

    def way_point
      goal = @way_points.first
      return :lever if goal == @route.cells.last && @route.ends_at == :lever && @cell == goal
      return goal if @boss_cell.nil? || holds_key?(FloorReport::BOSS_KEY)

      @boss_cell
    end

    def key_held?(cell)
      key = @level.key_at(*cell)
      !key.nil? && holds_key?(key)
    end

    def holds_key?(key) = @keys.anybits?(KEY_BITS.fetch(key))

    def choose_detour
      @detour = nil if @detour == @cell || (@detour && @walked[@detour] && !@drops.include?(@detour))
      return @detour if @detour

      steps = steps_from_here
      wanted = @report.pickups.select { |piece| worth_detour?(piece) }
                      .to_h { |piece| [[piece.x, piece.y], furthest_for(piece)] }
      wanted = wanted.reject { |cell, _| @walked[cell] }
      # Something a man dropped is on the floor however often this cell has been walked.
      wanted.merge!(@drops.to_h { |cell| [cell, DETOUR_STEPS] }) if @ammo < SCAVENGE_AMMO_BELOW
      @detour = wanted.keys.select { |cell| steps[cell].to_i.between?(1, wanted[cell] - 1) }
                      .min_by { |cell| steps[cell] }
    end

    # A better gun is worth any walk on this setting, and another life nearly so.
    def furthest_for(piece)
      kind, = piece.bonus
      case kind
      when :weapon then ANY_DISTANCE_STEPS
      when :extra_life then DETOUR_STEPS_FOR_A_LIFE
      when :health then @health < HURT_HEALTH ? ANY_DISTANCE_STEPS : DETOUR_STEPS_WHEN_HURT
      when :ammunition then @ammo < LOW_AMMO_ROUNDS ? DETOUR_STEPS_WHEN_HURT : DETOUR_STEPS
      else DETOUR_STEPS
      end
    end

    def worth_detour?(piece)
      kind, = piece.bonus
      case kind
      when :health then @health < HEALTH_WORTH_FETCHING
      when :ammunition then @ammo < Pickups::MOST_AMMO
      when :weapon then better_gun?(piece)
      when :extra_life then true
      else false
      end
    end

    def better_gun?(piece) = WEAPON_NUMBERS.fetch(piece.bonus.last) > @best_weapon

    # Cells between here and everywhere that can be walked to now.
    # The walk from here is the same until the player changes cell or the floor changes.
    def steps_from_here
      map = walk_map
      return map[:steps] if map[:steps_from] == @cell

      map[:steps_from] = @cell
      map[:steps] = measure_steps
    end

    # WHERE ONE CAN WALK DEPENDS ONLY ON WHICH WALLS ARE PUSHED AND WHICH KEYS ARE HELD. One map stands
    # for each of those, and the search for a stash asks about the same few again and again.
    def walk_map = @walk_maps[[@opened, @wall_ends, @keys]] ||= { neighbours: {}, steps: nil, steps_from: nil }

    def measure_steps
      steps = {}
      search_floor { |cell, distance, _came_from| steps[cell] = distance }
      steps
    end

    def path_to(goal)
      search_floor { |cell, _distance, came_from| return path_back(cell, came_from) if cell == goal }
      nil
    end

    # EVERY CELL THAT CAN BE WALKED TO FROM HERE, nearest first, breadth first with ties broken in
    # the order of FloorReport::STEPS. The block is given each cell, its distance in steps and the
    # trail behind it, and stops the search by leaving. +avoiding+ is any cell the walk must not cross.
    def search_floor(avoiding: nil)
      came_from = { @cell => nil }
      distance = { @cell => 0 }
      queue = [@cell]
      until queue.empty?
        here = queue.shift
        yield here, distance[here], came_from
        neighbours(here).each do |cell|
          next if came_from.key?(cell) || avoiding&.call(cell)

          came_from[cell] = here
          distance[cell] = distance[here] + 1
          queue << cell
        end
      end
    end

    def path_back(here, came_from)
      cells = []
      while here
        cells.unshift(here)
        here = came_from[here]
      end
      cells
    end

    def neighbours(cell) = walk_map[:neighbours][cell] ||= enterable_neighbours(cell)

    def enterable_neighbours((x, y)) = FloorReport::STEPS.map { |dx, dy| [x + dx, y + dy] }.select { |cell| enterable?(cell) }

    def enterable?((x, y))
      return false if x.negative? || y.negative? || x >= @level.width || y >= @level.height
      return true if @opened.include?([x, y])
      return false if @wall_ends.include?([x, y])
      return false if @level.solid?(x, y) || @blocks.blocks?(x, y)

      lock = @level.lock_at(x, y)
      lock.nil? || holds_key?(lock)
    end

    def pull_lever
      lever_east = @level.wall_code(@cell[0] + 1, @cell[1]) == LEVER_WALL_CODE
      press_into_wall(lever_east ? 0 : VIEW_UNITS_PER_TURN / 2)
    end

    # Walls and levers are used from up against them, so it keeps walking while it presses.
    def press_into_wall(wanted_view)
      error = view_error_from(wanted_view)
      buttons = turn_buttons(error, USE_AIM_VIEW_UNITS)
      return buttons unless error.abs <= USE_AIM_VIEW_UNITS

      yield if block_given?
      buttons << :up
      buttons << :a if press_at_intervals?
      buttons
    end

    # --- stocking up before a boss ------------------------------------------------------------

    def stock_goal
      look_for_secret if @stage == :planning || (@stage == :on_foot && @cell != @searched_from)
      @stage = :on_foot if taking_pieces? && next_piece.nil?
      case @stage
      when :to_secret then @cell == @secret.from || @pushing_passes.positive? ? :push_wall : @secret.from
      when :stocking, :looting then next_piece
      end
    end

    def taking_pieces? = %i[stocking looting].include?(@stage)

    def look_for_secret
      @searched_from = @cell
      @secret = secret_to_better_gun || secret_to_stash
      @stage = if @secret then :to_secret
               elsif @stage == :planning && ends_at_exit? then :stocking
               else :on_foot
               end
    end

    def secret_to_better_gun
      guns = @report.pickups.select { |piece| piece.bonus.first == :weapon && better_gun?(piece) }.map { |piece| [piece.x, piece.y] }
      walkable = steps_from_here
      return nil if guns.empty? || guns.any? { |cell| walkable[cell] }

      secrets_from(walkable).find do |secret|
        reachable = with_secret_open(secret) { steps_from_here }
        guns.any? { |cell| reachable[cell] }
      end
    end

    # THE FLOORS KEEP THEIR SUPPLIES BEHIND SECRET WALLS, often beside the way through. Short of
    # bullets or health, it opens one that is close and has enough behind it to pay for the walk.
    def secret_to_stash
      return unless ends_at_exit? || @ammo < STASH_AMMO_BELOW || @health < STASH_HEALTH_BELOW

      walkable = steps_from_here
      close_by = secrets_from(walkable).select { |secret| ends_at_exit? || walkable[secret.from] <= STASH_STEPS }
      close_by.find { |secret| stash_behind(secret).count { |piece| stock?(piece) } >= STASH_PIECES }
    end

    # What opening this wall would put within reach that is out of reach now.
    def stash_behind(secret)
      walkable = steps_from_here
      reachable = with_secret_open(secret) { steps_from_here }
      @report.pickups.select { |piece| reachable[[piece.x, piece.y]] && !walkable[[piece.x, piece.y]] }
    end

    def secrets_from(walkable)
      walls = @report.pushwalls.reject { |wall| @opened.include?([wall.x, wall.y]) }
      walls.flat_map { |wall| FloorReport::STEPS.filter_map { |dx, dy| secret_at(wall, dx, dy, walkable) } }
    end

    # The block sees the floor as it would be with this wall pushed.
    def with_secret_open(secret)
      opened = @opened
      wall_ends = @wall_ends
      @opened += secret.opens
      @wall_ends += [secret.wall_ends]
      yield
    ensure
      @opened = opened
      @wall_ends = wall_ends
    end

    def secret_at(wall, dx, dy, walkable)
      from = [wall.x - dx, wall.y - dy]
      beyond = [wall.x + dx, wall.y + dy]
      further = [wall.x + (2 * dx), wall.y + (2 * dy)]
      return unless walkable[from] && enterable?(beyond)

      opens = enterable?(further) ? [[wall.x, wall.y], beyond] : [[wall.x, wall.y]]
      Secret.new(wall: [wall.x, wall.y], from: from, view: VIEWS.fetch([dx, dy]), opens: opens,
                 wall_ends: enterable?(further) ? further : beyond)
    end

    def push_secret_wall
      press_into_wall(@secret.view) do
        @pushing_passes += 1
        next unless @pushing_passes > PUSH_PASSES

        @stash = stash_behind(@secret)
        @opened += @secret.opens
        @wall_ends += [@secret.wall_ends]
        @pushing_passes = 0
        @stage = ends_at_exit? ? :stocking : :looting
      end
    end

    # The nearest piece of what this stage is after that is still worth having.
    def next_piece
      steps = steps_from_here
      pieces = @stage == :stocking ? @report.pickups : @stash
      pieces.select { |piece| stock?(piece) }.map { |piece| [piece.x, piece.y] }
            .select { |cell| steps[cell] && !@walked[cell] }
            .min_by { |cell| steps[cell] }
    end

    def stock?(piece)
      kind, = piece.bonus
      case kind
      when :weapon then @weapon < Weapons::CHAIN_GUN
      when :ammunition then @ammo < Pickups::MOST_AMMO
      when :health then @health < Pickups::FULL_HEALTH
      when :extra_life then true
      else false
      end
    end

    # --- a boss -------------------------------------------------------------------------------

    def boss_dead? = !@boss.nil? && !@boss_hp.positive?

    def note_boss_seen
      return unless @boss_at && @boss_hp.positive?

      @boss_seen ||= @boss_hp < @boss_full_hp ||
                     Math.hypot(@boss_at[0] - @boss_home[0], @boss_at[1] - @boss_home[1]) > BOSS_MOVED_CELLS ||
                     (distance_to(*@boss_at) < BOSS_SEEN_CELLS && clear_line?(@x, @y, *@boss_at))
    end

    def boss_awake? = !@boss_at.nil? && @boss_hp.positive? && @boss_seen

    def fight_boss(x, y) = @hardest ? kite_boss(x, y) : fight_from_corner(x, y)

    # ON THE HARDEST SETTING NO CORNER SAVES YOU: he has more hit points than a fight of peeking
    # leaves bullets for. What saves you is T_Shoot's sums. From six cells a shot of his does a
    # quarter of the harm one does beside you, and a running player is harder to hit. So it keeps him
    # at range, gun on him, and never stands still.
    def kite_boss(x, y)
      supply = boss_fight_supply
      return follow_path_to(supply) if supply

      distance = distance_to(x, y)
      sees_him = clear_line?(@x, @y, x, y)
      error = view_error_to(x, y)
      tolerance = aim_tolerance(distance)
      buttons = turn_buttons(error, tolerance)
      buttons << :b if sees_him && error.abs <= tolerance && trigger_down?
      @firing_cell = @cell if sees_him && distance >= KITE_NEAR_CELLS
      return buttons + approach_cell(boss_approach_cell(x, y)) if !sees_him || distance > KITE_FAR_CELLS

      away = distance < KITE_NEAR_CELLS ? step_away_from(x, y) : nil
      buttons + (away || strafe_buttons(x, y)) + [:a]
    end

    # OUT OF HIS SIGHT IT GOES BACK TO WHERE IT LAST HAD A SHOT FROM, at range. Walking on towards him
    # is only for when that place shows nothing either, which means his door has shut: beside him is
    # where his chain gun does its worst.
    def boss_approach_cell(x, y)
      return @firing_cell if @firing_cell && @firing_cell != @cell

      [x.floor, y.floor]
    end

    def approach_cell(cell)
      way = path_to(cell)
      return [] unless way && way[1]

      step_buttons(way[1]) + run_or_open(way[1])
    end

    # Run for what is left of the stock, turning its back on him to get there.
    def boss_fight_supply
      kinds = []
      kinds << :health if @health < KITE_HEALTH_BELOW
      kinds << :ammunition if @ammo < KITE_ROUNDS_BELOW
      return if kinds.empty?

      steps = steps_from_here
      pieces = @report.pickups.select { |piece| kinds.include?(piece.bonus.first) }.map { |piece| [piece.x, piece.y] }
      pieces.select { |cell| steps[cell] && !@walked[cell] }.min_by { |cell| steps[cell] }
    end

    def step_away_from(x, y)
      farthest = neighbours(@cell).max_by { |cell| Math.hypot(cell[0] + 0.5 - x, cell[1] + 0.5 - y) }
      return unless farthest && Math.hypot(farthest[0] + 0.5 - x, farthest[1] + 0.5 - y) > distance_to(x, y)

      step_buttons(farthest)
    end

    # Side to side and back, as long as the step still has a line to him. A step that loses him is a
    # step back towards his gun, so it holds its place instead.
    def strafe_buttons(x, y)
      side = (@pass % (KITE_STRAFE_PASSES * 2)) < KITE_STRAFE_PASSES ? :l : :r
      strafe_keeps_line?(side, x, y) ? [side] : []
    end

    def strafe_keeps_line?(side, x, y)
      across = (@view * 2 * Math::PI / VIEW_UNITS_PER_TURN) + (side == :l ? -Math::PI / 2 : Math::PI / 2)
      clear_line?(@x + (Math.cos(across) * KITE_STRAFE_CELLS), @y + (Math.sin(across) * KITE_STRAFE_CELLS), x, y)
    end

    # Out to shoot and back in when hurt, keeping the gun on him all the while.
    def fight_from_corner(x, y)
      @foe_at = [x, y]
      error = view_error_to(x, y)
      tolerance = aim_tolerance(distance_to(x, y))
      in_his_sight = clear_line?(@x, @y, x, y)
      hiding = @health < PEEK_FROM_HEALTH && (@pass % PEEK_PASSES) >= PEEK_OUT_PASSES
      buttons = turn_buttons(error, tolerance)
      buttons << :b if in_his_sight && error.abs <= tolerance && trigger_down?
      return buttons if in_his_sight != hiding

      buttons + step_to_cover_or_sight(x, y, !hiding)
    end

    def step_to_cover_or_sight(x, y, wants_sight)
      first_step = nearest_cell_where { |cell| clear_line?(cell[0] + 0.5, cell[1] + 0.5, x, y) == wants_sight }
      return step_buttons(first_step) + run_or_open(first_step) if first_step

      @path = path_to([x.floor, y.floor])
      return [] unless @path && @path[1]

      step_buttons(@path[1]) + run_or_open(@path[1])
    end

    # A step in any direction without turning, so the gun stays on him.
    def step_buttons((x, y))
      error = view_error_to(x + 0.5, y + 0.5)
      if error.abs <= VIEW_UNITS_PER_TURN / 8 then [:up]
      elsif error.abs >= VIEW_UNITS_PER_TURN * 3 / 8 then [:down]
      else [error.positive? ? :r : :l]
      end
    end

    # The first step towards the nearest cell the block likes, within a few steps.
    def nearest_cell_where
      search_floor(avoiding: method(:beside_foe?)) do |cell, distance, came_from|
        return nil if distance > PEEK_STEPS
        return path_back(cell, came_from)[1] if cell != @cell && yield(cell)
      end
      nil
    end

    def beside_foe?((x, y)) = Math.hypot(x + 0.5 - @foe_at[0], y + 0.5 - @foe_at[1]) < PEEK_NEAREST_CELLS
  end
end
