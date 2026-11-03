# frozen_string_literal: true

module Wolf3D
  class Pilot
    class Strategy
      # THE PLAN FOR THE HARDEST SETTING, where there are more men than bullets and a guard's shot
      # takes up to a quarter of a life.
      #
      # ONCE IT HAS A GUN THAT CAN CLEAR A WAY it stops to shoot only at whoever blocks the way or
      # stands near, and runs past the rest: a moving player is harder to hit (T_Shoot). A boss
      # has more hit points than peeking from a corner leaves bullets for, so it is held at range
      # and circled (BossFight#kite).
      class Guerrilla < Strategy
        def choose_tactic(target, holding_door:)
          return :kite_boss if @boss_fight.awake?
          return :hold_door if holding_door
          return hunt_or_travel(target) unless running_past?
          return :clear_way if target && @gunfight.blocking_way?(target)
          return :run_past unless target && @gunfight.close_by?(target)

          hunt_or_travel(target)
        end

        private

        def running_past? = @sight.best_weapon >= Weapons::MACHINE_GUN
      end
    end
  end
end
