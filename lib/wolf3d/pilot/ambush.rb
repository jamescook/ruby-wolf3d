# frozen_string_literal: true

module Wolf3D
  class Pilot
    # A ROOM FULL OF MEN COMES THROUGH A DOOR ONE AT A TIME. So it opens the door, backs off down the
    # way it came with the gun on the opening, and shoots whoever comes through, until nobody has for
    # a while. Then it walks on through what is left.
    class Ambush
      # When a door is worth an ambush, how far back it stands, and how long it waits. Nobody through
      # the door for the quiet passes means nobody is coming.
      LEAST_ROUNDS = 25
      LEAST_MEN = 3
      CROWD_CELLS = 8.0
      BACK_STEPS = 4
      QUIET_PASSES = 120
      MOST_PASSES = 900

      # IS THE ROOM BEHIND THIS DOOR FULL, with a gun to meet it? Only the men in the room on the
      # far side count, by the map's own room numbers (Level#area). Men around the door on its
      # near side are in the room with BJ, and holding the door would have him stand among them
      # with his gun on the empty side.
      def self.worth_holding?(door, sight, level)
        return false unless sight.best_weapon >= Weapons::CHAIN_GUN && sight.ammo >= LEAST_ROUNDS

        here = level.area(*sight.cell)
        beyond = FloorReport::STEPS.filter_map { |dx, dy| level.area(door[0] + dx, door[1] + dy) }.uniq - [here]
        sight.men.count do |man|
          beyond.include?(level.area(man.x.floor, man.y.floor)) && Math.hypot(man.x - door[0], man.y - door[1]) < CROWD_CELLS
        end >= LEAST_MEN
      end

      attr_reader :door

      def initialize(door, sight, walker, gunfight)
        @door = door
        @sight = sight
        @walker = walker
        @gunfight = gunfight
        @spot = spot_in_line_with(door) || sight.cell
        @stage = :opening
        @quiet_passes = 0
        @passes = 0
      end

      # The buttons for this pass, or nil when the ambush is over.
      def hold(target)
        @passes += 1
        return nil if @passes > MOST_PASSES || @sight.ammo < Gunfight::KEEP_ROUNDS

        case @stage
        when :opening then open_door
        when :backing then back_to_spot(target)
        else shoot_through_door(target)
        end
      end

      private

      def spot_in_line_with((door_x, door_y))
        @sight.trail.last(BACK_STEPS).find { |x, y| @sight.clear_line?(x + 0.5, y + 0.5, door_x + 0.5, door_y + 0.5) }
      end

      def open_door
        if @sight.door_ajar?(@door)
          @stage = :backing
          return []
        end
        buttons = @walker.face_cell_buttons(@door) + [:up]
        @sight.press_at_intervals? ? buttons + [:a] : buttons
      end

      def back_to_spot(target)
        if @sight.cell == @spot
          @stage = :holding
          return []
        end
        way = @walker.path_to(@spot)
        return shoot_through_door(target) unless way && way[1]

        buttons = @walker.face_cell_buttons(@door) + @walker.step_buttons(way[1])
        target && @sight.in_aim?(target) && @sight.trigger_down? ? buttons + [:b] : buttons
      end

      def shoot_through_door(target)
        if target
          @quiet_passes = 0
          return @gunfight.fight(target)
        end
        @quiet_passes += 1
        return nil if @quiet_passes > QUIET_PASSES

        @walker.face_cell_buttons(@door)
      end
    end
  end
end
