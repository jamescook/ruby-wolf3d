# frozen_string_literal: true

module Wolf3D
  class Pilot
    # A BOSS IS BEATEN FROM A STOCK. On the easiest setting it fights him from beside a corner: out to
    # shoot, back in when hurt. On the hardest he outlasts that, so it holds him at range and keeps
    # moving, and runs for what is left of the stock when short.
    class BossFight
      # THE FEWEST HIT POINTS A BOSS STARTS WITH, on any setting. The pool of guards does not say
      # what kind a man is, but no ordinary man has this many. Pac-Man's ghosts are bosses by the
      # table and have none, for they cannot be shot.
      LEAST_HIT_POINTS = Enemy::ALL.select(&:boss?).flat_map(&:hit_points).select(&:positive?).min

      SEEN_CELLS = 10.0
      MOVED_CELLS = 0.3

      # The range it holds a boss at, how long one strafe lasts, and when it goes for more stock.
      KITE_NEAR_CELLS = 8.0
      KITE_FAR_CELLS = 11.0
      KITE_STRAFE_PASSES = 20
      KITE_STRAFE_CELLS = 0.7
      KITE_HEALTH_BELOW = 50
      KITE_ROUNDS_BELOW = 25

      # The cell he stands in, or nil until he has been read.
      attr_reader :cell

      def initialize(sight, walker, gunfight, supplies, hardest:)
        @sight = sight
        @walker = walker
        @gunfight = gunfight
        @supplies = supplies
        @hardest = hardest
        @hit_points = 0
        @full_hit_points = 0
        @seen = false
      end

      # Find him among +guards+, every slot in use, and note where he is.
      def note(guards)
        guards.each do |guard|
          @number = guard.number if @number.nil? && guard.hit_points >= LEAST_HIT_POINTS
          note_position(guard) if guard.number == @number
        end
      end

      # Has he been seen yet?
      def update
        return unless @at && @hit_points.positive?

        @seen ||= @hit_points < @full_hit_points ||
                  Math.hypot(@at[0] - @home[0], @at[1] - @home[1]) > MOVED_CELLS ||
                  (@sight.distance_to(*@at) < SEEN_CELLS && @sight.clear_line_to?(*@at))
      end

      def awake? = !@at.nil? && @hit_points.positive? && @seen
      def dead? = !@number.nil? && !@hit_points.positive?

      def fight = @hardest ? kite(*@at) : @gunfight.fight_from_corner(*@at)

      private

      def note_position(guard)
        @at = [guard.x, guard.y]
        @cell = [guard.x.floor, guard.y.floor]
        @hit_points = guard.hit_points
        @full_hit_points = [@full_hit_points, guard.hit_points].max
        @home ||= @at
      end

      # ON THE HARDEST SETTING NO CORNER SAVES YOU: he has more hit points than a fight of peeking
      # leaves bullets for. What saves you is T_Shoot's sums. From six cells a shot of his does a
      # quarter of the harm one does beside you, and a running player is harder to hit. So it keeps
      # him at range, gun on him, and never stands still.
      def kite(x, y)
        supply = nearest_supply
        return @walker.follow_path_to(supply) if supply

        distance = @sight.distance_to(x, y)
        sees_him = @sight.clear_line_to?(x, y)
        error = @sight.view_error_to(x, y)
        tolerance = @sight.aim_tolerance(distance)
        buttons = @sight.turn_buttons(error, tolerance)
        buttons << :b if sees_him && error.abs <= tolerance && @sight.trigger_down?
        @firing_cell = @sight.cell if sees_him && distance >= KITE_NEAR_CELLS
        return buttons + approach_buttons(approach_cell(x, y)) if !sees_him || distance > KITE_FAR_CELLS

        away = distance < KITE_NEAR_CELLS ? step_away_from(x, y) : nil
        buttons + (away || strafe_buttons(x, y)) + [:a]
      end

      # Run for what is left of the stock, turning its back on him to get there.
      def nearest_supply
        kinds = []
        kinds << :health if @sight.health < KITE_HEALTH_BELOW
        kinds << :ammunition if @sight.ammo < KITE_ROUNDS_BELOW
        return if kinds.empty?

        @supplies.nearest_of_kinds(kinds)
      end

      # OUT OF HIS SIGHT IT GOES BACK TO WHERE IT LAST HAD A SHOT FROM, at range. Walking on towards
      # him is only for when that place shows nothing either, which means his door has shut: beside
      # him is where his chain gun does its worst.
      def approach_cell(x, y)
        return @firing_cell if @firing_cell && @firing_cell != @sight.cell

        [x.floor, y.floor]
      end

      def approach_buttons(cell)
        way = @walker.path_to(cell)
        return [] unless way && way[1]

        @walker.step_or_open_buttons(way[1])
      end

      def step_away_from(x, y)
        farthest = @walker.neighbours(@sight.cell).max_by { |cell| Math.hypot(cell[0] + 0.5 - x, cell[1] + 0.5 - y) }
        return unless farthest && Math.hypot(farthest[0] + 0.5 - x, farthest[1] + 0.5 - y) > @sight.distance_to(x, y)

        @walker.step_buttons(farthest)
      end

      # Side to side and back, as long as the step still has a line to him. A step that loses him is
      # a step back towards his gun, so it holds its place instead.
      def strafe_buttons(x, y)
        side = (@sight.pass % (KITE_STRAFE_PASSES * 2)) < KITE_STRAFE_PASSES ? :l : :r
        strafe_keeps_line?(side, x, y) ? [side] : []
      end

      def strafe_keeps_line?(side, x, y)
        across = (@sight.view * 2 * Math::PI / Sight::VIEW_UNITS_PER_TURN) + (side == :l ? -Math::PI / 2 : Math::PI / 2)
        @sight.clear_line?(@sight.x + (Math.cos(across) * KITE_STRAFE_CELLS), @sight.y + (Math.sin(across) * KITE_STRAFE_CELLS), x, y)
      end
    end
  end
end
