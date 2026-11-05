# frozen_string_literal: true

module Wolf3D
  # WHAT A FLOOR HOLDS, AND A WAY THROUGH IT, read from the map with nothing played. A person or a
  # script planning a run wants the same few things: where you start, what lies about, who stands
  # where, and a route to the way out. tools/floor_report.rb prints this for a whole copy of the
  # game.
  #
  # A ROUTE IS A SEARCH OVER WHERE YOU ARE AND WHICH KEYS YOU CARRY, one cell at a time, because
  # the same cell is a different place once you hold the key to the door beside it. It takes the
  # fewest cells, so it can walk away from the door it wants, fetch the key and come back.
  #
  # IT DOES NOT PUSH SECRET WALLS, and it walks past guards as if they were not there. Getting past
  # them is what the run is for; this says only that the floor can be finished.
  class FloorReport
    # Which way a floor ended up being left.
    Route = Data.define(:cells, :ends_at)

    # The four cells next to one, in the order a tie is broken.
    STEPS = Ractor.make_shareable([[1, 0], [0, 1], [-1, 0], [0, -1]])

    # Cmd_Use (wl_agent.cpp) takes a lever only when you face east or west at it, so these are the
    # two sides it can be pulled from.
    LEVER_SIDES = Ractor.make_shareable([[-1, 0], [1, 0]])

    # Every boss leaves the gold key behind him, and on the floors that have one that is the key
    # to the way out, so no key lies on the floor for it.
    BOSS_KEY = :gold

    def initialize(level)
      @level = level
      @scenery = Scenery.new(level)
      @guards = Guards.new(level)
      @lifts = Elevator.new(level)
    end

    def start = @level.start

    # Everything a walk over it gives you.
    def pickups = @scenery.pieces.select(&:bonus)

    # Who stands on this floor when the game is set to +difficulty+.
    def guards(difficulty) = @guards.at(difficulty)

    def doors = @level.each_cell.select { |x, y| @level.door?(x, y) }
    def pushwalls = Pushwalls.new(@level).walls

    # The way from the start to the nearest way out, or nil when a floor has none that can be
    # walked to.
    def route
      goals = way_out_cells
      first = [start.x, start.y, keys_from([], start.x, start.y).freeze]
      came_from = { first => nil }
      queue = [first]
      until queue.empty?
        here = queue.shift
        return route_to(here, came_from, goals) if goals.key?(here.first(2))

        steps_from(here).each do |step|
          next if came_from.key?(step)

          came_from[step] = here
          queue << step
        end
      end
      nil
    end

    private

    def route_to(here, came_from, goals)
      cells = []
      while here
        cells.unshift(here.first(2))
        here = came_from[here]
      end
      Route.new(cells: cells, ends_at: goals.fetch(cells.last))
    end

    # The cells that finish the floor. A lift that goes to the secret floor is left out while the
    # ordinary one can be had, because the run is the ordinary way down.
    def way_out_cells
      goals = @level.exits.to_h { |cell| [cell, :exit] }
      lever_cells.each { |cell| goals[cell] ||= :lever }
      goals
    end

    def lever_cells
      cells = @lifts.levers.flat_map { |lever| LEVER_SIDES.map { |dx, dy| [lever.x + dx, lever.y + dy] } }
                    .select { |x, y| standable?(x, y) }
      ordinary = cells.reject { |x, y| @lifts.secret_cars.include?((y * @level.width) + x) }
      ordinary.empty? ? cells : ordinary
    end

    def steps_from((x, y, keys))
      STEPS.filter_map do |dx, dy|
        to_x = x + dx
        to_y = y + dy
        [to_x, to_y, keys_from(keys, to_x, to_y).freeze] if can_enter?(to_x, to_y, keys)
      end
    end

    def can_enter?(x, y, keys)
      return false unless standable?(x, y)

      lock = @level.lock_at(x, y)
      lock.nil? || keys.include?(lock)
    end

    # A door is a cell you can stand in. Nothing else that is solid is.
    def standable?(x, y) = !@level.solid?(x, y) && !@scenery.blocks?(x, y)

    def keys_from(keys, x, y)
      key = @level.key_at(x, y)
      keys = keys.union(boss_keys) if keys.empty?
      key ? keys.union([key]).sort : keys
    end

    # A boss is counted from the start, because he cannot be got past any other way.
    def boss_keys = @boss_keys ||= @guards.guards.any? { |guard| Enemy[guard.kind].boss? } ? [BOSS_KEY] : []
  end
end
