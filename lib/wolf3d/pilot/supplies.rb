# frozen_string_literal: true

module Wolf3D
  class Pilot
    # WHAT LIES ON THE FLOOR AND WHAT IT IS WORTH: which pieces it wants, how far it will walk for one,
    # and the nearest that is still there.
    class Supplies
      ALWAYS = Float::INFINITY
      NEVER = 0
      ANY_DISTANCE_STEPS = 1000
      SHORT_DETOUR_STEPS = 14
      LONG_DETOUR_STEPS = 40
      LIFE_DETOUR_STEPS = 60

      # WHAT ONE KIND OF PIECE IS WORTH, each number against a reading of the player's own. A piece
      # is a detour while +reading+ is under +detour_below+, and it is worth stocking up on while
      # +reading+ is under +stock_below+. Under +short_below+ it is short of the thing, and walks
      # +steps_when_short+ for one instead of +steps+.
      Bonus = Data.define(:reading, :detour_below, :stock_below, :short_below, :steps, :steps_when_short) do
        def worth_detour?(sight) = sight.public_send(reading) < detour_below
        def worth_stocking?(sight) = sight.public_send(reading) < stock_below
        def furthest_steps(sight) = sight.public_send(reading) < short_below ? steps_when_short : steps
      end

      def self.gun_bonus(gun)
        Bonus.new(reading: :best_weapon, detour_below: gun, stock_below: gun, short_below: NEVER,
                  steps: ANY_DISTANCE_STEPS, steps_when_short: ANY_DISTANCE_STEPS)
      end

      # A better gun is worth any walk, and another life nearly so. A hurt player walks further for
      # health. Everything else that lies about, treasure and scraps and keys, is walked over or not.
      BONUSES = Ractor.make_shareable(
        { health: Bonus.new(reading: :health, detour_below: 85, stock_below: Pickups::FULL_HEALTH, short_below: 70,
                            steps: LONG_DETOUR_STEPS, steps_when_short: ANY_DISTANCE_STEPS),
          ammunition: Bonus.new(reading: :ammo, detour_below: Pickups::MOST_AMMO, stock_below: Pickups::MOST_AMMO, short_below: 40,
                                steps: SHORT_DETOUR_STEPS, steps_when_short: LONG_DETOUR_STEPS),
          extra_life: Bonus.new(reading: :health, detour_below: ALWAYS, stock_below: ALWAYS, short_below: NEVER,
                                steps: LIFE_DETOUR_STEPS, steps_when_short: LIFE_DETOUR_STEPS),
          machine_gun: gun_bonus(Weapons::MACHINE_GUN),
          chain_gun: gun_bonus(Weapons::CHAIN_GUN) }
      )
      WORTH_NOTHING = Ractor.make_shareable(
        Bonus.new(reading: :health, detour_below: NEVER, stock_below: NEVER, short_below: NEVER,
                  steps: SHORT_DETOUR_STEPS, steps_when_short: SHORT_DETOUR_STEPS)
      )
      GUNS = %i[machine_gun chain_gun].freeze

      # Below this it picks up what the men dropped.
      SCAVENGE_AMMO_BELOW = 60

      # One thing to pick up. +number+ is its place in Scenery#pieces, which is how the game says
      # whether it has been taken.
      Piece = Data.define(:cell, :kind, :bonus, :number)

      def self.piece_from(scenery_piece, number)
        kind, what = scenery_piece.bonus
        kind = what if kind == :weapon
        Piece.new(cell: [scenery_piece.x, scenery_piece.y], kind: kind, bonus: BONUSES.fetch(kind, WORTH_NOTHING), number: number)
      end

      attr_reader :pieces

      def initialize(scenery, sight, walker)
        @pieces = scenery.pieces.each_with_index.filter_map { |piece, number| self.class.piece_from(piece, number) if piece.bonus }
        @sight = sight
        @walker = walker
      end

      # The nearest of +pieces+ that can be walked to and is still there.
      def nearest(pieces)
        steps = @walker.steps_from_here
        pieces.select { |piece| steps[piece.cell] && !@sight.thing_gone?(piece.number) }.map(&:cell).min_by { |cell| steps[cell] }
      end

      # The nearest cell holding something of these kinds, whatever it is needed for.
      def nearest_of_kinds(kinds) = nearest(@pieces.select { |piece| kinds.include?(piece.kind) })

      def better_gun_cells
        @pieces.select { |piece| GUNS.include?(piece.kind) && piece.bonus.worth_detour?(@sight) }.map(&:cell)
      end

      def stock?(piece) = piece.bonus.worth_stocking?(@sight)

      # Keep to the detour under way, or pick the nearest that pays for the walk. Answers the cell.
      def choose_detour
        @detour = nil if @detour == @sight.cell || (@detour && !lying_at?(@detour))
        return @detour if @detour

        steps = @walker.steps_from_here
        wanted = detour_limits
        @detour = wanted.keys.select { |cell| steps[cell].to_i.between?(1, wanted[cell] - 1) }
                        .min_by { |cell| steps[cell] }
      end

      private

      # How far it will walk to each cell worth a detour.
      def detour_limits
        wanted = @pieces.select { |piece| !@sight.thing_gone?(piece.number) && piece.bonus.worth_detour?(@sight) }
                        .to_h { |piece| [piece.cell, piece.bonus.furthest_steps(@sight)] }
        wanted.merge!(@sight.drops.to_h { |cell| [cell, SHORT_DETOUR_STEPS] }) if @sight.ammo < SCAVENGE_AMMO_BELOW
        wanted
      end

      def lying_at?(cell)
        @sight.drops.include?(cell) || @pieces.any? { |piece| piece.cell == cell && !@sight.thing_gone?(piece.number) }
      end
    end
  end
end
