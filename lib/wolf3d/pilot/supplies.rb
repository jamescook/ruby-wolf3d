# frozen_string_literal: true

module Wolf3D
  class Pilot
    # WHAT LIES ON THE FLOOR AND WHAT IT IS WORTH: which pieces it wants, how far it will walk for one,
    # and the nearest that is still there.
    class Supplies
      # A hurt player walks further for health.
      DETOUR_STEPS_WHEN_HURT = 40
      DETOUR_STEPS_FOR_A_LIFE = 60
      ANY_DISTANCE_STEPS = 1000
      WEAPON_NUMBERS = Ractor.make_shareable({ machine_gun: Weapons::MACHINE_GUN, chain_gun: Weapons::CHAIN_GUN })
      HURT_HEALTH = 50

      # A detour costs this many steps at most.
      DETOUR_STEPS = 14
      HEALTH_WORTH_FETCHING = 85
      SCAVENGE_AMMO_BELOW = 60
      LOW_AMMO_ROUNDS = 40

      def self.cell_of(piece) = [piece.x, piece.y]

      attr_reader :pieces

      def initialize(pieces, sight, walker)
        @pieces = pieces
        @sight = sight
        @walker = walker
      end

      # The nearest of +pieces+ that can be walked to and is still there.
      def nearest(pieces)
        steps = @walker.steps_from_here
        pieces.map { |piece| self.class.cell_of(piece) }
              .select { |cell| steps[cell] && !@sight.walked?(cell) }
              .min_by { |cell| steps[cell] }
      end

      # The nearest cell holding something of these kinds, whatever it is needed for.
      def nearest_of_kinds(kinds) = nearest(@pieces.select { |piece| kinds.include?(piece.bonus.first) })

      def better_gun_cells
        @pieces.select { |piece| piece.bonus.first == :weapon && better_gun?(piece) }.map { |piece| self.class.cell_of(piece) }
      end

      def stock?(piece)
        kind, = piece.bonus
        case kind
        when :weapon then @sight.weapon < Weapons::CHAIN_GUN
        when :ammunition then @sight.ammo < Pickups::MOST_AMMO
        when :health then @sight.health < Pickups::FULL_HEALTH
        when :extra_life then true
        else false
        end
      end

      # Keep to the detour under way, or pick the nearest that pays for the walk. Answers the cell.
      def choose_detour
        cell = @sight.cell
        @detour = nil if @detour == cell || (@detour && @sight.walked?(@detour) && !@sight.drops.include?(@detour))
        return @detour if @detour

        steps = @walker.steps_from_here
        wanted = detour_limits
        @detour = wanted.keys.select { |at| steps[at].to_i.between?(1, wanted[at] - 1) }
                        .min_by { |at| steps[at] }
      end

      private

      # How far it will walk to each cell worth a detour.
      def detour_limits
        wanted = @pieces.select { |piece| worth_detour?(piece) }
                        .to_h { |piece| [self.class.cell_of(piece), furthest_for(piece)] }
        wanted = wanted.reject { |cell, _| @sight.walked?(cell) }
        # Something a man dropped is on the floor however often this cell has been walked.
        wanted.merge!(@sight.drops.to_h { |cell| [cell, DETOUR_STEPS] }) if @sight.ammo < SCAVENGE_AMMO_BELOW
        wanted
      end

      # A better gun is worth any walk on this setting, and another life nearly so.
      def furthest_for(piece)
        kind, = piece.bonus
        case kind
        when :weapon then ANY_DISTANCE_STEPS
        when :extra_life then DETOUR_STEPS_FOR_A_LIFE
        when :health then @sight.health < HURT_HEALTH ? ANY_DISTANCE_STEPS : DETOUR_STEPS_WHEN_HURT
        when :ammunition then @sight.ammo < LOW_AMMO_ROUNDS ? DETOUR_STEPS_WHEN_HURT : DETOUR_STEPS
        else DETOUR_STEPS
        end
      end

      def worth_detour?(piece)
        kind, = piece.bonus
        case kind
        when :health then @sight.health < HEALTH_WORTH_FETCHING
        when :ammunition then @sight.ammo < Pickups::MOST_AMMO
        when :weapon then better_gun?(piece)
        when :extra_life then true
        else false
        end
      end

      def better_gun?(piece) = WEAPON_NUMBERS.fetch(piece.bonus.last) > @sight.best_weapon
    end
  end
end
