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
    FRACTION = 1 << VBlank::DSL::Fraction::DEFAULT_BITS
    CIRCLE = 1024

    KEY_BITS = FirstPerson::KEY_BITS
    LEVER = Elevator::SWITCH

    # How far off the line to a cell it still walks, and how far off a lever or wall it still uses
    # one. `view` moves in twelves, so a target narrower than half of that can never be met.
    WALK_AIM = 16
    WALK_ON_TURNING = 80
    USE_AIM = 12
    FINEST_AIM = 7
    GUARD_HALF_WIDTH = 0.12

    # The turn is held less often near the target, so it does not swing past.
    GENTLE_TURN = 60

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

    # The difficulty screen starts on its top row and the bottom one is the hardest, three presses
    # down. It fades in first, and it reads a press on a pass that can take a few frames, so each
    # press is held and spaced.
    DIFFICULTY_PRESSES = 3
    DIFFICULTY_SETTLE_FRAMES = 40
    DIFFICULTY_PRESS_FRAMES = 4
    DIFFICULTY_PRESS_SPACING = 24

    # A person's half a second, the place he has to be to shoot sooner, and how long a wound keeps him
    # awake.
    REACTION_PASSES = 15
    POINT_BLANK_CELLS = 2.0
    HURT_PASSES = 30
    HELD_UP_PASSES = 8

    # Below this, every fight is from behind something.
    COVER_BELOW_HEALTH = 70

    # A hurt player walks further for health.
    DETOUR_STEPS_WHEN_HURT = 40
    DETOUR_STEPS_FOR_A_LIFE = 60
    ANY_DISTANCE = 1000
    WEAPON_NUMBERS = Ractor.make_shareable({ machine_gun: Weapons::MACHINE_GUN, chain_gun: Weapons::CHAIN_GUN })
    HURT_HEALTH = 50

    # Ten seconds of shooting that hurts nobody is a man behind something; walk on for five.
    FUTILE_FIGHT_PASSES = 300
    WALK_ON_PASSES = 150

    # A detour costs this many steps at most.
    DETOUR_STEPS = 14
    STUCK_PASSES = 45
    AMMO_FULL = 99
    HEALTH_FULL = 100
    HEALTH_WORTH_FETCHING = 85
    SCAVENGE_AMMO_BELOW = 60
    LOW_AMMO = 40
    KEEP_ROUNDS = 15

    # When a door is worth an ambush, how far back it stands, and how long it waits. Nobody through
    # the door for the quiet passes means nobody is coming.
    AMBUSH_ROUNDS = 25
    AMBUSH_MEN = 3
    AMBUSH_CROWD_CELLS = 8.0
    AMBUSH_BACK_STEPS = 4
    AMBUSH_QUIET_PASSES = 120
    AMBUSH_MOST_PASSES = 900

    # Hit points no ordinary man has.
    BOSS_HIT_POINTS = 200
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
    def initialize(maps, hardest: false)
      @hardest = hardest
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
      return press_now_and_then(:a) if tally_showing?(game)

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
      return @buttons unless new_pass?(game)

      read_player(game)
      read_people(game) if (@pass % 2).zero? || @people.empty?
      @buttons = choose_buttons
    end

    # What to hold on the screens after the win, which a person reads before pressing on, or :done
    # when they are over: the summary, then each page of the article the episode ends on.
    def ending_buttons(game)
      @frame += 1
      return :done unless [Menus::WINNING, Menus::ARTICLE].include?(game.var(:screen))

      press_now_and_then(:a, every: ENDING_SCREEN_FRAMES)
    end

    private

    def new_pass?(game)
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
      return press_now_and_then(:a) unless screen == Menus::DIFFICULTY && @hardest

      @difficulty_frames += 1
      waited = @difficulty_frames - DIFFICULTY_SETTLE_FRAMES
      return [] if waited.negative?
      return press_now_and_then(:a) if waited >= DIFFICULTY_PRESSES * DIFFICULTY_PRESS_SPACING

      (waited % DIFFICULTY_PRESS_SPACING) < DIFFICULTY_PRESS_FRAMES ? [:down] : []
    end

    def press_now_and_then(button, every: MENU_PRESS_EVERY) = (@frame % every) < PRESS_FRAMES ? [button] : []
    def press_at_intervals? = (@pass % PRESS_EVERY_PASSES).zero?

    def count_men_near
      return 0 unless @cell

      @people.count { |x, y, _| distance_to(x, y) < NEAR_CELLS }
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
      @taken = {}
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
      @walk_on_passes = 0
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

    def stocks_up_here? = @route.ends_at == :exit

    def read_player(game)
      @x = game.var(:px) / FRACTION.to_f
      @y = game.var(:py) / FRACTION.to_f
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
      @taken[@cell] = true
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

        x = xs[n] / FRACTION.to_f
        y = ys[n] / FRACTION.to_f
        @drops << [x.floor, y.floor] if dropped[n].to_i.nonzero?
        note_boss(n, x, y, hit_points[n].to_i)
        [x, y, hit_points[n], n] if hit_points[n].to_i.positive?
      end
    end

    def note_boss(number, x, y, hit_points)
      @boss = number if @boss.nil? && hit_points >= BOSS_HIT_POINTS
      return unless number == @boss

      @boss_at = [x, y]
      @boss_cell = [x.floor, y.floor]
      @boss_hp = hit_points
      @boss_full_hp = [@boss_full_hp, hit_points].max
      @boss_home ||= @boss_at
    end

    def choose_buttons
      target = pick_target
      @sight_passes = target ? @sight_passes + 1 : 0
      return fight_boss(*@boss_at) if boss_awake?
      return hold_door(target) if @ambush
      return fight(target) if target && running_past? && in_the_way?(target)
      return travel_firing_at(target) if running_past?
      return travel unless target && reacted_to?(target)

      needs_cover = @health < COVER_BELOW_HEALTH || @men_in_sight > 1
      needs_cover ? fight_from_corner(target[0], target[1]) : fight(target)
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

    def in_the_way?((x, y, _hit_points)) = distance_to(x, y) < POINT_BLANK_CELLS || @stuck_passes > HELD_UP_PASSES

    def reacted_to?((x, y, _hit_points))
      @sight_passes >= REACTION_PASSES || @hurt_passes.positive? || distance_to(x, y) < POINT_BLANK_CELLS
    end

    # --- seeing and aiming --------------------------------------------------------------------

    # The nearest man with a clear line, unless shooting has stopped doing any good.
    def pick_target
      total = @people.sum { |_, _, hit_points| hit_points }
      @fight_passes = 0 if total != @hit_points_left
      @hit_points_left = total
      if @fight_passes > FUTILE_FIGHT_PASSES
        @walk_on_passes = WALK_ON_PASSES
        @fight_passes = 0
      end
      if @walk_on_passes.positive?
        @walk_on_passes -= 1
        @men_in_sight = 0
        return nil
      end
      seen = @people.select { |x, y, _| distance_to(x, y) < SIGHT_CELLS && clear_line?(@x, @y, x, y) }
      @men_in_sight = seen.length
      # It finishes the man it is shooting: turning to whoever is nearest this moment wastes the gun.
      target = seen.find { |man| man[3] == @target_number } || seen.min_by { |x, y, _| distance_to(x, y) }
      @target_number = target&.last
      target
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
      number && @doors_open && @doors_open[number].to_i >= FirstPerson::DOOR_WIDE * FRACTION
    end

    # How far `view` is from pointing at a place, the short way round.
    def view_error_to(x, y)
      wanted = (Math.atan2(y - @y, x - @x) / (2 * Math::PI) * CIRCLE).round
      view_error_from(wanted)
    end

    def view_error_from(wanted) = ((wanted - @view + (CIRCLE / 2)) % CIRCLE) - (CIRCLE / 2)

    def turn_buttons(error, tolerance)
      return [] if error.abs <= tolerance
      return [] if error.abs < GENTLE_TURN && (@pass % 2) != 0

      [error.positive? ? :right : :left]
    end

    def aim_tolerance(distance)
      [(Math.atan2(GUARD_HALF_WIDTH, distance) / (2 * Math::PI) * CIRCLE).round, FINEST_AIM].max
    end

    # A TRIGGER IS READ ON ITS EDGE, so a gun at rest needs the button let go between presses, and an
    # automatic in the middle of its cycle needs it held to go round again (Weapons).
    def trigger_down?
      return @weapon >= Weapons::MACHINE_GUN if @attack_stage >= 0

      @pass.even?
    end

    # --- an ordinary man ----------------------------------------------------------------------

    def fight((x, y, _hit_points))
      @fight_passes += 1
      distance = distance_to(x, y)
      error = view_error_to(x, y)
      tolerance = aim_tolerance(distance)
      buttons = turn_buttons(error, tolerance)
      buttons << :b if error.abs <= tolerance && trigger_down?
      buttons << :up if @ammo.zero? && error.abs < WALK_ON_TURNING / 2
      buttons
    end

    # --- a door with a crowd behind it ---------------------------------------------------------

    # A ROOM FULL OF MEN COMES THROUGH A DOOR ONE AT A TIME. So it opens the door, backs off down the
    # way it came with the gun on the opening, and shoots whoever comes through, until nobody has for
    # a while. Then it walks on through what is left.
    def crowded_door?(cell)
      return false unless @level.door?(*cell) && !@ambushed[cell]
      return false unless @best_weapon >= Weapons::CHAIN_GUN && @ammo >= AMBUSH_ROUNDS

      @people.count { |x, y, _| Math.hypot(x - cell[0], y - cell[1]) < AMBUSH_CROWD_CELLS } >= AMBUSH_MEN
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
      if @doors_open[@report.doors.index(@ambush[:door])].to_i.positive?
        @ambush[:stage] = :backing
        return []
      end
      buttons = turn_buttons(view_error_to(x + 0.5, y + 0.5), WALK_AIM) + [:up]
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

      buttons = turn_buttons(view_error_to(x + 0.5, y + 0.5), WALK_AIM) + step_buttons(way[1])
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
      turn_buttons(view_error_to(x + 0.5, y + 0.5), WALK_AIM)
    end

    def target_in_aim?((x, y)) = view_error_to(x, y).abs <= aim_tolerance(distance_to(x, y))

    # --- walking ------------------------------------------------------------------------------

    # With the boss dead the floor has nothing left to survive, so it takes his key and leaves.
    def travel
      goal = boss_dead? ? next_way_point : stock_goal || detour_goal || next_way_point
      return push_secret_wall if goal == :push_wall
      return pull_lever if goal == :lever

      follow_path_to(goal)
    end

    def follow_path_to(goal)
      if goal != @goal || @path.nil? || !@path.include?(@cell)
        @goal = goal
        @path = path_to(goal)
        return press_now_and_then(:a) unless @path
      end
      ahead = @path[@path.index(@cell) + 1]
      begin_ambush(ahead) if ahead && crowded_door?(ahead)
      return walk_towards(ahead) if ahead

      @path = nil
      [:up]
    end

    def walk_towards(ahead)
      error = view_error_to(ahead[0] + 0.5, ahead[1] + 0.5)
      buttons = turn_buttons(error, WALK_AIM)
      return buttons unless error.abs <= WALK_ON_TURNING

      buttons + [:up] + run_or_open(ahead)
    end

    # A DOES BOTH JOBS: held it runs, and pressed it opens a door. A door reads the press on its edge,
    # so it is let go on the way to one, and when walking has stopped getting anywhere.
    def run_or_open(ahead)
      blocked = @level.door?(*ahead) || @stuck_passes > STUCK_PASSES
      return [:a] unless blocked

      press_at_intervals? ? [:a] : []
    end

    def next_way_point
      @way_points.shift while @way_points.length > 1 && (@taken[@way_points.first] || key_held?(@way_points.first))
      goal = @way_points.first
      return :lever if goal == @route.cells.last && @route.ends_at == :lever && @cell == goal
      return goal if @boss_cell.nil? || (@keys & KEY_BITS.fetch(:gold)).nonzero?

      @boss_cell
    end

    def key_held?(cell)
      key = @level.key_at(*cell)
      key && (@keys & KEY_BITS.fetch(key)).nonzero?
    end

    def detour_goal
      @detour = nil if @detour == @cell || (@detour && @taken[@detour] && !@drops.include?(@detour))
      return @detour if @detour

      steps = steps_from_here
      wanted = @report.pickups.select { |piece| fetch_on_the_way?(piece) }
                      .to_h { |piece| [[piece.x, piece.y], furthest_for(piece)] }
      wanted = wanted.reject { |cell, _| @taken[cell] }
      # Something a man dropped is on the floor however often this cell has been walked.
      wanted.merge!(@drops.to_h { |cell| [cell, DETOUR_STEPS] }) if @ammo < SCAVENGE_AMMO_BELOW
      @detour = wanted.keys.select { |cell| steps[cell].to_i.between?(1, wanted[cell] - 1) }
                      .min_by { |cell| steps[cell] }
    end

    # A better gun is worth any walk on this setting, and another life nearly so.
    def furthest_for(piece)
      kind, = piece.bonus
      case kind
      when :weapon then ANY_DISTANCE
      when :extra_life then DETOUR_STEPS_FOR_A_LIFE
      when :health then @health < HURT_HEALTH ? ANY_DISTANCE : DETOUR_STEPS_WHEN_HURT
      when :ammunition then @ammo < LOW_AMMO ? DETOUR_STEPS_WHEN_HURT : DETOUR_STEPS
      else DETOUR_STEPS
      end
    end

    def fetch_on_the_way?(piece)
      kind, = piece.bonus
      case kind
      when :health then @health < HEALTH_WORTH_FETCHING
      when :ammunition then @ammo < AMMO_FULL
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
      steps = { @cell => 0 }
      queue = [@cell]
      until queue.empty?
        here = queue.shift
        neighbours(here).each do |cell|
          next if steps.key?(cell)

          steps[cell] = steps[here] + 1
          queue << cell
        end
      end
      steps
    end

    def path_to(goal)
      came_from = { @cell => nil }
      queue = [@cell]
      until queue.empty?
        here = queue.shift
        return path_back(here, came_from) if here == goal

        neighbours(here).each do |cell|
          next if came_from.key?(cell)

          came_from[cell] = here
          queue << cell
        end
      end
      nil
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
      lock.nil? || (@keys & KEY_BITS.fetch(lock)).nonzero?
    end

    def pull_lever
      lever_east = @level.wall_code(@cell[0] + 1, @cell[1]) == LEVER
      lean_on_and_press(lever_east ? 0 : CIRCLE / 2)
    end

    # Walls and levers are used from up against them, so it keeps walking while it presses.
    def lean_on_and_press(wanted_view)
      error = view_error_from(wanted_view)
      buttons = turn_buttons(error, USE_AIM)
      return buttons unless error.abs <= USE_AIM

      yield if block_given?
      buttons << :up
      buttons << :a if press_at_intervals?
      buttons
    end

    # --- stocking up before a boss ------------------------------------------------------------

    def stock_goal
      look_for_secret if @stage == :planning || (@stage == :on_foot && @cell != @searched_from)
      case @stage
      when :to_secret then @cell == @secret.from || @pushing_passes.positive? ? :push_wall : @secret.from
      when :stocking then next_stock_piece
      when :looting then next_stash_piece
      end
    end

    def look_for_secret
      @searched_from = @cell
      @secret = secret_to_better_gun || secret_to_stash
      @stage = if @secret then :to_secret
               elsif @stage == :planning && stocks_up_here? then :stocking
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
      return unless stocks_up_here? || @ammo < STASH_AMMO_BELOW || @health < STASH_HEALTH_BELOW

      walkable = steps_from_here
      close_by = secrets_from(walkable).select { |secret| stocks_up_here? || walkable[secret.from] <= STASH_STEPS }
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
      lean_on_and_press(@secret.view) do
        @pushing_passes += 1
        next unless @pushing_passes > PUSH_PASSES

        @stash = stash_behind(@secret)
        @opened += @secret.opens
        @wall_ends += [@secret.wall_ends]
        @pushing_passes = 0
        @stage = stocks_up_here? ? :stocking : :looting
      end
    end

    def next_stash_piece
      steps = steps_from_here
      wanted = @stash.select { |piece| stock?(piece) }.map { |piece| [piece.x, piece.y] }
                     .select { |cell| steps[cell] && !@taken[cell] }
      return wanted.min_by { |cell| steps[cell] } unless wanted.empty?

      @stage = :on_foot
      nil
    end

    def next_stock_piece
      steps = steps_from_here
      wanted = @report.pickups.select { |piece| stock?(piece) }.map { |piece| [piece.x, piece.y] }
                      .select { |cell| steps[cell] && !@taken[cell] }
      return wanted.min_by { |cell| steps[cell] } unless wanted.empty?

      @stage = :on_foot
      nil
    end

    def stock?(piece)
      kind, = piece.bonus
      case kind
      when :weapon then @weapon < Weapons::CHAIN_GUN
      when :ammunition then @ammo < AMMO_FULL
      when :health then @health < HEALTH_FULL
      when :extra_life then true
      else false
      end
    end

    # --- a boss -------------------------------------------------------------------------------

    def boss_dead? = !@boss.nil? && !@boss_hp.positive?

    def boss_awake?
      return false unless @boss_at && @boss_hp.positive?

      @boss_seen ||= @boss_hp < @boss_full_hp ||
                     Math.hypot(@boss_at[0] - @boss_home[0], @boss_at[1] - @boss_home[1]) > BOSS_MOVED_CELLS ||
                     (distance_to(*@boss_at) < BOSS_SEEN_CELLS && clear_line?(@x, @y, *@boss_at))
    end

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
      pieces.select { |cell| steps[cell] && !@taken[cell] }.min_by { |cell| steps[cell] }
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
      across = (@view * 2 * Math::PI / CIRCLE) + (side == :l ? -Math::PI / 2 : Math::PI / 2)
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
      if error.abs <= CIRCLE / 8 then [:up]
      elsif error.abs >= CIRCLE * 3 / 8 then [:down]
      else [error.positive? ? :r : :l]
      end
    end

    # The first step towards the nearest cell the block likes, within a few steps.
    def nearest_cell_where
      came_from = { @cell => nil }
      queue = [@cell]
      until queue.empty?
        here = queue.shift
        path = path_back(here, came_from)
        break if path.length > PEEK_STEPS + 1
        return path[1] if here != @cell && yield(here)

        neighbours(here).each do |cell|
          next if came_from.key?(cell) || beside_foe?(cell)

          came_from[cell] = here
          queue << cell
        end
      end
      nil
    end

    def beside_foe?((x, y)) = Math.hypot(x + 0.5 - @foe_at[0], y + 0.5 - @foe_at[1]) < PEEK_NEAREST_CELLS
  end
end
