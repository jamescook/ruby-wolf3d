# frozen_string_literal: true

module Wolf3D
  class Pilot
    # ONE LIFE ON ONE FLOOR. Made new when a floor starts and when a death puts one back as it was,
    # so all it remembers is true of this go at this floor, and everything goes when it goes. Each
    # pass its parts read the game, its Strategy picks a tactic, and it carries the tactic out.
    class FloorPlay
      LEVER_WALL_CODE = Elevator::SWITCH

      # +strategy+ is the Strategy subclass for the setting being played.
      def initialize(level:, report:, scenery:, strategy:)
        @level = level
        @route = report.route
        @way_points = @route.cells.select { |x, y| level.key_at(x, y) } + [@route.cells.last]
        @ambushed = {}
        @sight = Sight.new(level, report.doors)
        @walker = Walker.new(level, scenery, @sight, before_step: method(:ambush_if_crowded))
        @supplies = Supplies.new(scenery, @sight, @walker)
        @gunfight = Gunfight.new(@sight, @walker)
        @boss_fight = BossFight.new(@sight, @walker, @gunfight, @supplies)
        @secret_plan = SecretPlan.new(report, @route, @sight, @walker, @supplies)
        @strategy = strategy.new(level: level, sight: @sight, gunfight: @gunfight, boss_fight: @boss_fight)
      end

      # What it chose to do on the last pass, one of TACTICS. The run log reads it.
      attr_reader :tactic

      # Every tactic a strategy can choose, and what each is:
      #   boss_fight        the boss, from beside a corner
      #   kite_boss         the boss, held at range and circled
      #   hold_door         an Ambush under way
      #   clear_way         stand and shoot a man in the way
      #   run_past          walk on, shooting whoever happens to be in front
      #   hunt              back out to where a man it was fighting was last seen
      #   travel            walk on
      #   fight_in_open     stand and shoot, walking at him with no rounds
      #   fight_from_cover  out sideways to shoot, back in when hurt
      TACTICS = %i[boss_fight kite_boss hold_door clear_way run_past hunt travel fight_in_open fight_from_cover].freeze

      def choose_buttons(game, pass:)
        @sight.read(game, pass: pass)
        @boss_fight.note(@sight.guards)
        @gunfight.update
        @boss_fight.update
        target = @gunfight.target
        @tactic = @strategy.choose_tactic(target, holding_door: !@ambush.nil?)
        case @tactic
        when :boss_fight then @boss_fight.fight_from_corner
        when :kite_boss then @boss_fight.kite
        when :hold_door then hold_door(target)
        when :clear_way, :fight_in_open then @gunfight.fight(target)
        when :run_past then travel_firing_at(target)
        when :hunt then @gunfight.fight_from_corner(*@gunfight.last_seen)
        when :travel then travel
        else @gunfight.fight_from_corner(target.x, target.y)
        end
      end

      private

      # Whoever happens to stand in front of a running gun gets shot, at no cost in time.
      def travel_firing_at(target)
        buttons = travel
        return buttons unless target && @sight.ammo > Gunfight::KEEP_ROUNDS

        @sight.in_aim?(target) && @sight.trigger_down? ? buttons + [:b] : buttons
      end

      def ambush_if_crowded(ahead)
        return unless @level.door?(*ahead) && !@ambushed[ahead] && @strategy.hold_door?(ahead)

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
