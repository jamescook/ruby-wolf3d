# frozen_string_literal: true

module Wolf3D
  class Pilot
    # WHICH SECRET WALL TO OPEN AND WHAT TO TAKE FROM BEHIND IT. A floor with a better gun behind a
    # wall has that opened first. After that it opens a wall when short, and on the floor that ends
    # at an exit, which is a boss's, it stocks up with everything before going on.
    class SecretPlan
      # A SECRET WALL WORTH OPENING: the one that stands between here and a better gun. +from+ is
      # where to push it, +view+ which way that faces, +opens+ the cells it leaves and +wall_ends+
      # where it stops, which stays shut. A wall slides two cells, or one with something behind it.
      Secret = Data.define(:wall, :from, :view, :opens, :wall_ends)
      VIEWS = Ractor.make_shareable({ [1, 0] => 0, [0, 1] => 256, [-1, 0] => 512, [0, -1] => 768 })

      PUSH_PASSES = 35

      # When a stash behind a secret wall is worth the walk.
      STASH_AMMO_BELOW = 40
      STASH_HEALTH_BELOW = 70
      STASH_STEPS = 30
      STASH_PIECES = 3

      def initialize(report, route, sight, walker, supplies)
        @report = report
        @ends_at_exit = route.ends_at == :exit
        @sight = sight
        @walker = walker
        @supplies = supplies
        @stage = :planning
        @stash = []
        @pushing_passes = 0
      end

      # Look for a wall to open if it is time to, and move on from what is finished.
      def update
        look_for_secret if @stage == :planning || (@stage == :on_foot && @sight.cell != @searched_from)
        @stage = :on_foot if taking_pieces? && next_piece.nil?
      end

      # Where this plan wants to be: a cell, :push_wall when up against the wall, or nil.
      def goal
        case @stage
        when :to_secret then @sight.cell == @secret.from || @pushing_passes.positive? ? :push_wall : @secret.from
        when :stocking, :looting then next_piece
        end
      end

      def push_wall
        @walker.press_into_wall(@secret.view) do
          @pushing_passes += 1
          finish_push if @pushing_passes > PUSH_PASSES
        end
      end

      private

      def taking_pieces? = %i[stocking looting].include?(@stage)

      # The nearest piece of what this stage is after that is still worth having.
      def next_piece
        pieces = @stage == :stocking ? @supplies.pieces : @stash
        @supplies.nearest(pieces.select { |piece| @supplies.stock?(piece) })
      end

      def look_for_secret
        @searched_from = @sight.cell
        @secret = secret_to_better_gun || secret_to_stash
        @stage = if @secret then :to_secret
                 elsif @stage == :planning && @ends_at_exit then :stocking
                 else :on_foot
                 end
      end

      def secret_to_better_gun
        guns = @supplies.better_gun_cells
        walkable = @walker.steps_from_here
        return nil if guns.empty? || guns.any? { |cell| walkable[cell] }

        secrets_from(walkable).find do |secret|
          reachable = @walker.with_secret_open(secret) { @walker.steps_from_here }
          guns.any? { |cell| reachable[cell] }
        end
      end

      # THE FLOORS KEEP THEIR SUPPLIES BEHIND SECRET WALLS, often beside the way through. Short of
      # bullets or health, it opens one that is close and has enough behind it to pay for the walk.
      def secret_to_stash
        return unless @ends_at_exit || @sight.ammo < STASH_AMMO_BELOW || @sight.health < STASH_HEALTH_BELOW

        walkable = @walker.steps_from_here
        close_by = secrets_from(walkable).select { |secret| @ends_at_exit || walkable[secret.from] <= STASH_STEPS }
        close_by.find { |secret| stash_behind(secret).count { |piece| @supplies.stock?(piece) } >= STASH_PIECES }
      end

      # What opening this wall would put within reach that is out of reach now.
      def stash_behind(secret)
        walkable = @walker.steps_from_here
        reachable = @walker.with_secret_open(secret) { @walker.steps_from_here }
        @supplies.pieces.select do |piece|
          cell = Supplies.cell_of(piece)
          reachable[cell] && !walkable[cell]
        end
      end

      def secrets_from(walkable)
        walls = @report.pushwalls.reject { |wall| @walker.opened?([wall.x, wall.y]) }
        walls.flat_map { |wall| FloorReport::STEPS.filter_map { |dx, dy| secret_at(wall, dx, dy, walkable) } }
      end

      def secret_at(wall, dx, dy, walkable)
        from = [wall.x - dx, wall.y - dy]
        beyond = [wall.x + dx, wall.y + dy]
        further = [wall.x + (2 * dx), wall.y + (2 * dy)]
        return unless walkable[from] && @walker.enterable?(beyond)

        opens = @walker.enterable?(further) ? [[wall.x, wall.y], beyond] : [[wall.x, wall.y]]
        Secret.new(wall: [wall.x, wall.y], from: from, view: VIEWS.fetch([dx, dy]), opens: opens,
                   wall_ends: @walker.enterable?(further) ? further : beyond)
      end

      def finish_push
        @stash = stash_behind(@secret)
        @walker.open_secret(@secret)
        @pushing_passes = 0
        @stage = @ends_at_exit ? :stocking : :looting
      end
    end
  end
end
