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

      # A man this near is fought even by a player running past the rest.
      CLOSE_BY_CELLS = 4.0

      # How long it can stand in one cell before whoever is near counts as in the way.
      STUCK_SHOOT_PASSES = 8

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

      # How long a man who stepped out of sight stays where it thinks he is.
      REMEMBER_PASSES = 120

      attr_reader :target

      def initialize(sight, walker)
        @sight = sight
        @walker = walker
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
          @men_in_sight = men_in_view
          @target = pick_target(@men_in_sight)
          @target_number = @target&.number
        end
        @sight_passes = @target ? @sight_passes + 1 : 0
        note_last_seen
      end

      # WHERE IT LAST SAW THE MAN IT WAS FIGHTING, while that is fresh and he is still standing. Out
      # of sight behind a doorway he is not forgotten: it keeps the gun on that spot and steps out
      # to it again.
      def last_seen
        return nil unless @last_seen && @passes_unseen <= REMEMBER_PASSES
        return nil unless @sight.men.any? { |man| man.number == @last_seen_number }

        @last_seen
      end

      def blocking_way?(man)
        @sight.distance_to_man(man) < POINT_BLANK_CELLS || @sight.stuck_passes > STUCK_SHOOT_PASSES
      end

      def close_by?(man) = @sight.distance_to_man(man) < CLOSE_BY_CELLS

      def reacted_to?(man)
        @sight_passes >= REACTION_PASSES || @sight.hurt? || @sight.distance_to_man(man) < POINT_BLANK_CELLS
      end

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

      # HIT AND RUN. Out sideways to shoot and back in when hurt, the gun on him while it can see
      # him. With a wall between them the view stays on the spot it last saw him or was told of,
      # and never follows him through the wall.
      def fight_from_corner(x, y)
        @fight_passes += 1
        in_his_sight = @sight.clear_line_to?(x, y)
        hiding = @sight.health < PEEK_FROM_HEALTH && (@sight.pass % PEEK_PASSES) >= PEEK_OUT_PASSES
        return hiding ? [] : step_into_sight(x, y) unless in_his_sight

        error = @sight.view_error_to(x, y)
        tolerance = @sight.aim_tolerance(@sight.distance_to(x, y))
        buttons = @sight.turn_buttons(error, tolerance)
        buttons << :b if error.abs <= tolerance && @sight.trigger_down?
        hiding ? buttons + step_into_cover(x, y) : buttons
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

      # Whoever it can see in front of it. A wound says somebody is there, so while it hurts it turns
      # to a man beside or behind it as well.
      def men_in_view
        @sight.men.select do |man|
          @sight.distance_to_man(man) < SIGHT_CELLS && (@sight.on_guard? || @sight.in_view?(man.x, man.y)) &&
            @sight.clear_line_to?(man.x, man.y)
        end
      end

      # It finishes the man it is shooting: turning to whoever is nearest this moment wastes the gun.
      def pick_target(men)
        men.find { |man| man.number == @target_number } || men.min_by { |man| @sight.distance_to_man(man) }
      end

      def note_last_seen
        if @target
          @last_seen = [@target.x, @target.y]
          @last_seen_number = @target.number
          @passes_unseen = 0
        elsif @last_seen
          @passes_unseen += 1
        end
      end

      # A MAN WHO SEES YOU TAKES A MOMENT TO SHOOT, and so does turning. So it turns behind cover, and
      # steps out sideways only once the gun is on the spot: the first pass he is in line is a shot.
      def step_into_sight(x, y)
        error = @sight.view_error_to(x, y)
        tolerance = @sight.aim_tolerance(@sight.distance_to(x, y))
        return @sight.turn_buttons(error, tolerance) if error.abs > tolerance

        first_step = first_step_to_line(x, y, wants_line: true) || @walker.set_path_to([x.floor, y.floor])
        return [] unless first_step

        buttons = @walker.step_or_open_buttons(first_step)
        pull_early?(first_step, x, y) ? buttons + [:b] : buttons
      end

      # A GUN FIRES A STAGE AFTER ITS TRIGGER (Weapons::STAGE_PASSES), so the trigger goes down
      # behind cover when the very next step is into his line: the round leaves as it arrives,
      # not a stage later while he has it in his sights.
      def pull_early?(step, x, y)
        @sight.ammo.positive? && @sight.trigger_down? && @sight.clear_line?(step[0] + 0.5, step[1] + 0.5, x, y)
      end

      def step_into_cover(x, y)
        first_step = first_step_to_line(x, y, wants_line: false) || @walker.set_path_to([x.floor, y.floor])
        first_step ? @walker.step_or_open_buttons(first_step) : []
      end

      # The first step to the nearest cell that has a line to him, or has none.
      def first_step_to_line(x, y, wants_line:)
        beside_him = ->((cell_x, cell_y)) { Math.hypot(cell_x + 0.5 - x, cell_y + 0.5 - y) < PEEK_NEAREST_CELLS }
        @walker.first_step_towards_nearest(within: PEEK_STEPS, avoiding: beside_him) do |cell|
          @sight.clear_line?(cell[0] + 0.5, cell[1] + 0.5, x, y) == wants_line
        end
      end
    end
  end
end
