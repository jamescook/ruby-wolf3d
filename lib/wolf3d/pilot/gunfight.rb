# frozen_string_literal: true

module Wolf3D
  class Pilot
    # WHO TO SHOOT AND HOW. Each pass it settles on the man to deal with, and it answers the buttons
    # for shooting him where it stands or from behind something.
    class Gunfight
      SIGHT_CELLS = 11.0

      # How long a person takes to react, and how near a man has to be for it to shoot sooner.
      REACTION_PASSES = 15
      POINT_BLANK_CELLS = 2.0

      # How long it can stand in one cell before whoever is near counts as in the way.
      STUCK_SHOOT_PASSES = 8

      # Below this, every fight is from behind something.
      COVER_BELOW_HEALTH = 70

      # This much shooting that hurts nobody means a man behind something, so it ignores everybody
      # for half as long and walks on.
      FUTILE_FIGHT_PASSES = 300
      IGNORE_MEN_PASSES = 150

      # Rounds it will not spend on anybody who is not in the way.
      KEEP_ROUNDS = 15

      # With no bullets it walks at the man, once it is this nearly facing him.
      WALK_INTO_FIGHT_VIEW_UNITS = Walker::WALK_WITHIN_VIEW_UNITS / 2

      # OUT FOR THIRTY-FIVE PASSES IN EVERY FIFTY-FIVE, once it has been hurt at all, and it looks
      # this far for a corner. It never picks a cell this close to the man, for he stops you walking
      # there.
      PEEK_PASSES = 55
      PEEK_OUT_PASSES = 35
      PEEK_FROM_HEALTH = 90
      PEEK_STEPS = 5
      PEEK_NEAREST_CELLS = 1.6

      attr_reader :target, :target_number

      def initialize(sight, walker, target_number:)
        @sight = sight
        @walker = walker
        @target_number = target_number
        @sight_passes = 0
        @fight_passes = 0
        @ignore_men_passes = 0
        @men_in_sight = []
      end

      # Settle who the target is this pass, unless shooting has stopped doing any good.
      def update
        start_ignoring_men_after_futile_fight
        if @ignore_men_passes.positive?
          @ignore_men_passes -= 1
          @men_in_sight = []
          @target = nil
        else
          @men_in_sight = men_with_clear_line
          @target = pick_target(@men_in_sight)
          @target_number = @target&.number
        end
        @sight_passes = @target ? @sight_passes + 1 : 0
      end

      def blocking_way?(man)
        @sight.distance_to_man(man) < POINT_BLANK_CELLS || @sight.stuck_passes > STUCK_SHOOT_PASSES
      end

      def reacted_to?(man)
        @sight_passes >= REACTION_PASSES || @sight.hurt? || @sight.distance_to_man(man) < POINT_BLANK_CELLS
      end

      def needs_cover? = @sight.health < COVER_BELOW_HEALTH || @men_in_sight.length > 1

      # Stand and shoot.
      def fight(man)
        @fight_passes += 1
        distance = @sight.distance_to_man(man)
        error = @sight.view_error_to(man.x, man.y)
        tolerance = @sight.aim_tolerance(distance)
        buttons = @sight.turn_buttons(error, tolerance)
        buttons << :b if error.abs <= tolerance && @sight.trigger_down?
        buttons << :up if @sight.ammo.zero? && error.abs < WALK_INTO_FIGHT_VIEW_UNITS
        buttons
      end

      # Out to shoot and back in when hurt, keeping the gun on him all the while.
      def fight_from_corner(x, y)
        error = @sight.view_error_to(x, y)
        tolerance = @sight.aim_tolerance(@sight.distance_to(x, y))
        in_his_sight = @sight.clear_line_to?(x, y)
        hiding = @sight.health < PEEK_FROM_HEALTH && (@sight.pass % PEEK_PASSES) >= PEEK_OUT_PASSES
        buttons = @sight.turn_buttons(error, tolerance)
        buttons << :b if in_his_sight && error.abs <= tolerance && @sight.trigger_down?
        return buttons if in_his_sight != hiding

        buttons + step_to_cover_or_sight(x, y, !hiding)
      end

      private

      def start_ignoring_men_after_futile_fight
        total = @sight.men.sum(&:hit_points)
        @fight_passes = 0 if total != @hit_points_left
        @hit_points_left = total
        return unless @fight_passes > FUTILE_FIGHT_PASSES

        @ignore_men_passes = IGNORE_MEN_PASSES
        @fight_passes = 0
      end

      def men_with_clear_line
        @sight.men.select { |man| @sight.distance_to_man(man) < SIGHT_CELLS && @sight.clear_line_to?(man.x, man.y) }
      end

      # It finishes the man it is shooting: turning to whoever is nearest this moment wastes the gun.
      def pick_target(men)
        men.find { |man| man.number == @target_number } || men.min_by { |man| @sight.distance_to_man(man) }
      end

      def step_to_cover_or_sight(x, y, wants_sight)
        beside_him = ->((cell_x, cell_y)) { Math.hypot(cell_x + 0.5 - x, cell_y + 0.5 - y) < PEEK_NEAREST_CELLS }
        first_step = @walker.first_step_towards_nearest(within: PEEK_STEPS, avoiding: beside_him) do |cell|
          @sight.clear_line?(cell[0] + 0.5, cell[1] + 0.5, x, y) == wants_sight
        end
        first_step ||= @walker.set_path_to([x.floor, y.floor])
        first_step ? @walker.step_or_open_buttons(first_step) : []
      end
    end
  end
end
