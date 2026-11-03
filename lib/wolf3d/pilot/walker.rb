# frozen_string_literal: true

module Wolf3D
  class Pilot
    # GETTING ABOUT THE FLOOR: where can be walked to from here, and the buttons that walk there. It
    # is told which secret walls are open, and keeps one map of the floor for each way things stand.
    class Walker
      # What the steps from one cell say for one way the floor can stand. +neighbours+ fills as it
      # is asked and +steps+ holds the last walk measured, from +steps_from+.
      WalkMap = Struct.new(:neighbours, :steps, :steps_from)

      # How far off the line to a cell it still walks, how far off a lever or wall it still uses one,
      # and how far off it can be and still be walking at all rather than only turning.
      WALK_AIM_VIEW_UNITS = 16
      USE_AIM_VIEW_UNITS = 12
      WALK_WITHIN_VIEW_UNITS = 80

      # Passes in one cell before walking counts as having stopped getting anywhere.
      STUCK_PRESS_USE_PASSES = 45

      # +before_step+ is told each cell a path is about to enter.
      def initialize(level, scenery, sight, before_step:)
        @level = level
        @blocks = scenery
        @sight = sight
        @before_step = before_step
        @opened = []
        @wall_ends = []
        @walk_maps = {}
      end

      # Cells between here and everywhere that can be walked to now.
      # The walk from here is the same until the player changes cell or the floor changes.
      def steps_from_here
        map = walk_map
        return map.steps if map.steps_from == @sight.cell

        map.steps_from = @sight.cell
        map.steps = measure_steps
      end

      def path_to(goal)
        search_floor { |cell, _distance, came_from| return path_back(cell, came_from) if cell == goal }
        nil
      end

      # The first step towards the nearest cell the block likes, no further off than +within+ steps,
      # without crossing a cell +avoiding+ answers yes to.
      def first_step_towards_nearest(within:, avoiding:)
        search_floor(avoiding: avoiding) do |cell, distance, came_from|
          return nil if distance > within
          return path_back(cell, came_from)[1] if cell != @sight.cell && yield(cell)
        end
        nil
      end

      def neighbours(cell) = walk_map.neighbours[cell] ||= enterable_neighbours(cell)

      def enterable?((x, y))
        return false if x.negative? || y.negative? || x >= @level.width || y >= @level.height
        return true if @opened.include?([x, y])
        return false if @wall_ends.include?([x, y])
        return false if @level.solid?(x, y) || @blocks.blocks?(x, y)

        lock = @level.lock_at(x, y)
        lock.nil? || @sight.holds_key?(lock)
      end

      def opened?(cell) = @opened.include?(cell)

      # +secret+ has been pushed.
      def open_secret(secret)
        @opened += secret.opens
        @wall_ends += [secret.wall_ends]
      end

      # The block sees the floor as it would be with this wall pushed.
      def with_secret_open(secret)
        opened = @opened
        wall_ends = @wall_ends
        open_secret(secret)
        yield
      ensure
        @opened = opened
        @wall_ends = wall_ends
      end

      def follow_path_to(goal)
        if goal != @goal || @path.nil? || !@path.include?(@sight.cell)
          @goal = goal
          @path = path_to(goal)
          return press_use unless @path
        end
        ahead = @path[@path.index(@sight.cell) + 1]
        @before_step.call(ahead) if ahead
        return walk_towards(ahead) if ahead

        @path = nil
        [:up]
      end

      # A path picked by the fighting rather than by the goal, which walking goes on along. Answers
      # the first cell of it.
      def set_path_to(cell)
        @path = path_to(cell)
        @path && @path[1]
      end

      def forget_path
        @path = nil
      end

      # One step of the way to +cell+, facing the way it goes.
      def walk_path_to(cell)
        way = path_to(cell)
        way && way[1] ? walk_towards(way[1]) : []
      end

      def walk_towards(ahead)
        error = @sight.view_error_to(ahead[0] + 0.5, ahead[1] + 0.5)
        buttons = @sight.turn_buttons(error, WALK_AIM_VIEW_UNITS)
        return buttons unless error.abs <= WALK_WITHIN_VIEW_UNITS

        buttons + [:up] + run_or_open(ahead)
      end

      # A step in any direction without turning, so the gun stays where it is pointing.
      def step_buttons((x, y))
        error = @sight.view_error_to(x + 0.5, y + 0.5)
        if error.abs <= Sight::VIEW_UNITS_PER_TURN / 8 then [:up]
        elsif error.abs >= Sight::VIEW_UNITS_PER_TURN * 3 / 8 then [:down]
        else [error.positive? ? :r : :l]
        end
      end

      def step_or_open_buttons(cell) = step_buttons(cell) + run_or_open(cell)

      def face_cell_buttons((x, y)) = @sight.turn_buttons(@sight.view_error_to(x + 0.5, y + 0.5), WALK_AIM_VIEW_UNITS)

      # Walls and levers are used from up against them, so it keeps walking while it presses. The
      # block runs on each pass it is lined up.
      def press_into_wall(wanted_view)
        error = @sight.view_error_from(wanted_view)
        buttons = @sight.turn_buttons(error, USE_AIM_VIEW_UNITS)
        return buttons unless error.abs <= USE_AIM_VIEW_UNITS

        yield if block_given?
        buttons << :up
        buttons << :a if @sight.press_at_intervals?
        buttons
      end

      private

      # WHERE ONE CAN WALK DEPENDS ONLY ON WHICH WALLS ARE PUSHED AND WHICH KEYS ARE HELD. One map
      # stands for each of those, and the search for a stash asks about the same few again and again.
      def walk_map = @walk_maps[[@opened, @wall_ends, @sight.keys]] ||= WalkMap.new({}, nil, nil)

      def measure_steps
        steps = {}
        search_floor { |cell, distance, _came_from| steps[cell] = distance }
        steps
      end

      # EVERY CELL THAT CAN BE WALKED TO FROM HERE, nearest first, breadth first with ties broken in
      # the order of FloorReport::STEPS. The block is given each cell, its distance in steps and the
      # trail behind it, and stops the search by leaving. +avoiding+ is any cell the walk must not
      # cross.
      def search_floor(avoiding: nil)
        start = @sight.cell
        came_from = { start => nil }
        distance = { start => 0 }
        queue = [start]
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

      def enterable_neighbours((x, y)) = FloorReport::STEPS.map { |dx, dy| [x + dx, y + dy] }.select { |cell| enterable?(cell) }

      # A DOES BOTH JOBS: held it runs, and pressed it opens a door. A door reads the press on its
      # edge, so it is let go on the way to one, and when walking has stopped getting anywhere.
      def run_or_open(ahead)
        blocked = @level.door?(*ahead) || @sight.stuck_passes > STUCK_PRESS_USE_PASSES
        return [:a] unless blocked

        press_use
      end

      def press_use = @sight.press_at_intervals? ? [:a] : []
    end
  end
end
