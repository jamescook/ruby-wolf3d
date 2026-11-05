# frozen_string_literal: true

module Wolf3D
  class Pilot
    # HOW IT PLAYS ON ONE SETTING. Each pass the floor's parts have read the game and settled who the
    # man to deal with is; a strategy says which of FloorPlay::TACTICS to use about him, and which
    # doors are worth holding. FloorPlay carries the tactic out. One strategy is made for each life
    # on a floor, from the class Strategy.for picks by difficulty.
    #
    # This class is what every setting shares. A setting's own plan is a subclass in strategy/.
    class Strategy
      # The class for a row of the difficulty screen.
      def self.for(difficulty) = difficulty == HARDEST_DIFFICULTY ? Guerrilla : Steady

      def initialize(level:, sight:, gunfight:, boss_fight:)
        @level = level
        @sight = sight
        @gunfight = gunfight
        @boss_fight = boss_fight
      end

      # One of FloorPlay::TACTICS for this pass. +target+ is Gunfight#target, and +holding_door+
      # says an Ambush is under way.
      def choose_tactic(target, holding_door:) = raise NotImplementedError

      # Is +door+, the next step of the way, worth stopping at to shoot whoever comes through?
      def hold_door?(door) = Ambush.worth_holding?(door, @sight, @level)

      private

      # Out of sight of a man it was fighting, it goes back for him; with no man about, it walks.
      def hunt_or_travel(target)
        return :hunt if target.nil? && @gunfight.last_seen
        return :travel unless target && @gunfight.reacted_to?(target)

        @sight.ammo.zero? ? :fight_in_open : :fight_from_cover
      end
    end
  end
end

require_relative "strategy/steady"
require_relative "strategy/guerrilla"
