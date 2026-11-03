# frozen_string_literal: true

module Wolf3D
  class Pilot
    class Strategy
      # THE PLAN FOR THE EASIER SETTINGS: fight whoever it sees from beside a corner, walk on when
      # nobody is about, and fight a boss the same way, out to shoot and back in when hurt.
      class Steady < Strategy
        def choose_tactic(target, holding_door:)
          return :boss_fight if @boss_fight.awake?
          return :hold_door if holding_door

          hunt_or_travel(target)
        end
      end
    end
  end
end
