# frozen_string_literal: true

module Wolf3D
  # WHAT AN ENEMY DOES with each frame, which is a state machine and almost nothing else.
  #
  # The original's actor table is plain data — a picture, how long to stand in it, what to think
  # about while there, and which row comes next — and the whole of a guard's behaviour is that
  # table plus four things to think about. He looks for you while standing. He walks his beat
  # while patrolling, looking as he goes. He closes on you once he has seen you, and stops to
  # take a shot when he has a clear line. A dog, having no gun, hunts you down instead.
  #
  # ONE MIND FOR ALL FIVE KINDS, and that is not a simplification: a state number already says
  # which kind is in it (see Behaviour), so every number a kind decides — its picture, its speed,
  # how it attacks, how it falls, what it leaves — is a column of a table read by that one
  # number. Nothing here asks what it is looking at, and five kinds cost what one costs.
  #
  # WHAT LIVES HERE AND WHAT DOES NOT: this decides where a guard is and which state he is in.
  # Drawing him is the view's business, and it reads the same pool.
  class GuardMind
    # A guard walks from the middle of one cell to the middle of the next and never stops
    # between them, which is what makes "can he go that way" a question about a single cell.
    CELL = 1.0

    # What each of the thinking jobs is numbered, so one table can say which to do.
    NOTHING = Enemy::THINKING.fetch(nil)
    LOOK = Enemy::THINKING.fetch(:look)
    PATROL = Enemy::THINKING.fetch(:patrol)
    CHASE = Enemy::THINKING.fetch(:chase)
    HUNT = Enemy::THINKING.fetch(:hunt)
    THROW = Enemy::THINKING.fetch(:throw)
    FLAME = Enemy::THINKING.fetch(:flame)
    HAUNT = Enemy::THINKING.fetch(:haunt)

    # ...and the ways of attacking, the same way.
    WITH_A_GUN = Enemy::ATTACKS.fetch(:gun)
    WITH_TEETH = Enemy::ATTACKS.fetch(:teeth)
    MORPHS = Enemy::ATTACKS.fetch(:morph)
    FINISHED = Enemy::ATTACKS.fetch(:cam)
    CRIES_OUT = Enemy::ATTACKS.fetch(:scream)
    TREADS = Enemy::ATTACKS.fetch(:tread)
    SLURPS = Enemy::ATTACKS.fetch(:slurp)
    FIRST_THROWN = Enemy::ATTACKS.fetch(Enemy::THROWN.first)

    # HOW OFTEN ONE WHO THROWS DOES, out of 256 for each think it has a clear line, and distance has
    # nothing to do with it where it has everything to do with a guard's. The original's chance is
    # eight per unit of its time for the throwers and two for a fake Hitler (T_Schabb, T_Fake).
    THROW_CHANCE = 8 * Enemy::TICKS_PER_THINK / Enemy::SCALE
    FLAME_CHANCE = 2 * Enemy::TICKS_PER_THINK / Enemy::SCALE

    # INSIDE THIS MANY CELLS A THROWER BACKS OFF, and that is the whole of why these fights are not
    # like Hans's: come close and he runs (T_Schabb, `dist < 4`, SelectRunDir).
    TOO_CLOSE = 4

    # HALF OF A RANDOM BYTE, which is how the original tosses a coin, and how far round the eight
    # ways the opposite of any one of them is.
    COIN = 128
    BEHIND = 4
    # North, northwest, west. See #search_dirs.
    SEARCH_DIRS = Ractor.make_shareable([2, 3, 4])

    # One fall in this many, which is `!US_RndT()`. A test can ask for it every time.
    RARE_SCREAM_ODDS = 256

    # A GHOST'S TOUCH. Within a whole cell on each axis (MINACTORDIST) it takes two for every unit of
    # the original's time.
    TOUCHING = 1.0

    # A RUNNING PLAYER IS HARDER TO HIT, and this is how much: T_Shoot starts from 160 and not 256.
    RUNNING_DODGE = 96

    # Inside this on both axes a man does not roll to fire: T_Chase sets the chance past any byte.
    BESIDE_CELLS = 1.25

    # How near a man counts as near enough to look closer, and how many passes that answer lasts.
    NEARBY_CELLS = 3.0
    NEARBY_PASSES = 4
    TOUCH_WOUND = 2 * Enemy::TICKS_PER_THINK / Enemy::SCALE

    # WHETHER HE FIRES is a chance against distance, taken every frame he has a clear line —
    # which is why a guard sometimes just stands there aiming. The original's number is sixteen
    # times the time elapsed, divided by the distance in cells, out of 256. Worked out here for
    # every distance rather than divided as the game runs; at arm's length it is a certainty.
    CHANCES = 256

    # HOW NEAR THE MIDDLE OF THE VIEW a guard has to be for a shot to be about him: a tenth of
    # the screen either side, which is the original's. Turned into a slope so the test needs no
    # divide — a guard is in the sights when how far he is to the side of the line you are
    # looking down is less than this much of how far in front of you he is.
    AIM = (240 / 10) / FirstPerson::WALL_SCALE

    # Nothing is a target.
    NOBODY = -1

    def initialize(build:, guards:, pool:, level:, this_floor:, player:, door_open:, door_linger:, things:,
                   behaviour: nil, dying: nil, pickups: nil, sounds: nil,
                   rooms: nil, floors: nil, difficulty: nil, lasting: nil, death_cam: nil, flash:,
                   scoring:, floor: nil, rare_scream_odds: RARE_SCREAM_ODDS)
      @b = build
      @floor = floor      # which floor is being played, or nil where nothing asks
      @rare_scream_odds = rare_scream_odds
      @scoring = scoring # where the points for a kill go
      @flash = flash     # the screen going red when you are hit
      @lasting = lasting # what a saved game holds, which what is in the air is part of
      @cam = death_cam   # how an episode ends, or nil on a cartridge with no such boss
      # THE STATE TABLE OF EVERY KIND THIS CARTRIDGE HOLDS. A build that says nothing gets the
      # guard's alone, which is what every test of the guard himself wants.
      @behaviour = behaviour || Behaviour.for([:guard])
      @difficulty = difficulty # how tough the game is set, or nil where nothing can change it
      @dying = dying      # what to tell when a shot takes the last of the health, or nil
      @pickups = pickups  # what to tell when a guard falls, so he can leave a clip behind
      @sounds = sounds    # the recorded sounds, or nil on a build with none
      @guards = guards
      @pool = pool
      @level = level
      @floors = floors    # every floor the cartridge holds, or nil for a game with one
      @rooms = rooms      # which rooms are open to the player's, or nil where nothing shuts off
      @this_floor = this_floor
      @things = things    # the row of pictures everything standing in the level is drawn from
      @player = player    # see Player
      @open = door_open   # how far each door has slid
      @linger = door_linger # how long each door has left standing open
      declare
    end

    # What the picture of a state is, and whether it turns — the view reads these to draw.
    attr_reader :picture_of, :turns_of

    # ...and which kinds this cartridge holds, for anything that has to ship their pictures.
    attr_reader :behaviour

    # ...and what they have thrown, or nil on a cartridge where nobody throws anything.
    attr_reader :thrown

    # One frame of thinking, for every guard on the floor.
    #
    # KEPT IN A ROUTINE OF ITS OWN, so it is placed on its own merits. The framework gives the
    # quick memory to whatever a frame spends its time in, and the view's own loop — eighty
    # rays and eighty stretched columns — is the thing that wants it. All of this is a great
    # deal of code and hardly any of a frame's work: ten guards think a few dozen statements
    # each, where the view draws thousands of pixels. Leaving it in the loop's own body pushed
    # the loop out of the quick memory and made the WHOLE frame two and a half times dearer,
    # which is the price of running from the cartridge instead.
    def update
      @b.call :guard_thinking
    end

    private

    def declare
      b = @b
      states = @behaviour.states
      rows = (0...states.length)
      # A STATE NUMBER IS ITS OWN WIDTH, because every kind together runs past a byte.
      wide = @behaviour.width

      # THE STATE TABLE, as tables the game reads by state number. Kept apart rather than as one
      # row per state because each is read on its own.
      #
      # A picture takes a HALF rather than a byte: a cartridge with all five kinds on it ships
      # nearly three hundred pictures of them, and the scenery stands in the same row.
      @picture_of = b.table :guard_picture,
                            rows.map { |n| @things.position_of(@behaviour.picture_of(n)) }, width: :half
      @turns_of = b.table :guard_turns, states.map { |s| s.turns ? 1 : 0 }, width: :byte
      @ticks_of = b.table :guard_ticks, states.map(&:ticks), width: @behaviour.ticks_width
      @becomes_of = b.table :guard_becomes, rows.map { |n| @behaviour.becomes_from(n) }, width: wide
      @think_of = b.table :guard_think, states.map { |s| Enemy::THINKING.fetch(s.think) }, width: :byte
      @attacks_of = b.table :guard_attacks, states.map { |s| Enemy::ATTACKS.fetch(s.fires) },
                            width: :byte
      @roused_of = b.table :guard_roused, states.map { |s| Enemy.roused?(s) ? 1 : 0 }, width: :byte

      # WHAT THE THING IN THIS STATE DOES NEXT, which is where the five kinds really live. Each
      # of these used to be one number, because there was one kind and one answer; now the state
      # a thing is in says which kind it is, so the answer is a column read by the number the
      # mind is already holding. Nothing branches on a kind and nothing remembers one.
      @chase_of = b.table :guard_chase, rows.map { |n| @behaviour.chase_from(n) }, width: wide
      @attack_of = b.table :guard_attack, rows.map { |n| @behaviour.attack_from(n) }, width: wide
      @hurt_of = b.table :guard_hurt, rows.map { |n| @behaviour.flinch_from(n) }, width: wide
      @hurt2_of = b.table :guard_hurt2,
                          rows.map { |n| @behaviour.flinch_from(n, second: true) }, width: wide
      # ...and whether it flinches at all, because one that does not is left exactly where it
      # was rather than being written back over itself. See Behaviour#flinches_from.
      @flinches_of = b.table :guard_flinches, rows.map { |n| @behaviour.flinches_from(n) },
                             width: :byte
      @fall_of = b.table :guard_fall, rows.map { |n| @behaviour.fall_from(n) }, width: wide
      # ...and how far it walks each think, which is how an officer runs you down and a dog is
      # quicker than either. Written as a fraction, so it ships as a word.
      @step_of = b.table :guard_step, rows.map { |n| @behaviour.step_from(n) }
      @opens_doors_of = b.table :guard_opens_doors, rows.map { |n| @behaviour.kind_at(n).opens_doors? ? 1 : 0 },
                                width: :byte
      # ...and what killing it is worth, and what it leaves lying where it fell.
      @points_of = b.table :guard_points, rows.map { |n| @behaviour.points_from(n) }, width: :half
      @leaves_of = b.table :guard_leaves, rows.map { |n| @behaviour.leaves_from(n) }, width: :byte
      @ends_episode = b.table(:guard_ends_episode, rows.map { |n| @behaviour.ends_the_episode_from(n) }, width: :byte) if @cam
      # HOW LONG IT TAKES TO REACT, the fixed part and what a random byte is divided by.
      @reacts_at = b.table :guard_reacts_at, rows.map { |n| @behaviour.reaction_from(n).first }, width: :byte
      @reacts_over = b.table :guard_reacts_over, rows.map { |n| @behaviour.reaction_from(n).last }, width: :byte
      @better_shot = b.table :guard_better_shot, rows.map { |n| @behaviour.kind_at(n).better_shot? ? 1 : 0 }, width: :byte
      # WHAT EACH KIND SOUNDS LIKE, as places in the list of what this cartridge's kinds say.
      if @sounds
        names = rows.map { |n| @behaviour.kind_at(n).name }
        @sees_you_says = b.table :guard_sees_you_says, names.map { |name| @sounds.voice(Sounds::SIGHTING[name]) }, width: :byte
        @fires_says = b.table :guard_fires_says, names.map { |name| @sounds.voice(Sounds::FIRING[name]) }, width: :byte
        @dies_says = b.table :guard_dies_says, names.map { |name| @sounds.voice(Sounds::DYING[name]) }, width: :byte
        declare_rare_scream(rows)
      end

      # WHICH WAY EACH DIRECTION GOES, one cell at a time. Nine entries: eight ways round and
      # then nowhere, which is where a guard hemmed in on every side ends up.
      steps = Guards::WAYS + [[0, 0]]
      @step_x = b.table :guard_step_x, steps.map(&:first)
      @step_y = b.table :guard_step_y, steps.map(&:last)

      # A TURNING POINT UNDER A PATROLLING GUARD sends him a new way. Nowhere means carry on.
      # Every floor's, end to end like the map, and read with this floor's own slice added.
      @arrow = b.table :guard_arrow, every_floors_arrows, width: :byte

      reach = [@level.width, @level.height].max
      @shot = b.table :guard_shot, (0..reach).map { |away| shot_chance(away) }

      # HOW NEAR A DOG JUMPS FROM: about a cell, plus the ground it covers in the think it is
      # deciding on — which is the original's own test, made against the step it is about to take
      # rather than against where it already stands.
      @jump_from = Guards::JUMP_FROM + Enemy[:dog].speed(chasing: true)
      @width = @level.width
      @reach = reach

      declare_the_scratch
      # The two pieces asked for from many places, each emitted once. See where each is defined
      # for what that is worth and why it can be done at all.
      declare_the_line_walk
      declare_the_walkable_test
      declare_what_is_thrown
      declare_the_jobs

      # WHOSE TURN IT IS. Flipped each time this routine runs, and a guard thinks on the turns
      # that match his — so half of them think each time and a guard is thought about every
      # other one. See Enemy::TICKS_PER_THINK for why that is often enough.
      #
      # FLIPPED HERE rather than on its own beat, so that whatever paces the world paces this
      # too. A turn flipped once a FRAME while the world moved once a PASS would flip twice
      # between two moves on a game taking two frames a pass — back to where it started, so the
      # same half would think every time and the other half never.
      @turn = b.var :_gturn, 0
      b.func(:guard_thinking) do
        @turn = (@turn + 1) % 2
        # HALF OF THEM ON ANY ONE FRAME, which is what @turn is for.
        @pool.each { |guard| think(guard) if guard.turn == @turn }
      end
    end

    # WHICH FLOORS AND WHICH KINDS CAN MAKE IT. A cartridge holding no tenth floor pays nothing.
    def declare_rare_scream(rows)
      tenth = @floors&.map { |floor| floor.index % Floors::PER_EPISODE == Playthrough::SECRET_FLOOR ? 1 : 0 } || []
      return unless tenth.include?(1) && @floor

      @rare_scream_floor = @b.table :guard_rare_scream_floor, tenth, width: :byte
      @rare_scream_kind = @b.table :guard_rare_scream_kind,
                                   rows.map { |n| @behaviour.kind_at(n).boss? ? 0 : 1 }, width: :byte
    end

    # THE TURNING POINTS OF EVERY FLOOR, in the order the cartridge plays them, so that this table
    # lines up cell for cell with the map. A cartridge with one floor is that floor's own.
    def every_floors_arrows
      floors = @floors&.to_a || [nil]
      floors.flat_map do |floor|
        level = floor&.level || @level
        guards = floor&.guards || @guards
        level.each_cell.map { |x, y| guards&.arrow_at(x, y) || Guards::NOWHERE }
      end
    end

    # At nothing at all he cannot miss the chance; beyond that it falls away with distance.
    def shot_chance(away)
      return CHANCES if away.zero?

      [(16 * Enemy::TICKS_PER_THINK / Enemy::SCALE) / away, CHANCES].min
    end

    def declare_the_scratch
      b = @b
      @job, @slot, @clear, @done, @ahead, @picked, @tx, @ty, @odds, @wound, @spot, @blow, @left =
        %i[gjob gslot gclear gdone gahead gpicked gtx gty godds gwound gspot gblow gleft]
        .map { |name| b.var(:"_#{name}", 0) }
      @dx, @dy, @absx, @absy, @far, @pace, @fwd, @sideways =
        %i[gdx gdy gabsx gabsy gfar gpace gfwd gsideways].map { |name| b.var(:"_#{name}", 0.0) }
      @man_in_step = b.var :_gman_in_step, 0
      @man_nearby = b.var :_gman_nearby, 0
      @nearby_wait = b.var :_gnearby_wait, 0
      @step_to_x = b.var :_gstep_to_x, 0.0
      @step_to_y = b.var :_gstep_to_y, 0.0

      # EACH OF THESE IS GIVEN ANOTHER VARIABLE'S NUMBER, so each has a `var` line of its own. Only
      # a name made on such a line takes the number. Made in a list like the ones above, `@a = @b`
      # would move the name to @b, and nothing would say so.
      @state = b.var :_gstate, 0
      @dir = b.var :_gdir, 0
      @try = b.var :_gtry, 0
      @cellx = b.var :_gcellx, 0
      @celly = b.var :_gcelly, 0
      @way = b.var :_gway, 0
      @other = b.var :_gother, 0
      @held = b.var :_gheld, 0
      @slant = b.var :_gslant, 0
      @back = b.var :_gback, 0
      @dodging = b.var :_gdodging, 0
      @homex = b.var :_ghomex, 0
      @homey = b.var :_ghomey, 0
      @away = b.var :_gaway, 0
      @target = b.var :_gtarget, 0
      @stepx = b.var :_gstepx, 0.0
      @stepy = b.var :_gstepy, 0.0
      @atx = b.var :_gatx, 0.0
      @aty = b.var :_gaty, 0.0
      @nearest = b.var :_gnearest, 0.0
      @fromx = b.var :_gfromx, 0.0
      @fromy = b.var :_gfromy, 0.0
      @man_x = b.var :_gman_x, 0.0
      @man_y = b.var :_gman_y, 0.0
      @shut_door = b.var :_gshut_door, 0
    end

    # ONE GUARD, ONE FRAME. Count his state down, move him on when it runs out, then let him
    # think — which is the order the original does it in, and it matters: a state that has just
    # begun thinks on the frame it begins.
    def think(guard)
      return thinks_it_through(guard) if @rooms.nil?

      # ...UNLESS HE HAS NO REASON TO, which is the original's own first line here (wl_play.cpp,
      # DoActor): a guard thinks if he has ever been seen, or if the room he is in is open to the
      # room the player is in. Everyone else stands exactly as he was.
      #
      # Nearly all of a think is the line of sight he walks to you, and it is walked whether he is
      # next door or on the far side of the floor. The second floor of the first episode has
      # twenty-nine guards and, wherever you stand on it, about one and a half of them are in the
      # room with you.
      #
      # `|` AND NOT `||`, because this runs for half the guards every pass. The right side reads a
      # list, so `||` would keep its answer in a variable of its own to skip it. `|` is one test.
      thinks_it_through(guard) if (guard.awake == 1) | @rooms.open_to_the_player?(guard.x, guard.y)
    end

    def thinks_it_through(guard)
      @state = guard.state
      step_the_state(guard)

      # EXACTLY ONE OF THESE RUNS. They are the arms of one choice — a guard is standing, or
      # walking his beat, or coming after you, or (a dog) hunting you down.
      #
      # A CARTRIDGE WITH NO DOGS HAS NO HUNTING ARM, so it pays nothing for one.
      @job = @think_of[guard.state]
      @b.call :guard_looks if @job == LOOK
      @b.call :guard_patrols if @job == PATROL
      @b.call :guard_chases if @job == CHASE if hunts?(:chase)
      @b.call :guard_hunts if @job == HUNT if hunts?(:hunt)
      @b.call :guard_throws if @job == THROW if hunts?(:throw)
      @b.call :guard_breathes_fire if @job == FLAME if hunts?(:flame)
      @b.call :guard_haunts if @job == HAUNT if hunts?(:haunt)
    end

    # EACH JOB A ROUTINE OF THE POOL'S OWN, run on whichever guard the walk is on. Written into
    # the walk, the four came to one routine of nearly all the console's quick memory, which it
    # could never be given, so all of it ran from the cartridge. Apart, each is placed on its own
    # merits, and the one a fight spends its time in can go where it runs faster.
    def declare_the_jobs
      @pool.func(:guard_try_dir) { |guard| walk_if_clear(guard) }
      @pool.func(:guard_select_dodge_dir) { |guard| select_dodge_dir(guard) }
      @pool.func(:guard_select_chase_dir) { |guard| select_chase_dir(guard) }
      @pool.func(:guard_looks) { |guard| look(guard) }
      @pool.func(:guard_patrols) { |guard| patrol(guard) }
      @pool.func(:guard_chases) { |guard| chase(guard) } if hunts?(:chase)
      @pool.func(:guard_hunts) { |guard| hunt(guard) } if hunts?(:hunt)
      if hunts?(:throw)
        @pool.func(:guard_select_chase_or_run_dir) { |guard| select_chase_or_run_dir(guard) }
        @pool.func(:guard_throws) { |guard| throw_or_back_off(guard) }
      end
      @pool.func(:guard_breathes_fire) { |guard| breathe_fire_or_walk(guard) } if hunts?(:flame)
      @pool.func(:guard_haunts) { |guard| haunt(guard) } if hunts?(:haunt)
    end

    # WHAT IS IN THE AIR IS DECLARED HERE, between the tests it borrows and the jobs that throw it. A
    # cartridge where nobody throws anything has none of it.
    def declare_what_is_thrown
      declare_the_box_test if @behaviour.throws? || @cam
      return unless @behaviour.throws?

      @thrown = Thrown.new(build: @b, mind: self, player: @player, things: @things, lasting: @lasting)
    end

    def declare_the_box_test
      @blocked = @b.var :_gblocked, 0
      @boxx = @b.var :_gboxx, 0.0
      @boxy = @b.var :_gboxy, 0.0
      @boxsize = @b.var :_gboxsize, 0.0
      @b.func(:is_a_box_in_something_solid) do
        @blocked = 0
        [[-1.0, -1.0], [1.0, -1.0], [-1.0, 1.0], [1.0, 1.0]].each do |(across, down)|
          @cellx = (@boxx + (@boxsize * across)).to_i
          @celly = (@boxy + (@boxsize * down)).to_i
          # Only what is built: ProjectileTryMove walks past men, the one who threw it included.
          @b.call :check_cell_open
          @blocked = 1 if @clear == 0
        end
      end
    end

    # Does anything on this cartridge think this way at all?
    def hunts?(job) = @behaviour.any?(job)

    # A state with no length never runs down — that is how standing goes on forever. One step a
    # think is enough for every other: the shortest state in the table is nine of these units
    # long and a think is worth six, so a think can never step clean over one.
    def step_the_state(guard)
      if @ticks_of[@state] > 0
        guard.ticks -= Enemy::TICKS_PER_THINK
        if guard.ticks <= 0
          # The shot leaves as he LEAVES the state he aimed in, which is where the original
          # hangs it: aiming, firing and lowering the arm are three pictures and the bullet
          # belongs to the join between the second and the third.
          attack_the_player(guard)
          guard.state = @becomes_of[@state]
          guard.ticks += @ticks_of[guard.state]
        end
      end
    end

    # A GUN OR A SET OF TEETH, OR SOMETHING THROWN, and which is a column of the state table like
    # everything else. A cartridge with no dogs on it asks nothing about teeth, and one with nobody
    # to throw anything asks nothing about that.
    def attack_the_player(guard)
      @blow = @attacks_of[@state]
      fire_at_the_player(guard) if @blow == WITH_A_GUN
      bite_the_player(guard) if @blow == WITH_TEETH if @behaviour.any?(:teeth)
      @thrown.throw_from(guard, @blow - FIRST_THROWN) if @blow >= FIRST_THROWN if @thrown
      let_the_man_out(guard) if @blow == MORPHS if @behaviour.man_inside?
      @cam.he_is_down(guard) if @blow == FINISHED if @cam
      cry_out if @blow == CRIES_OUT if @sounds
      tread(guard) if @blow == TREADS if @behaviour.any?(:tread) && @sounds
      @sounds.slurp if @blow == SLURPS if @behaviour.any?(:slurp) && @sounds
    end

    # HE CRIES OUT, in his own voice, or one of eight if he is a guard (A_DeathScream).
    def cry_out
      return @sounds.dies(@dies_says[@state]) if @rare_scream_floor.nil?

      @try = 0
      roll_rare_scream
      @sounds.dies(@dies_says[@state]) if @try == 0
    end

    # THE ONE THE ORIGINAL KEEPS BACK: on the tenth floor of an episode, one fall in 256 by anything
    # but a boss makes the sound nobody expects. The floor is asked first, as `mapon==9` is there.
    def roll_rare_scream
      if @rare_scream_floor[@floor] == 1 && @rare_scream_kind[@state] == 1
        if @b.rand(0...@rare_scream_odds) == 0
          @try = 1
          @sounds.rare_scream
        end
      end
    end

    # THE MACHINE'S TREAD, heard only from its own room or one open to it (A_MechaSound).
    def tread(guard)
      return @sounds.tread if @rooms.nil?

      @sounds.tread if @rooms.open_to_the_player?(guard.x, guard.y)
    end

    # THE MACHINE IS DOWN AND THE MAN GETS OUT, where it stands and going the way it was going
    # (A_HitlerMorph). He has been on the floor all along, so nothing is made: he is found by the
    # state he waits in. His own hit points were set when the floor started.
    def let_the_man_out(machine)
      @pool.each do |man|
        if man.state == @behaviour.inside
          man.x = machine.x
          man.y = machine.y
          man.dir = machine.dir
          man.togo = machine.togo
          man.door = machine.door
          man.state = @behaviour.out_of_the_machine
          man.ticks = @ticks_of[@behaviour.out_of_the_machine]
          man.awake = 1
        end
      end
    end

    public

    # IS ANY CORNER OF A BOX THIS SIZE IN SOMETHING SOLID? The same question a guard's feet ask, of the
    # four cells a box can touch, for what crosses cells in mid-flight and for setting the player
    # down. Neither of those has a map of its own.
    def blocked_around(x, y, size)
      @boxx = x
      @boxy = y
      @boxsize = size
      @b.call :is_a_box_in_something_solid
      @blocked == 1
    end

    # A THROWN THING HAS REACHED YOU. +shot+ stands where a guard stands in what follows, so a death
    # by rocket turns to face the rocket, as the original's does.
    def hit_the_player(shot, blow)
      @wound = blow
      take_it_out_of_the_player(shot)
    end

    # THE DEATH CAM HAS LINED UP, and the body in slot +boss+ gets up and falls again: from the first
    # picture of the fall, which a body's state still knows the way to.
    def fall_again(boss)
      hit = %i[state ticks].to_h { |field| [field, @pool.field_ref(field, boss)] }
      @blow = @fall_of[hit[:state]]
      hit[:state] = @blow
      hit[:ticks] = @ticks_of[@blow]
    end

    private

    # A DOG HAS NO GUN, so the only way it can hurt you is to reach you — and its jaws close at
    # the end of the second picture of the jump, whether or not anything is in the way. There is
    # no line of sight to walk and no distance to fall off with: it is near enough or it is not,
    # and what it takes is a byte of randomness shifted down four. Which is why a dog at your
    # feet is worse than a guard across the room, and why backing away from one works.
    def bite_the_player(guard)
      @sounds&.bites
      @dx = @player.x - guard.x
      @dy = @player.y - guard.y
      if @dx.abs <= Guards::BITE_REACH && @dy.abs <= Guards::BITE_REACH
        if @b.rand(0..CHANCES - 1) < Guards::BITE_CHANCE
          @wound = @b.rand(0..CHANCES - 1) / Guards::BITE_SHIFT
          take_it_out_of_the_player(guard)
        end
      end
    end

    # HIS SHOT IS NOT AIMED. It is a chance against distance, and the far half of that chance
    # depends on whether you can SEE him — a guard you are looking at misses more, because you
    # could be dodging. That is the game quietly being fair, and it is in the original's
    # numbers rather than anywhere else.
    #
    # What it does when it lands falls off with distance too, so a guard across the room does
    # almost nothing and one in your face does real harm.
    def fire_at_the_player(guard)
      # HEARD WHETHER OR NOT IT LANDS, and before either question is asked. A guard fires; the
      # chance and the line of sight decide what it does to you, not whether he pulled.
      @sounds&.say(@fires_says[@state])
      @dx = @player.x - guard.x
      @dy = @player.y - guard.y
      line_of_sight(guard)
      if @clear == 1
        measure_distance(guard)
        @away = @away * 2 / 3 if @better_shot[@state] == 1
        @odds = CHANCES - (@away * 8)
        @odds = CHANCES - (@away * 16) if guard.shown == 1
        @odds -= RUNNING_DODGE if @player.running == 1
        wound_the_player(guard) if @b.rand(0..CHANCES - 1) < @odds
      end
    end

    # WHAT A SHOT THAT LANDS TAKES OFF YOU, by distance: a byte of randomness shifted down twice
    # inside two cells, three times inside four, four times beyond.
    def wound_the_player(guard)
      @wound = @b.rand(0..CHANCES - 1) / 4
      @wound = @b.rand(0..CHANCES - 1) / 8 if @away >= 2
      @wound = @b.rand(0..CHANCES - 1) / 16 if @away >= 4
      take_it_out_of_the_player(guard)
    end

    # THE BLOW THAT TAKES THE LAST OF THE HEALTH IS THE ONE THE DEATH NEEDS TO KNOW ABOUT, and
    # this is the only place that knows who struck it. The view turns to face him, so who it was
    # has to be caught here rather than worked out afterwards from a body on the floor.
    #
    # A bullet and a set of teeth both come through here, which is where the original puts the
    # setting's own softening too — at the health rather than at the shot, so every wound goes
    # through it.
    #
    # AND NOTHING HURTS YOU ONCE THE DEATH CAM HAS STARTED, which the original tests before anything
    # else about a wound (TakeDamage, wl_agent.cpp): you are not there any more.
    def take_it_out_of_the_player(guard)
      gently
      @wound = 0 if @cam.stage > 0 if @cam
      @player.health -= @wound
      @flash.hurt(@wound) if @wound > 0
      if @player.health <= 0
        @player.health = 0
        @dying&.struck_by(guard)
      end
    end

    # THE EASIEST SETTING TAKES A QUARTER OF WHAT THE BLOW WOULD TAKE, and it is nearly the only
    # thing about an enemy that how tough you said you were changes. How well it shoots and how
    # far it sees are the same on all four; how much killing it takes is the same too, except for
    # a mutant, whose four differ.
    #
    # IT IS THE EASIEST SETTING ALONE. The second one hurts you exactly as much as the hardest
    # does, which is worth saying out loud because the two easiest agree about the other thing
    # the setting decides: neither of them brings in a single extra guard.
    def gently
      return if @difficulty.nil?

      @wound = @wound / Guards::GENTLE_PART if @difficulty == Guards::GENTLE
    end

    # --- looking for you -------------------------------------------------------------

    # Looking has two halves. He has to be able to SEE you, and then he has to REACT — a moment
    # of up to about a second before he turns and comes. That delay is why the game feels fair:
    # you get a beat between being seen and being come after.
    def look(guard)
      if guard.wait > 0
        guard.wait -= Enemy::TICKS_PER_THINK
        if guard.wait <= 0
          guard.wait = 0
          first_sighting(guard)
        end
      else
        heard_or_saw(guard)
        how_long_to_react(guard) if @clear == 1
      end
    end

    # THIS DELAY IS WHY THE GAME FEELS FAIR, and how long it is depends on who has seen you: a guard
    # takes up to about a second and an officer or a boss hardly any time at all (SightPlayer).
    def how_long_to_react(guard)
      @blow = @reacts_at[guard.state] * Enemy::SCALE
      @try = @reacts_over[guard.state]
      @blow += (@b.rand(0..CHANCES - 1) * Enemy::SCALE) / @try if @try > 0
      guard.wait = @blow
    end

    # A NOISE COUNTS AS A SIGHTING, which is the original's whole hearing model in one line:
    # `if (!madenoise && !CheckSight(ob)) return false`. It does not tell him where you are and
    # it does not make him chase — it gets him past the "can I see you" gate, and he still takes
    # his moment to react. Nothing about it can walk a guard at you through a wall.
    #
    # AND IT DOES NOT CARRY THROUGH ONE. A noise reaches a guard whose room is open to the room
    # you are standing in, and no further — the same rooms-joined-by-open-doors question the
    # whole think is gated on, asked again HERE because a guard who has been seen once thinks
    # wherever he stands. Without it, one shot would be heard through a wall for the rest of the
    # floor by everybody who had ever laid eyes on you. The original asks it twice for the same
    # reason (DoActor, then SightPlayer).
    #
    # A GUARD LYING IN WAIT HEARS NOTHING, which is what the ambush tile is for: he must SEE you.
    # That is the man behind the door who is meant to catch you walking past, and a gunshot two
    # rooms away giving him away would be the end of him. (The original drops the flag the moment
    # he does see you. Nothing here ever puts a guard back to standing, so it would never be
    # asked again.)
    # Written as nested tests rather than one joined condition, which is what this codebase does
    # wherever a side costs something: asking which room a guard is in is a table read and a list
    # read, and on the overwhelming majority of passes there is no noise to ask about.
    def heard_or_saw(guard)
      @clear = 0
      a_noise_reaches(guard) if @player.noise > 0 && guard.ambush == 0
      # ...and if it did not reach him, he is back to looking, which is what he was doing anyway.
      can_see(guard) if @clear == 0
    end

    # A floor whose rooms are never shut off from each other — one room, or no doors to join two
    # with — has nothing to ask, and everyone on it hears everything.
    def a_noise_reaches(guard)
      if @rooms.nil?
        @clear = 1
        return
      end

      @clear = 1 if @rooms.open_to_the_player?(guard.x, guard.y)
    end

    # He has seen you: he breaks into a chase, and from here he moves several times as fast —
    # three for a guard, four for an SS, five for an officer, which is a table read rather than a
    # number because the state he lands in is the one that says how fast his kind runs.
    def first_sighting(guard)
      @blow = @chase_of[guard.state]
      guard.state = @blow
      guard.ticks = @ticks_of[@blow]
      guard.togo = 0.0
      guard.door = 0            # FirstSighting drops any door he was waiting at
      guard.noticed = 1
      # "Halt!" — which is the one sound in this game that tells you something you could not
      # otherwise know: that you have been seen, and by how many.
      @sounds&.say(@sees_you_says[@blow])
    end

    # CAN HE SEE YOU? Three questions in order, cheapest first. Are you near enough that it does
    # not matter which way he faces. Are you in front of him at all. And is anything between you.
    def can_see(guard)
      @dx = @player.x - guard.x
      @dy = @player.y - guard.y
      near = Guards::AUTOMATIC_SIGHT

      if @dx > -near && @dx < near && @dy > -near && @dy < near
      @clear = 1
    else
        in_front(guard)
        line_of_sight(guard) if @clear == 1
      end
    end

    # IS THE PLAYER IN FRONT OF HIM, which the original answers with one comparison per facing
    # rather than an angle. A guard facing north cannot see anything south of him; each diagonal
    # takes the two halves together.
    def in_front(guard)
      @clear = 1
      @dir = guard.dir
      @clear = 0 if @dir == 2 && @dy > 0.0   # north
      @clear = 0 if @dir == 0 && @dx < 0.0   # east
      @clear = 0 if @dir == 6 && @dy < 0.0   # south
      @clear = 0 if @dir == 4 && @dx > 0.0   # west
      @clear = 0 if @dir == 3 && @dy > -@dx  # northwest
      @clear = 0 if @dir == 1 && @dy > @dx   # northeast
      @clear = 0 if @dir == 5 && @dx > @dy   # southwest
      @clear = 0 if @dir == 7 && -@dx > @dy  # southeast
    end

    # IS ANYTHING BETWEEN THEM: a step at a time from the guard toward the player, stopping at
    # the first thing that blocks. A shut door blocks; an open one does not.
    #
    # The ceiling is the width of the map, which no line can exceed, and the walk leaves as soon
    # as it arrives — so what it usually costs is how far apart they are, not how far apart they
    # could ever be — and almost every line meets a wall almost at once.
    def line_of_sight(guard) = walk_the_sight_line_from(guard.x, guard.y)

    # ONE COPY OF THE WALK, NOT FOUR, and that is what this indirection buys.
    #
    # It is asked from four places — a guard looking, a guard about to fire, and a bullet
    # picking its target — and a Ruby method call here is INLINED into the program, so four
    # asks used to mean four copies of the loop, the divide and the wall test. That is a great
    # deal of code for a routine whose whole job is to walk a handful of cells, and code is the
    # thing this game is short of: the console's quick memory holds 32K, the frame's own loop
    # wants nearly all of it, and what a guard emits decides whether both can fit.
    #
    # Every one of its inputs is working room already, so all a caller has to hand over is where
    # the line starts.
    def walk_the_sight_line_from(fromx, fromy)
      @fromx = fromx
      @fromy = fromy
      @b.call :walk_the_sight_line
    end

    def declare_the_line_walk
      @b.func(:walk_the_sight_line) { walk_the_sight_line }
    end

    # The line itself, walked from wherever it was told to start — a guard looking for you, or a
    # bullet on its way to him.
    def walk_the_sight_line
      b = @b
      aim_along_the_line(@fromx, @fromy)
      @tx = @player.x.to_i
      @ty = @player.y.to_i
      @clear = 1
      @done = 0

      b.repeat(@reach, stop_when: @done == 1) do
        @atx += @stepx
        @aty += @stepy
        @cellx = @atx.to_i
        @celly = @aty.to_i

        if @cellx == @tx && @celly == @ty
          @done = 1
        else
          @ahead = @this_floor.cell_at(@cellx, @celly)
          blocked_by(@ahead) if @ahead > 0
          @done = 1 if @clear == 0
        end
      end
    end

    # A step along the line from the guard toward the player, sized so the longer of the two
    # directions moves one whole cell each time — which is what makes the walk visit every cell
    # the line passes through without visiting any twice.
    # ONE DIVIDE AT MOST, NOT TWO, and the one that goes was never doing any work.
    #
    # The step is the direction scaled so the LONGER of the two moves one whole cell. Which
    # means the longer one's step is one whole cell — plus or minus — by construction, and
    # dividing it by its own size can only ever give back the one it already is. So it is set
    # from the sign instead, and only the shorter of the two is divided.
    #
    # That matters here because dividing a number holding a fraction by another is the dearest
    # arithmetic there is — about nine times an ordinary step, where every other divide is a
    # third to three — and these two were a fifth of everything a guard spends in a frame. The
    # walk that follows is unchanged, step for step.
    #
    # And when the two are both under a cell apart the scaling is held at one, so neither is
    # divided at all: the step IS the direction. That is the near case, which is the one a guard
    # about to shoot you is in.
    def aim_along_the_line(fromx, fromy)
      # HOW FAR EACH IS FROM NOUGHT, KEPT in a variable rather than asked for where it is read:
      # a bare `abs` is a new number and works it out afresh at every mention, and these two are
      # read five times between them.
      @absx = @dx.abs
      @absy = @dy.abs

      @stepx = @dx
      @stepy = @dy
      if @absx > @absy
        if @absx > 1.0
          @stepx = 1.0
          @stepx = -1.0 if @dx < 0.0
          @stepy = @dy / @absx
        end
      elsif @absy > 1.0
        @stepy = 1.0
        @stepy = -1.0 if @dy < 0.0
        @stepx = @dx / @absy
      end

      @atx = fromx
      @aty = fromy
    end

    # Something is in this cell. A wall stops the line; a doorway stops it only while its panel
    # is still across the way. A cell a secret wall could reach counts as clear, because the
    # wall is usually not in it and a guard blinded by a wall that is not there would be odd.
    def blocked_by(cell)
      @this_floor.sort_out(cell, door: lambda {
        @slot = @this_floor.door_in(cell)
        @clear = 0 if @open[@slot] < FirstPerson::DOOR_WALKABLE
      }, wall: -> { @clear = 0 })
    end

    # --- walking a beat --------------------------------------------------------------

    # A patrolling guard looks for you first — the whole point of a patrol is that it walks into
    # you — and then carries on to the next cell, unless looking has just set him chasing.
    def patrol(guard)
      look(guard)
      if @think_of[guard.state] == PATROL
        choose_a_patrol_way(guard) if guard.togo <= 0.0
        walk(guard, patrolling: true)
      end
    end

    # A turning point under his feet sends him a new way; without one he carries straight on.
    # Either way he only sets off if he can actually get there.
    def choose_a_patrol_way(guard)
      @way = @arrow[@this_floor.map_index(guard.x.to_i, guard.y.to_i)]
      guard.dir = @way if @way < Guards::NOWHERE
      @picked = 0
      try_dir(guard.dir)
      guard.dir = Guards::NOWHERE if @picked == 0
    end

    # --- coming after you ------------------------------------------------------------

    # A CHASE IS NOT PATHFINDING. Try the way toward the player on the longer axis, then the
    # other, then whatever way he was already going, then a short search. See select_chase_dir.
    #
    # And with a clear line at you he may stop to take a shot, and if he does not, he sidesteps
    # rather than closing straight down that line.
    def chase(guard)
      take_a_shot(guard)
      if @think_of[guard.state] == CHASE
        @dodging = @clear
        select_chase_or_dodge_dir(guard) if guard.togo <= 0.0
        walk(guard, patrolling: false)
      end
    end

    # A DOG CLOSES INSTEAD OF STOPPING FOR A SHOT, and that is the whole difference between
    # hunting and chasing. Where a guard asks whether he has a clear line, a dog asks whether it
    # is near enough to jump — and it asks about the step it is ABOUT to take, so it leaves the
    # ground a stride early. It never asks about the line, so it weaves wherever it is (T_DogChase).
    def hunt(guard)
      near_enough_to_jump(guard)
      if @think_of[guard.state] == HUNT
        @dodging = 1
        select_chase_or_dodge_dir(guard) if guard.togo <= 0.0
        walk(guard, patrolling: false)
      end
    end

    # ONE WHO THROWS COMES AT YOU UNTIL IT IS NEAR AND THEN BACKS OFF, and with a clear line it may
    # stop to throw, or sidestep. Distance has nothing to do with whether it does (T_Schabb, T_Gift,
    # T_Fat).
    def throw_or_back_off(guard)
      throw_if_it_will(guard, THROW_CHANCE)
      if @think_of[guard.state] == THROW
        @dodging = @clear
        @b.call :guard_select_chase_or_run_dir if guard.togo <= 0.0
        walk(guard, patrolling: false, backing_off: true)
      end
    end

    # A FAKE HITLER DOES NOT BACK OFF and does not throw often. Sidestepping is all he ever does,
    # with a clear line or without one (T_Fake).
    def breathe_fire_or_walk(guard)
      throw_if_it_will(guard, FLAME_CHANCE)
      if @think_of[guard.state] == FLAME
        @dodging = 1
        select_chase_or_dodge_dir(guard) if guard.togo <= 0.0
        walk(guard, patrolling: false)
      end
    end

    # A GHOST COMES ON BY THE PLAIN WAY AND NEVER SIDESTEPS (T_Ghosts). It has no attack: it hurts you
    # by trying to walk into you, which is in the same place the original puts it, the check every
    # moving thing makes not to stand on you (MoveObj). Everything else stops there. A ghost goes on
    # trying, and each try is a wound, a little one, for as long as you are within a cell of it.
    def haunt(guard)
      @dx = @player.x - guard.x
      @dy = @player.y - guard.y
      if @dx.abs < TOUCHING && @dy.abs < TOUCHING
        touch_the_player(guard)
      else
        @dodging = 0
        select_chase_or_dodge_dir(guard) if guard.togo <= 0.0
        walk(guard, patrolling: false)
      end
    end

    # ...and only across a room you are in, for a wall can have a ghost a cell from you on the far side.
    def touch_the_player(guard)
      return wound_by_touch(guard) if @rooms.nil?

      wound_by_touch(guard) if @rooms.open_to_the_player?(guard.x, guard.y)
    end

    def wound_by_touch(guard)
      @wound = TOUCH_WOUND
      take_it_out_of_the_player(guard)
    end

    # WITH NO ROOM IN THE AIR IT DOES NOT TRY, which is the original's `objfreelist`.
    def throw_if_it_will(guard, chance)
      @dx = @player.x - guard.x
      @dy = @player.y - guard.y
      line_of_sight(guard)
      if @clear == 1
        unless @thrown.full?
          start_attacking(guard) if @b.rand(0..CHANCES - 1) < chance
        end
      end
    end

    # Too close, and it goes the other way. Otherwise it comes on as a guard does.
    def select_chase_or_run_dir(guard)
      measure_distance(guard)
      if @away < TOO_CLOSE
        select_run_dir(guard)
      else
        select_chase_or_dodge_dir(guard)
      end
    end

    # AWAY FROM THE PLAYER on the longer axis first, then the other, then the same search a chase
    # ends in, except that any way will do here, the one he came from included (SelectRunDir).
    def select_run_dir(guard)
      @tx = @player.x.to_i - guard.x.to_i
      @ty = @player.y.to_i - guard.y.to_i
      @back = Guards::NOWHERE

      @way = 4                                  # west
      @way = 0 if @tx < 0                       # east
      @other = 2                                # north
      @other = 6 if @ty < 0                     # south
      @tx = 0 - @tx if @tx < 0
      @ty = 0 - @ty if @ty < 0
      swap_dirs if @ty > @tx

      @picked = 0
      try_dir_unless_back(@way)
      try_dir_unless_back(@other)
      search_dirs
      guard.dir = Guards::NOWHERE if @picked == 0
    end

    # Near enough on EACH axis on its own rather than as a distance, which is the original's own
    # test and is why a dog catches you round a corner it could not see you through.
    def near_enough_to_jump(guard)
      @dx = @player.x - guard.x
      @dy = @player.y - guard.y
      start_attacking(guard) if @dx.abs <= @jump_from && @dy.abs <= @jump_from
    end

    def take_a_shot(guard)
      @dx = @player.x - guard.x
      @dy = @player.y - guard.y
      line_of_sight(guard)
      if @clear == 1
        measure_distance(guard)
        start_attacking(guard) if beside_player? || @b.rand(0..CHANCES - 1) < @shot[@away]
      end
    end

    def beside_player? = @away == 1 && @dx.abs < BESIDE_CELLS && @dy.abs < BESIDE_CELLS

    # How far away in whole cells, taken on whichever of the two axes is the bigger — which is
    # the distance the original's guards judge a shot by.
    def measure_distance(guard)
      @cellx = @player.x.to_i - guard.x.to_i
      @cellx = 0 - @cellx if @cellx < 0
      @celly = @player.y.to_i - guard.y.to_i
      @celly = 0 - @celly if @celly < 0
      @away = @cellx
      @away = @celly if @celly > @away
      @away.clamp! 0, @reach
    end

    # He raises his gun, or the dog gathers itself — which of the two is a column of the state
    # table, so this is one piece of code and not two.
    def start_attacking(guard)
      @blow = @attack_of[guard.state]
      guard.state = @blow
      guard.ticks = @ticks_of[@blow]
      guard.togo = 0.0
    end

    # WHICHEVER OF THE TWO HE IS DOING, with a clear line in hand or without one.
    def select_chase_or_dodge_dir(guard)
      if @dodging == 1
        @b.call :guard_select_dodge_dir
      else
        @b.call :guard_select_chase_dir
      end
    end

    # A SIDESTEP, which is why a man with a clear line at you is hard to hit (SelectDodgeDir). He
    # has five ways to try and a coin decides the middle of the order. The one he likes best is the
    # slant between the two ways that bring him nearer, which is what walks him off your line.
    #
    # WHEN YOU ARE FURTHER AWAY ACROSS THAN DOWN the way across goes second, so that the step he
    # prefers is the one that takes him sideways to you. The coin then turns that round half the
    # time. The two that lead away from you come last, and last of all the way he came, which he
    # may only take sooner on the first choice after he notices you.
    #
    # Whole cells, as the original measures it, so standing in the same cell as him is not a side.
    def select_dodge_dir(guard)
      set_turnaround(guard)
      @tx = @player.x.to_i - guard.x.to_i
      @ty = @player.y.to_i - guard.y.to_i

      @way = 4                                  # west
      @way = 0 if @tx > 0                       # east
      @other = 2                                # north
      @other = 6 if @ty > 0                     # south
      @slant = (@way + @other) / 2              # the two added and halved, which suits three of the four
      @slant = 7 if @way == 0 && @other == 6    # and southeast is the one that wraps round

      @tx = 0 - @tx if @tx < 0
      @ty = 0 - @ty if @ty < 0
      swap_dirs if @tx > @ty
      swap_dirs if @b.rand(0..CHANCES - 1) < COIN

      @picked = 0
      try_dir_unless_back(@slant)
      try_dir_unless_back(@way)
      try_dir_unless_back(@other)
      try_dir_unless_back((@way + BEHIND) % Guards::NOWHERE)
      try_dir_unless_back((@other + BEHIND) % Guards::NOWHERE)
      try_dir(@back) if @picked == 0
      guard.dir = Guards::NOWHERE if @picked == 0
    end

    # WHICH WAY IS BACK. Nowhere on the first choice after he notices you, and for one who was
    # going nowhere, so that nothing is ruled out.
    def set_turnaround(guard)
      @back = Guards::NOWHERE
      if guard.noticed == 1
        guard.noticed = 0
      elsif guard.dir < Guards::NOWHERE
        @back = (guard.dir + BEHIND) % Guards::NOWHERE
      end
    end

    def swap_dirs
      @held = @way
      @way = @other
      @other = @held
    end

    def try_dir_unless_back(way)
      @try = way
      @b.call :guard_try_dir if @picked == 0 && @try != @back
    end

    # TOWARD THE PLAYER ON THE LONGER AXIS FIRST, then the other, then on as before, then a search
    # (SelectChaseDir). He will not turn straight round until nothing else is left, which is what
    # walks a blocked man along a wall rather than back and forth.
    #
    # Whole cells, as the original measures it, so an axis he is already level on is no way at all.
    def select_chase_dir(guard)
      @tx = @player.x.to_i - guard.x.to_i
      @ty = @player.y.to_i - guard.y.to_i
      @back = Guards::NOWHERE
      @back = (guard.dir + BEHIND) % Guards::NOWHERE if guard.dir < Guards::NOWHERE

      @way = Guards::NOWHERE
      @way = 0 if @tx > 0                       # east
      @way = 4 if @tx < 0                       # west
      @other = Guards::NOWHERE
      @other = 6 if @ty > 0                     # south
      @other = 2 if @ty < 0                     # north
      @tx = 0 - @tx if @tx < 0
      @ty = 0 - @ty if @ty < 0
      swap_dirs if @ty > @tx

      @picked = 0
      try_dir_unless_back(@way)
      try_dir_unless_back(@other)
      try_dir(guard.dir) if @picked == 0
      search_dirs
      try_dir(@back) if @picked == 0
      guard.dir = Guards::NOWHERE if @picked == 0
    end

    # THE ORIGINAL'S SEARCH IS THREE WAYS, NOT FOUR. Its loop counts from north to west, and in the
    # list of directions those two are two apart with northwest between them. So a blocked man
    # tries north, northwest and west, in an order a coin picks, and never east or south.
    def search_dirs
      if @picked == 0
        if @b.rand(0..CHANCES - 1) > COIN
          SEARCH_DIRS.each { |way| try_dir_unless_back(way) }
        else
          SEARCH_DIRS.reverse_each { |way| try_dir_unless_back(way) }
        end
      end
    end

    # Say which way, and find out whether he went.
    def try_dir(way)
      @try = way
      @b.call :guard_try_dir
    end

    # Can he walk one cell that way? If so he sets off, and from here he is between two cells
    # until he arrives. @try says which, and @picked says he did.
    #
    # A SLANT HAS TO CLEAR THE TWO CELLS BESIDE IT as well as the one it ends in, or he would walk
    # through the corner of a wall (TryWalk, CHECKDIAG). Every odd way round is a slant.
    def walk_if_clear(guard)
      if @try < Guards::NOWHERE
        @homex = guard.x.to_i
        @homey = guard.y.to_i
        @cellx = @homex + @step_x[@try]
        @celly = @homey + @step_y[@try]
        free_to_walk
        check_diagonal_sides if @clear == 1 && (@try % 2) == 1
        if @clear == 1
          guard.door = 0
          start_step(guard)
        elsif @shut_door > 0 && (@try % 2) == 0 && @opens_doors_of[guard.state] == 1
          guard.door = @shut_door
          start_step(guard)
        end
      end
    end

    def start_step(guard)
      guard.dir = @try
      guard.togo = CELL
      @picked = 1
    end

    def check_diagonal_sides
      @celly = @homey
      free_to_walk
      if @clear == 1
        @cellx = @homex
        @celly = @homey + @step_y[@try]
        free_to_walk
      end
    end

    # ONE COPY OF THIS TOO, and it is asked from more places than anything else here: a guard
    # picking a way to go tries as many as eight of them, and each try used to emit the whole
    # question again. It reads and writes nothing but working room, so it needs nothing passed
    # to it at all — the caller says which cell in @cellx and @celly, which it was doing anyway.
    def free_to_walk = @b.call(:can_a_guard_walk_there)

    def declare_the_walkable_test
      @b.func(:check_cell_open) { cell_open }
      @b.func(:can_a_guard_walk_there) do
        @b.call :check_cell_open
        @pool.each { |man| refuse_cell_of(man) } if @clear == 1
      end
      @b.func(:check_man_in_step) do
        @man_in_step = 0
        @pool.each { |man| refuse_step_at(man) }
      end
      @b.func(:look_for_men_nearby) do
        @man_nearby = 0
        @pool.each { |man| note_man_nearby(man) }
      end
    end

    public

    # A WALK OVER EVERY MAN FOR EVERY STEP IS DEAR, and on most steps nobody is near. So this looks
    # for anybody within NEARBY_CELLS every few passes, and steps look closer only when somebody is.
    # Nobody crosses the gap between that and a cell away in the passes between two looks.
    def update_men_nearby
      @nearby_wait -= 1
      if @nearby_wait <= 0
        @nearby_wait = NEARBY_PASSES
        @b.call :look_for_men_nearby
      end
    end

    # IS A MAN IN THE WAY OF A STEP THE PLAYER WANTS TO TAKE TO (x, y)?
    def man_in_step?(x, y)
      @man_in_step = 0
      if @man_nearby == 1
        @step_to_x = x
        @step_to_y = y
        @b.call :check_man_in_step
      end
      @man_in_step == 1
    end

    private

    def note_man_nearby(man)
      if man.hp > 0
        @dx = @player.x - man.x
        @dy = @player.y - man.y
        @man_nearby = 1 if @dx.abs < NEARBY_CELLS && @dy.abs < NEARBY_CELLS
      end
    end

    # TRYMOVE REFUSES A STEP THAT ENDS WITHIN A CELL OF A MAN ON BOTH AXES (MINACTORDIST). A body has
    # no hit points and the man inside the machine is not on the floor, so neither is in the way.
    #
    # The original asks only where the step ends, which leaves you stuck to a man who walked up to
    # you. A step that takes you further from him is allowed, so you can always leave.
    def refuse_step_at(man)
      return refuse_step_at_standing(man) unless @behaviour.man_inside?

      refuse_step_at_standing(man) if man.state != @behaviour.inside
    end

    def refuse_step_at_standing(man)
      if man.hp > 0
        @dx = @step_to_x - man.x
        @dy = @step_to_y - man.y
        if @dx.abs < TOUCHING && @dy.abs < TOUCHING
          @absx = @player.x - man.x
          @absy = @player.y - man.y
          @man_in_step = 1 if @dx.abs + @dy.abs < @absx.abs + @absy.abs
        end
      end
    end

    # A cell a guard can walk into: open floor, or a doorway whose panel has slid all the way out of
    # the way, and nothing standing in it that a body cannot pass. The same question the player's
    # feet ask, asked of a guard — and a guard is stopped by a barrel exactly as you are.
    #
    # A door in any other state says which it is in @shut_door. The original marks a door on the map
    # until it is fully open, so a man does not step in while it is sliding, though you can.
    def cell_open
      @spot = (@celly * @width) + @cellx
      @ahead = @this_floor.cell(@spot)
      @clear = 0
      @shut_door = 0
      @clear = 1 if @ahead == 0
      @this_floor.sort_out(@ahead, door: lambda {
        @slot = @this_floor.door_in(@ahead)
        if @open[@slot] >= FirstPerson::DOOR_WIDE
          @clear = 1
        else
          @shut_door = @slot + 1
        end
      })
      @this_floor.when_blocked(@spot) { @clear = 0 }
    end

    # A MAN WILL NOT WALK INTO ANOTHER (CHECKSIDE, CHECKDIAG). The cell a walking man holds is the one
    # he is heading for, because the original moves him to it on the map as he sets off. One waiting
    # at a door has not set off, so he holds his own. A body and a ghost have no hit points, which is
    # what the original's missing FL_SHOOTABLE comes out as, so both can be walked through, and the
    # man inside the machine is not on the floor at all.
    def refuse_cell_of(man)
      return refuse_cell_of_standing(man) unless @behaviour.man_inside?

      refuse_cell_of_standing(man) if man.state != @behaviour.inside
    end

    def refuse_cell_of_standing(man)
      if man.hp > 0
        @man_x = man.x
        @man_y = man.y
        if man.door == 0 && man.togo > 0.0 && man.dir < Guards::NOWHERE
          @man_x += man.togo * @step_x[man.dir].to_f
          @man_y += man.togo * @step_y[man.dir].to_f
        end
        @clear = 0 if @man_x.to_i == @cellx && @man_y.to_i == @celly
      end
    end

    public

    # --- being shot at ---------------------------------------------------------------

    # THE PLAYER FIRES. A pistol shot goes to the NEAREST guard who is in the sights and has
    # nothing between him and you — not to whatever the middle strip of the view happens to be
    # pointing at, which is a rule people expect and the original does not have.
    #
    # "In the sights" is a tenth of the screen either side of the middle, as a slope: how far
    # he is to the side of the line you are looking down, against how far in front of you he
    # is. Written that way it is a multiply and a comparison and never a divide.
    #
    # +with_knife+ is true while the knife is the thing in your hands, or nil on a game with one
    # weapon — and then none of the knife's own arm is emitted. What it changes is the DAMAGE
    # and the REACH, never the search: a knife goes for the same man down the same line, and the
    # only question it asks differently is whether he is near enough to touch.
    def shoot(with_knife: nil)
      @target = NOBODY
      @nearest = FAR_AWAY

      @pool.each { |guard| consider_as_a_target(guard) }

      hit_the_target(with_knife) if @target != NOBODY
    end

    private

    # The furthest anything can be, so the first candidate always beats it.
    FAR_AWAY = 1000.0

    # Is this one in the sights, in the open, and nearer than the best so far?
    #
    # THE FIRST QUESTION IS ONE THE DRAWING ALREADY ANSWERED, and it is the cheapest thing here
    # by a long way: one byte read and one comparison against work the renderer did anyway. A
    # guard behind a wall never reaches the two multiplies below, and no sight line is ever
    # walked to him — the strips he covers were measured against the walls last frame and he was
    # not put on the screen. The original opens both of its attacks the same way, on the same
    # flag (`check->flags & FL_VISABLE`, wl_agent.cpp), and for the same reason.
    #
    # It is a pass stale, which is what the original's is too. On the second floor of the first
    # episode it is the difference between measuring twenty-nine men and measuring the one or two
    # actually in front of you.
    #
    # ASKED BEFORE HIS HEALTH, and nested rather than joined with `&`, so that the guard it turns
    # away costs one list read instead of two: most of a floor is men who are alive and not on
    # the screen, and the bodies are the few.
    def consider_as_a_target(guard)
      measure_him(guard) if guard.shown == 1 && guard.hp > 0
    end

    # Where he is in front of the eye and to the side of it, and — if that puts him in the sights
    # and nearer than the best so far — whether the line to him is clear.
    def measure_him(guard)
      x = guard.x
      y = guard.y
      @dx = x - @player.x
      @dy = y - @player.y

      @fwd = @dx * @player.cos
      @fwd += @dy * @player.sin
      @sideways = @dy * @player.cos
      @sideways -= @dx * @player.sin

      if @fwd > 0.0 && @fwd < @nearest && @sideways.abs < (@fwd * AIM)
        # Only now is a line worth walking, and it is walked from him toward you — the same
        # line either way.
        @dx = @player.x - x
        @dy = @player.y - y
        walk_the_sight_line_from(x, y)
        if @clear == 1
          @nearest = @fwd
          @target = guard.index
        end
      end
    end

    # HOW BADLY THE MAN IN THE SIGHTS IS HURT. How far away he is decides it, in whole cells,
    # and the weapon does not — every gun in this game does the same damage, so a chain gun is
    # not a harder-hitting pistol, it is more pistol shots.
    def hit_the_target(with_knife)
      x = @pool.field_ref(:x, @target)
      y = @pool.field_ref(:y, @target)
      @cellx = (@player.x.to_i - x.to_i)
      @cellx = 0 - @cellx if @cellx < 0
      @celly = (@player.y.to_i - y.to_i)
      @celly = 0 - @celly if @celly < 0
      @away = @cellx
      @away = @celly if @celly > @away

      if with_knife
        what_a_knife_does
      else
        what_a_gun_does
      end
      wound_a_guard if @wound > 0
    end

    # ...AND WHAT A GUN DOES, by distance, where the third case can miss outright: past four
    # cells a roll has to beat the distance or the shot goes wide, which is why a pistol across
    # a room is a waste of a bullet and why backing away from a fight works.
    def what_a_gun_does
      @wound = @b.rand(0..CHANCES - 1) / 4
      @wound = @b.rand(0..CHANCES - 1) / 6 if @away >= 2
      if @away >= 4
        # Far enough away to miss altogether.
        @wound = 0 if @b.rand(0..CHANCES - 1) / 12 < @away
      end
    end

    # ...AND WHAT A KNIFE DOES, which is not a gun at zero range. It takes about a quarter of
    # what a close shot takes, and instead of falling off with distance it simply stops: inside
    # a cell and a half it cuts, outside it the swing meets nothing at all.
    #
    # The distance it asks about is the one the search already worked out — how far in FRONT of
    # the eye the man is, which is what the original measures a knife by too.
    def what_a_knife_does
      @wound = 0
      @wound = @b.rand(0..CHANCES - 1) / 16 if @nearest < Weapons::KNIFE_REACH
    end

    # A GUARD WHO HAS NOT NOTICED YOU TAKES DOUBLE, which is the original quietly rewarding you
    # for getting the first one in. Then he either falls over or flinches and comes for you —
    # and a guard who was not already coming starts now, however little the shot took off him.
    #
    # HIS FIELDS ARE KEPT IN A HASH because a name holds a value, so `hp -= @wound` on a local would
    # leave the guard as he was. A write to a slot of the Hash reaches the field.
    def wound_a_guard
      hit = %i[hp state ticks togo noticed].to_h { |field| [field, @pool.field_ref(field, @target)] }

      # A MAN WHO IS HIT CRIES OUT, and that is a noise like a gunshot — the original's own flag
      # is commented "true when shooting or screaming" and it is set here, where the damage is
      # done, rather than with the weapon. It is what makes a knife that LANDS bring the room
      # while one that misses does not.
      @player.noise = FirstPerson::HEARD_FOR
      @wound = @wound * 2 if @roused_of[hit[:state]] == 0
      hit[:hp] -= @wound

      if hit[:hp] <= 0
        # WHAT KILLING HIM IS WORTH AND WHAT HE WAS CARRYING, both read BEFORE he starts falling
        # over — a state number is what says which kind he is, and in a moment it will say he is
        # a body instead.
        @scoring.pay(@points_of[hit[:state]])
        @cam.remember_the_spot if @ends_episode[hit[:state]] == 1 if @cam
        @left = @leaves_of[hit[:state]]
        @blow = @fall_of[hit[:state]]
        hit[:state] = @blow
        hit[:ticks] = @ticks_of[@blow]
        # ...and one off the floor's tally, which is a different thing from the score: the score
        # is kept across floors and this is how much of THIS floor has been cleared.
        @player.kills += 1
        # ...and he leaves what he was carrying in the cell he fell in, which is the loop the
        # whole game runs on: shoot a guard, take what he was carrying, shoot the next one. Half
        # a clip from most of them, a machine gun from an SS, and nothing at all from a dog.
        @pickups&.a_guard_fell(@target, leaving: @left)
      else
        # BEING SHOT AT COUNTS AS BEING SEEN, whatever the thing does about the wound itself —
        # the original rouses one that had not noticed you BEFORE it asks which kind it is. So
        # this comes first and reaches everything, a boss included.
        if @roused_of[hit[:state]] == 0
          @blow = @chase_of[hit[:state]]
          hit[:state] = @blow
          hit[:ticks] = @ticks_of[@blow]
          hit[:togo] = 0.0
          hit[:noticed] = 1
          @sounds&.say(@sees_you_says[hit[:state]])
        end
        # ...and then the flinch, for a kind that has one. Odd or even decides which of the two
        # it wears, so the same wound twice running does not look like a repeat.
        #
        # A KIND WITH NO FLINCH IS LEFT ALONE ENTIRELY, which is what the original's damage code
        # does by having no arm for it — and it is what lets a boss finish a chaingun burst with
        # rounds landing on him. Writing the same state back would restart its count and rob him
        # of the rest of the picture he was in, so the whole block is skipped rather than made
        # to write over itself. See Behaviour#flinch_from.
        if @flinches_of[hit[:state]] == 1
          @blow = @hurt_of[hit[:state]]
          @blow = @hurt2_of[hit[:state]] if (hit[:hp] % 2) == 0
          hit[:state] = @blow
          hit[:ticks] = @ticks_of[@blow]
        end
      end
    end

    # Move him the way he is going. When he reaches the middle of the next cell, pick another.
    #
    # HOW FAR HE GOES IS A COLUMN OF THE STATE TABLE, because it is the one thing about walking
    # that differs between the kinds and between the beat and the chase — and the state he is in
    # already says both. So an officer running you down and a dog trotting past cost the same
    # here as a guard did.
    #
    # A MAN AT A SHUT DOOR HOLDS IT OPEN AND WAITS, and walks on the moment it is all the way open
    # (T_Chase, T_Path, ob->distance below nought). OpenDoor asks nothing about keys, which is only
    # the player's own OperateDoor, so a man goes through a door you cannot.
    def walk(guard, patrolling:, backing_off: false)
      wait_at_door(guard) if guard.door > 0
      if guard.door == 0 && guard.dir < Guards::NOWHERE
        @pace = @step_of[guard.state]
        guard.x += @pace * @step_x[guard.dir].to_f
        guard.y += @pace * @step_y[guard.dir].to_f
        guard.togo -= @pace

        if guard.togo <= 0.0
          # Put him exactly in the middle of the cell he has reached, so the rounding of a long
          # patrol never adds up into a drift.
          guard.x = guard.x.to_i.to_f + 0.5
          guard.y = guard.y.to_i.to_f + 0.5
          guard.togo = 0.0
          if patrolling
            choose_a_patrol_way(guard)
          elsif backing_off
            @b.call :guard_select_chase_or_run_dir
          else
            select_chase_or_dodge_dir(guard)
          end
        end
      end
    end

    def wait_at_door(guard)
      @slot = guard.door - 1
      play_door_sound(guard) if @open[@slot] == 0.0
      @linger[@slot] = FirstPerson::DOOR_LINGER
      guard.door = 0 if @open[@slot] >= FirstPerson::DOOR_WIDE
    end

    # HEARD FROM EITHER SIDE. DoorOpening joins the door's two rooms and then asks whether you are in
    # one, so a man opening a door into your room is heard. The two cells are the one he stands in
    # and the one past the door.
    def play_door_sound(guard)
      return @sounds&.door_opens if @rooms.nil?

      @man_x = guard.x + (2.0 * @step_x[guard.dir].to_f)
      @man_y = guard.y + (2.0 * @step_y[guard.dir].to_f)
      if @rooms.open_to_the_player?(guard.x, guard.y)
        @sounds&.door_opens
      elsif @rooms.open_to_the_player?(@man_x, @man_y)
        @sounds&.door_opens
      end
    end
  end
end
