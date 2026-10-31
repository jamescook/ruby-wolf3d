# frozen_string_literal: true

module Wolf3D
  # THE PLAYER: where they stand, which way they look, what they have, and what they have found on
  # this floor. Every part of the game that touches the player is handed this one record, and reads
  # the parts it wants by name.
  #
  # IT IS ALL DECLARED AT ONCE, so nothing has to come into being in the right order for anything
  # else to reach it. Each field is a framework variable the game changes as it runs; the record
  # itself never changes, so it is frozen and can be handed about freely.
  #
  #   x, y                 where they stand, in cells, with the fraction saying where in the cell
  #   angle                which way they look, as a step round the sine table
  #   cos, sin             that angle's cosine and sine, worked out once a move
  #   health, ammo, score  what the bar shows and the game is played by
  #   keys                 which keys are carried, one bit each
  #   kills, secrets,      how much of this floor has been found
  #   treasures
  #   noise                how long a noise they made stands for
  #
  # +sin+ IS A NUMBER, THE SINE OF THIS ONE ANGLE, and never the table of sines. The table belongs
  # to the view rather than to the player, and anything that needs it to look up another angle is
  # handed it separately: see Dying.
  Player = Data.define(:x, :y, :angle, :cos, :sin, :health, :ammo, :score, :keys, :kills, :secrets,
                       :treasures, :noise) do
    # A PLAYER AT +x+, +y+ LOOKING ALONG +angle+, with +ammo+ rounds. +lasting+ is what a saved game
    # holds (see LastingState), and every field but the noise and the two worked out from the angle
    # is in it.
    #
    # +looks+ says whether anything will ever need +cos+ and +sin+: the shot and every standing
    # thing do, and a floor with nothing standing in it does not, so there they are nil and cost
    # nothing.
    def self.declare(build:, x:, y:, angle:, lasting: LastingState.new(build:),
                     ammo: FirstPerson::START_AMMO, looks: false)
      new(
        x: lasting.var(:px, x), y: lasting.var(:py, y), angle: lasting.var(:view, angle),
        cos: (build.var(:_vcos, 0.0) if looks), sin: (build.var(:_vsin, 0.0) if looks),
        health: lasting.var(:health, FirstPerson::START_HEALTH), ammo: lasting.var(:ammo, ammo),
        score: lasting.var(:score, 0),
        # Which keys are carried, one bit each. A key is a thing lying on the floor like a clip of
        # ammunition is, so picking one up belongs to Pickups; this is only what is carried, which
        # is the one number a locked door asks about.
        keys: lasting.var(:keys, 0),
        # HOW MUCH OF THE FLOOR HAS BEEN FOUND: how many of its guards are down, how many of its
        # secret walls have been shoved, how many of its treasures are in your pocket. Three
        # numbers the game keeps for the tally at the end of a floor, and they belong to the FLOOR
        # rather than to the game — every one goes back to nothing when a floor starts, which is
        # what makes them a percentage of something.
        #
        # The score is the opposite: it is kept across floors and comes back to nothing only when a
        # whole game starts again.
        #
        # How much there was to find is counted with the things lying on the floor — see
        # FirstPerson#declare_what_there_is_to_find.
        kills: lasting.var(:kills, 0), secrets: lasting.var(:secrets, 0),
        treasures: lasting.var(:treasures, 0),
        # A NOISE THE PLAYER MADE. A gun going off is one, and so is a man crying out when you hit
        # him — the original's own flag is commented "true when shooting or screaming". A guard who
        # hears one looks your way without having to see you first, which is what turns a corridor
        # round. See Weapons#fire_a_round and GuardMind#wound_a_guard for where it is made,
        # GuardMind#look for who hears it, and FirstPerson#fire for where it runs out.
        #
        # IT IS A COUNT AND NOT A FLAG, which is a difference this game has to make and the
        # original does not. There, every actor thinks on every tic, so a flag that stands for one
        # tic is heard by all of them. Here a guard thinks on every OTHER pass — half the floor on
        # one, half on the next, which is what makes a room of them affordable — so a noise that
        # stood for one pass would be heard by half the room and missed by the other half, chosen
        # by nothing anyone could see. It stands for FirstPerson::HEARD_FOR passes instead, which is
        # how long it takes every guard to have thought once.
        noise: build.var(:noise, 0)
      )
    end
  end
end
