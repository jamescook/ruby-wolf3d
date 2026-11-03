# frozen_string_literal: true

module Wolf3D
  class Pilot
    # WHAT THE PILOT KNOWS OF THE RUNNING GAME THIS PASS, and what can be worked out from it alone:
    # where it is, who is about, what lies in a straight line, and which way to turn to face a place.
    # Everything else in the Pilot reads the game through this, one floor's worth at a time.
    class Sight
      # One of the men on the floor. +number+ is his slot in the pool of guards.
      Man = Data.define(:x, :y, :hit_points, :number) do
        def alive? = hit_points.positive?
      end

      # What the running game keeps its fractions in, and what a full turn is on `view`.
      FIXED_POINT_SCALE = 1 << VBlank::DSL::Fraction::DEFAULT_BITS
      VIEW_UNITS_PER_TURN = 1024

      # `view` moves in tens with A held (FirstPerson::TURN_UNITS_RUNNING), so a target narrower than
      # half of that can be stepped over.
      FINEST_AIM_VIEW_UNITS = 7
      GUARD_HALF_WIDTH_CELLS = 0.12

      # The turn is held less often near the target, so it does not swing past.
      GENTLE_TURN_VIEW_UNITS = 60

      # How long a wound keeps it alert, and how often in play it presses a button read on its edge.
      HURT_PASSES = 30
      PRESS_EVERY_PASSES = 8

      # HOW FAR ROUND IT NOTICES A MAN. Wider than FirstPerson::HALF_VIEW, for a person playing sees the
      # edge of a narrow picture, moves, and turns: a man just off the screen is one a turn away. A
      # man behind it is not seen at all.
      SEEN_HALF_VIEW_UNITS = VIEW_UNITS_PER_TURN / 6

      # How long after a wound it looks for whoever gave it, beside it or behind it. A man shoots far
      # less often than HURT_PASSES, so one at its back would otherwise be forgotten between shots.
      ON_GUARD_PASSES = 150

      MOST_SLOPE = GuardMind::MOST_SLOPE

      attr_reader :x, :y, :view, :cell, :health, :ammo, :keys, :weapon, :best_weapon, :pass,
                  :stuck_passes, :trail, :men, :guards, :drops

      def initialize(level, doors)
        @level = level
        @door_numbers = doors.each_with_index.to_h
        @men = []
        @guards = []
        @drops = []
        @walked = {}
        @trail = []
        @stuck_passes = 0
        @hurt_passes = 0
        @on_guard_passes = 0
      end

      # What the game says this pass. Men and doors cost far more to read than the player, so they
      # are read every other pass, unless nobody has been found yet.
      def read(game, pass:)
        @pass = pass
        read_player(game)
        read_men(game) if pass.even? || @men.empty?
      end

      def hurt? = @hurt_passes.positive?

      # Somebody has shot it, so it looks round for him whichever way he is.
      def on_guard? = @on_guard_passes.positive?
      def walked?(cell) = @walked.key?(cell)

      # Has the game taken this piece off the floor? +number+ is its place in Scenery#pieces. Walking
      # over a piece says nothing: a full player leaves it lying (Pickups).
      def thing_gone?(number) = !@things_gone[number].to_i.zero?

      def holds_key?(key) = @keys.anybits?(FirstPerson::KEY_BITS.fetch(key))

      def distance_to(x, y) = Math.hypot(x - @x, y - @y)
      def distance_to_man(man) = distance_to(man.x, man.y)

      # IS THERE A LINE BETWEEN BJ, STANDING AT +from+, AND A MAN AT +x+, +y+? The game's own answer:
      # the original's CheckLine, walked from the man, a column at a time and then a row at a time
      # (GuardMind#walk_the_sight_line).
      def clear_line?(from_x, from_y, x, y)
        crossings_clear?(x, y, from_x, from_y) { |cell_x, cell_y, middle| see_through?(cell_x, cell_y, middle) } &&
          crossings_clear?(y, x, from_y, from_x) { |cell_y, cell_x, middle| see_through?(cell_x, cell_y, middle) }
      end

      def clear_line_to?(x, y) = clear_line?(@x, @y, x, y)

      def in_view?(x, y) = view_error_to(x, y).abs <= SEEN_HALF_VIEW_UNITS

      # Has this door started to open at all?
      def door_ajar?(cell) = @doors_open[@door_numbers.fetch(cell)].to_i.positive?

      # How far `view` is from pointing at a place, the short way round.
      def view_error_to(x, y)
        wanted = (Math.atan2(y - @y, x - @x) / (2 * Math::PI) * VIEW_UNITS_PER_TURN).round
        view_error_from(wanted)
      end

      def view_error_from(wanted) = ((wanted - @view + (VIEW_UNITS_PER_TURN / 2)) % VIEW_UNITS_PER_TURN) - (VIEW_UNITS_PER_TURN / 2)

      def turn_buttons(error, tolerance)
        return [] if error.abs <= tolerance
        return [] if error.abs < GENTLE_TURN_VIEW_UNITS && @pass.odd?

        [error.positive? ? :right : :left]
      end

      def aim_tolerance(distance)
        [(Math.atan2(GUARD_HALF_WIDTH_CELLS, distance) / (2 * Math::PI) * VIEW_UNITS_PER_TURN).round, FINEST_AIM_VIEW_UNITS].max
      end

      def in_aim?(man) = view_error_to(man.x, man.y).abs <= aim_tolerance(distance_to_man(man))

      # A TRIGGER IS READ ON ITS EDGE, so a gun at rest needs the button let go between presses, and
      # an automatic in the middle of its cycle needs it held to go round again (Weapons).
      def trigger_down?
        return @weapon >= Weapons::MACHINE_GUN if @attack_stage >= 0

        @pass.even?
      end

      def press_at_intervals? = (@pass % PRESS_EVERY_PASSES).zero?

      private

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
        just_hurt = @last_health && @health < @last_health
        @hurt_passes = just_hurt ? HURT_PASSES : [@hurt_passes - 1, 0].max
        @on_guard_passes = just_hurt ? ON_GUARD_PASSES : [@on_guard_passes - 1, 0].max
        @last_health = @health
        note_cell([@x.floor, @y.floor])
      end

      def note_cell(cell)
        @cell = cell
        @walked[cell] = true
        @stuck_passes = cell == @last_cell ? @stuck_passes + 1 : 0
        @trail << cell unless cell == @last_cell
        @last_cell = cell
      end

      # +guards+ is every slot in use, the fallen too, for only they say where a boss ended. +men+ is
      # those still standing.
      def read_men(game)
        @doors_open = game.list(:door_open)
        @things_gone = game.list(:thing_gone)
        xs, ys, hit_points, dropped = %i[x y hp dropped].map { |field| game.pool(:guard, field) }
        slots = xs.each_index.select { |n| xs[n] }
        @guards = slots.map do |n|
          Man.new(x: xs[n] / FIXED_POINT_SCALE.to_f, y: ys[n] / FIXED_POINT_SCALE.to_f, hit_points: hit_points[n].to_i, number: n)
        end
        @men = @guards.select(&:alive?)
        @drops = slots.zip(@guards).select { |n, _| dropped[n].to_i.nonzero? }.map { |_, man| [man.x.floor, man.y.floor] }
      end

      # ONE OF CheckLine's TWO WALKS, a column (or a row) at a time from the man toward BJ. +along+
      # is the axis it steps on and +across+ the other; the block is given each cell entered, as
      # [along, across], and the line's crossing at the middle of that step.
      def crossings_clear?(along_from, across_from, along_to, across_to)
        cell = along_from.floor
        last = along_to.floor
        return true if cell == last

        way = last > cell ? 1 : -1
        slope = ((across_to - across_from) / (along_to - along_from).abs).clamp(-MOST_SLOPE, MOST_SLOPE)
        edge = along_from - cell
        edge = 1 - edge if way == 1
        cross = across_from + (slope * edge)
        loop do
          cell += way
          across = cross.floor
          cross += slope
          return false unless yield(cell, across, cross - (slope / 2))
          return true if cell == last
        end
      end

      def see_through?(x, y, middle) = !@level.solid?(x, y) && (!@level.door?(x, y) || door_open_at?(x, y, middle))

      # A DOOR IS SEEN THROUGH WHERE A GUARD SEES THROUGH IT, with the original's slip: the line's
      # crossing, counted from the map's edge in cells, against how far open the door is times 256
      # (GuardMind#blocked_by). Any other door would have it think itself behind cover while the
      # man on the other side shoots it.
      def door_open_at?(x, y, middle)
        number = @door_numbers[[x, y]]
        return false unless number && @doors_open

        middle <= @doors_open[number].to_i * 256.0 / FIXED_POINT_SCALE
      end
    end
  end
end
