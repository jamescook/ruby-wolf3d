# frozen_string_literal: true

module Wolf3D
  class Pilot
    # ONE LIFE ON ONE FLOOR. Made new when a floor starts and when a death puts one back as it was,
    # so all it remembers is true of this go at this floor, and everything goes when it goes. It
    # decides what matters most this pass, and the parts it holds answer the buttons.
    class FloorPlay
      LEVER_WALL_CODE = Elevator::SWITCH
      NEAR_CELLS = 6.0

      def initialize(level:, report:, scenery:, hardest:)
        @level = level
        @route = report.route
        @hardest = hardest
        @way_points = @route.cells.select { |x, y| level.key_at(x, y) } + [@route.cells.last]
        @ambushed = {}
        @sight = Sight.new(level, report.doors)
        @walker = Walker.new(level, scenery, @sight, before_step: method(:ambush_if_crowded))
        @supplies = Supplies.new(scenery, @sight, @walker)
        @gunfight = Gunfight.new(@sight, @walker)
        @boss_fight = BossFight.new(@sight, @walker, @gunfight, @supplies, hardest: hardest)
        @secret_plan = SecretPlan.new(report, @route, @sight, @walker, @supplies)
      end

      # What it was doing when this floor ended, for the report.
      def last_seen
        near = @sight.cell ? @sight.men.count { |man| @sight.distance_to_man(man) < NEAR_CELLS } : 0
        format("last at %s with %d near, gun %d ammo %d", @sight.cell.inspect, near, @sight.best_weapon.to_i, @sight.ammo.to_i)
      end

      def choose_buttons(game, pass:)
        @sight.read(game, pass: pass)
        @boss_fight.note(@sight.guards)
        @gunfight.update
        @boss_fight.update
        return @boss_fight.fight if @boss_fight.awake?

        target = @gunfight.target
        return hold_door(target) if @ambush
        return @gunfight.fight(target) if target && running_past? && @gunfight.blocking_way?(target)
        return travel_firing_at(target) if running_past?
        return travel unless target && @gunfight.reacted_to?(target)

        @gunfight.needs_cover? ? @gunfight.fight_from_corner(target.x, target.y) : @gunfight.fight(target)
      end

      private

      # ON THE HARDEST SETTING THERE ARE MORE MEN THAN BULLETS, so once it has a gun that can clear a
      # way it stops to shoot only at whoever blocks the way. A moving player is also harder to hit.
      def running_past? = @hardest && @sight.best_weapon >= Weapons::MACHINE_GUN

      # Whoever happens to stand in front of a running gun gets shot, at no cost in time.
      def travel_firing_at(target)
        buttons = travel
        return buttons unless target && @sight.ammo > Gunfight::KEEP_ROUNDS

        @sight.in_aim?(target) && @sight.trigger_down? ? buttons + [:b] : buttons
      end

      def ambush_if_crowded(ahead)
        return unless @level.door?(*ahead) && !@ambushed[ahead] && Ambush.worth_holding?(ahead, @sight)

        @ambush = Ambush.new(ahead, @sight, @walker, @gunfight)
      end

      def hold_door(target)
        buttons = @ambush.hold(target)
        return buttons if buttons

        @ambushed[@ambush.door] = true
        @ambush = nil
        @walker.forget_path
        travel
      end

      def travel
        drop_reached_way_points
        goal = choose_goal
        return @secret_plan.push_wall if goal == :push_wall
        return pull_lever if goal == :lever

        @walker.follow_path_to(goal)
      end

      # With the boss dead the floor has nothing left to survive, so it takes his key and leaves.
      def choose_goal
        return way_point if @boss_fight.dead?

        @secret_plan.update
        @secret_plan.goal || @supplies.choose_detour || way_point
      end

      def drop_reached_way_points
        @way_points.shift while @way_points.length > 1 && (@sight.walked?(@way_points.first) || key_held?(@way_points.first))
      end

      def way_point
        goal = @way_points.first
        return :lever if goal == @route.cells.last && @route.ends_at == :lever && @sight.cell == goal
        return goal if @boss_fight.cell.nil? || @sight.holds_key?(FloorReport::BOSS_KEY)

        @boss_fight.cell
      end

      def key_held?(cell)
        key = @level.key_at(*cell)
        !key.nil? && @sight.holds_key?(key)
      end

      def pull_lever
        lever_east = @level.wall_code(@sight.cell[0] + 1, @sight.cell[1]) == LEVER_WALL_CODE
        @walker.press_into_wall(lever_east ? 0 : Sight::VIEW_UNITS_PER_TURN / 2)
      end
    end
  end
end
