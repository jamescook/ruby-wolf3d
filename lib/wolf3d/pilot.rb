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
  # IT PLAYS AS A PERSON WOULD, on the easiest setting: walk the way out, stop and shoot whoever is
  # in sight, fetch what is near and needed. It presses buttons and nothing else, so what it finishes
  # a person can finish.
  #
  # A BOSS IS BEATEN THE OLD WAY. His shots are dice with no bullet to dodge, so sidestepping does
  # nothing (T_Shoot). What stops a shot is a wall. So stock up first, in the secret room his floor
  # keeps for it, then fight from beside a corner: out to shoot, back in when hurt. He also carries
  # the key to the way out, so the floor cannot be finished round him.
  class Pilot
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

    # Frames between two presses of a button read on its edge, and how many it stays down.
    PRESS_EVERY = 16
    MENU_PRESS_EVERY = 24
    PRESS_FRAMES = 2

    # The screens with a highlighted row start on the middle setting, and the top one is the easiest.
    DIFFICULTY_UP_PRESSES = 4

    # Ten seconds of shooting that hurts nobody is a man behind something; walk on for five.
    FUTILE_FIGHT_FRAMES = 600
    WALK_ON_FRAMES = 300

    # A detour costs this many steps at most.
    DETOUR_STEPS = 14
    STUCK_FRAMES = 90
    AMMO_FULL = 99
    HEALTH_FULL = 100
    HEALTH_WORTH_FETCHING = 75
    SCAVENGE_AMMO_BELOW = 30

    # Hit points no ordinary man has.
    BOSS_HIT_POINTS = 200
    BOSS_SEEN_CELLS = 10.0
    BOSS_MOVED_CELLS = 0.3

    # OUT FOR SEVENTY FRAMES IN EVERY HUNDRED AND TEN, once he has hurt it at all, and it looks this
    # far for a corner. It never picks a cell this close to him, for he stops you walking there.
    PEEK_FRAMES = 110
    PEEK_OUT_FRAMES = 70
    PEEK_FROM_HEALTH = 90
    PEEK_STEPS = 5
    PEEK_NEAREST_CELLS = 1.6

    # THE SECRET ROOM ON THE FIRST EPISODE'S BOSS FLOOR, west of the big hall: the chain gun, health
    # and more clips than a pocket holds. Pushed from the east, the wall slides two cells and stops,
    # which leaves that last cell shut and the two behind it open.
    BossStock = Data.define(:wall, :from, :opens, :wall_ends)
    STOCK = Ractor.make_shareable(BossStock.new(wall: [25, 32], from: [26, 32], opens: [[25, 32], [24, 32]],
                                                wall_ends: [23, 32]))
    PUSH_FRAMES = 70

    # +maps+ are the floors of the copy on the cartridge, in the order they are played.
    def initialize(maps)
      @levels = Array.new(maps.count) { |n| maps[n] }
      @reports = @levels.map { |level| FloorReport.new(level) }
      @scenery = @levels.map { |level| Scenery.new(level) }
      @frame = 0
      @difficulty_presses = 0
    end

    # What to hold for the next frame, or :done on the screen that says you won.
    def buttons_for(game)
      @frame += 1
      screen = game.var(:screen)
      return :done if screen == Menus::WINNING
      return menu_buttons(screen) unless screen == Menus::PLAYING
      return press_now_and_then(:a) unless game.var(:_tally_showing).zero?

      floor = game.var(:floor)
      lives = game.var(:lives)
      begin_floor(floor, lives) if floor != @floor || lives != @lives
      return [] if game.var(:health) <= 0

      read_player(game)
      read_people(game) if (@frame % 4).zero? || @people.empty?
      choose_buttons
    end

    private

    def menu_buttons(screen)
      if screen == Menus::DIFFICULTY && @difficulty_presses < DIFFICULTY_UP_PRESSES * 2
        @difficulty_presses += 1
        return @difficulty_presses.odd? ? [:up] : []
      end
      press_now_and_then(:a)
    end

    def press_now_and_then(button) = (@frame % MENU_PRESS_EVERY) < PRESS_FRAMES ? [button] : []
    def press_at_intervals? = (@frame % PRESS_EVERY) < PRESS_FRAMES

    def begin_floor(floor, lives)
      @floor = floor
      @lives = lives
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
      @stuck_frames = 0
      @fight_frames = 0
      @walk_on_frames = 0
      @hit_points_left = nil
      @opened = []
      @pushing_frames = 0
      @boss = nil
      @boss_at = nil
      @boss_cell = nil
      @boss_home = nil
      @boss_seen = false
      @boss_hp = 0
      @boss_full_hp = 0
      @stage = stocks_up_here? ? :to_secret : :on_foot
    end

    def stocks_up_here? = @route.ends_at == :exit && @report.pushwalls.any? { |wall| [wall.x, wall.y] == STOCK.wall }

    def read_player(game)
      @x = game.var(:px) / FRACTION.to_f
      @y = game.var(:py) / FRACTION.to_f
      @view = game.var(:view)
      @health = game.var(:health)
      @ammo = game.var(:ammo)
      @keys = game.var(:keys)
      @weapon = game.var(:weapon)
      @attack_stage = game.var(:weapon_stage)
      @cell = [@x.floor, @y.floor]
      @taken[@cell] = true
      @stuck_frames = @cell == @last_cell ? @stuck_frames + 1 : 0
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
        [x, y, hit_points[n]] if hit_points[n].to_i.positive?
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
      return fight_from_corner if boss_awake?

      target ? fight(target) : travel
    end

    # --- seeing and aiming --------------------------------------------------------------------

    # The nearest man with a clear line, unless shooting has stopped doing any good.
    def pick_target
      total = @people.sum { |_, _, hit_points| hit_points }
      @fight_frames = 0 if total != @hit_points_left
      @hit_points_left = total
      if @fight_frames > FUTILE_FIGHT_FRAMES
        @walk_on_frames = WALK_ON_FRAMES
        @fight_frames = 0
      end
      if @walk_on_frames.positive?
        @walk_on_frames -= 1
        return nil
      end
      @people.select { |x, y, _| distance_to(x, y) < SIGHT_CELLS && clear_line?(@x, @y, x, y) }
             .min_by { |x, y, _| distance_to(x, y) }
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
      number = @report.doors.index([x, y])
      number && @doors_open && @doors_open[number].to_i.positive?
    end

    # How far `view` is from pointing at a place, the short way round.
    def view_error_to(x, y)
      wanted = (Math.atan2(y - @y, x - @x) / (2 * Math::PI) * CIRCLE).round
      view_error_from(wanted)
    end

    def view_error_from(wanted) = ((wanted - @view + (CIRCLE / 2)) % CIRCLE) - (CIRCLE / 2)

    def turn_buttons(error, tolerance)
      return [] if error.abs <= tolerance
      return [] if error.abs < GENTLE_TURN && (@frame % 3) != 0

      [error.positive? ? :right : :left]
    end

    def aim_tolerance(distance)
      [(Math.atan2(GUARD_HALF_WIDTH, distance) / (2 * Math::PI) * CIRCLE).round, FINEST_AIM].max
    end

    # A TRIGGER IS READ ON ITS EDGE, so a gun at rest needs the button let go between presses, and an
    # automatic in the middle of its cycle needs it held to go round again (Weapons).
    def trigger_down?
      return @weapon >= Weapons::MACHINE_GUN if @attack_stage >= 0

      @frame.even?
    end

    # --- an ordinary man ----------------------------------------------------------------------

    def fight((x, y, _hit_points))
      @fight_frames += 1
      distance = distance_to(x, y)
      error = view_error_to(x, y)
      tolerance = aim_tolerance(distance)
      buttons = turn_buttons(error, tolerance)
      buttons << :b if error.abs <= tolerance && trigger_down?
      buttons << :up if @ammo.zero? && error.abs < WALK_ON_TURNING / 2
      buttons
    end

    # --- walking ------------------------------------------------------------------------------

    def travel
      goal = stock_goal || detour_goal || next_way_point
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
      return walk_towards(ahead) if ahead

      @path = nil
      [:up]
    end

    def walk_towards(ahead)
      error = view_error_to(ahead[0] + 0.5, ahead[1] + 0.5)
      buttons = turn_buttons(error, WALK_AIM)
      buttons << :up if error.abs <= WALK_ON_TURNING
      buttons << :a if (@level.door?(*ahead) || @stuck_frames > STUCK_FRAMES) && press_at_intervals?
      buttons
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
      @detour = nil if @detour && @taken[@detour]
      return @detour if @detour

      wanted = @report.pickups.select { |piece| fetch_on_the_way?(piece) }.map { |piece| [piece.x, piece.y] }
      wanted += @drops if @ammo < SCAVENGE_AMMO_BELOW
      steps = steps_from_here
      @detour = wanted.reject { |cell| @taken[cell] }.select { |cell| steps[cell].to_i.between?(1, DETOUR_STEPS - 1) }
                      .min_by { |cell| steps[cell] }
    end

    def fetch_on_the_way?(piece)
      kind, = piece.bonus
      case kind
      when :health then @health < HEALTH_WORTH_FETCHING
      when :ammunition then @ammo < AMMO_FULL
      when :weapon, :extra_life then true
      else false
      end
    end

    # Cells between here and everywhere that can be walked to now.
    def steps_from_here
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

    def neighbours((x, y)) = FloorReport::STEPS.map { |dx, dy| [x + dx, y + dy] }.select { |cell| enterable?(cell) }

    def enterable?((x, y))
      return false if x.negative? || y.negative? || x >= @level.width || y >= @level.height
      return true if @opened.include?([x, y])
      return false if @opened.any? && [x, y] == STOCK.wall_ends
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
      case @stage
      when :to_secret then @cell == STOCK.from || @pushing_frames.positive? ? :push_wall : STOCK.from
      when :stocking then next_stock_piece
      end
    end

    def push_secret_wall
      lean_on_and_press(CIRCLE / 2) do
        @pushing_frames += 1
        next unless @pushing_frames > PUSH_FRAMES

        @opened = STOCK.opens
        @stage = :stocking
      end
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

    def boss_awake?
      return false unless @boss_at && @boss_hp.positive?

      @boss_seen ||= @boss_hp < @boss_full_hp ||
                     Math.hypot(@boss_at[0] - @boss_home[0], @boss_at[1] - @boss_home[1]) > BOSS_MOVED_CELLS ||
                     (distance_to(*@boss_at) < BOSS_SEEN_CELLS && clear_line?(@x, @y, *@boss_at))
    end

    def fight_from_corner
      x, y = @boss_at
      error = view_error_to(x, y)
      tolerance = aim_tolerance(distance_to(x, y))
      in_his_sight = clear_line?(@x, @y, x, y)
      hiding = @health < PEEK_FROM_HEALTH && (@frame % PEEK_FRAMES) >= PEEK_OUT_FRAMES
      buttons = turn_buttons(error, tolerance)
      buttons << :b if in_his_sight && error.abs <= tolerance && trigger_down?
      return buttons if in_his_sight != hiding

      buttons + step_to_cover_or_sight(x, y, !hiding)
    end

    def step_to_cover_or_sight(x, y, wants_sight)
      first_step = nearest_cell_where { |cell| clear_line?(cell[0] + 0.5, cell[1] + 0.5, x, y) == wants_sight }
      return step_buttons(first_step) if first_step

      @path = path_to(@boss_cell)
      return [] unless @path && @path[1]

      step_buttons(@path[1]) + (press_at_intervals? ? [:a] : [])
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
          next if came_from.key?(cell) || beside_boss?(cell)

          came_from[cell] = here
          queue << cell
        end
      end
      nil
    end

    def beside_boss?((x, y)) = Math.hypot(x + 0.5 - @boss_at[0], y + 0.5 - @boss_at[1]) < PEEK_NEAREST_CELLS
  end
end
