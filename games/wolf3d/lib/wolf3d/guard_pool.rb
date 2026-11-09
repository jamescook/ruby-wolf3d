# frozen_string_literal: true

module Wolf3D
  # EVERY GUARD ON THE FLOOR BEING PLAYED: where each stands, which way he faces, what state he is
  # in and how much killing he still takes. One slot per man, alive or lying where he fell.
  #
  # THE POOL HOLDS ONE FLOOR'S WORTH, not every floor's, because only one floor is ever being
  # played — so it is sized for the busiest and refilled from the tables when a floor starts. It
  # is sized for the hardest game too, or the hardest setting could not be played at all.
  #
  # This only keeps them. What a guard does about you is GuardMind, how he gets on the screen is
  # Billboards, and the clip he drops is Pickups; all three are handed #pool and read and write
  # its fields. What lives here is the shape of a slot, how wide each field is, where every guard
  # of every floor started, and putting a floor's guards back when it starts.
  class GuardPool
    # HOW BIG EACH OF A GUARD'S FIELDS REALLY NEEDS TO BE. A pool is one list per field and a
    # slot is a whole 32-bit number unless it is told otherwise, so left alone a guard takes four
    # bytes to keep a direction, a flag, or how many hit points are left. Eleven of the
    # fourteen hold far less than that, and on a cartridge carrying every floor the pool is
    # sized for the busiest one — so what those eleven cost is memory the placement chooser would
    # otherwise be giving to the code the frame runs in.
    #
    # EVERY RANGE HERE IS READ OFF THE GAME rather than guessed, and the three countdowns are
    # why that matters. `ticks` and `wait` and `hp` are all written by taking something off and
    # THEN testing against nothing, so each really does hold a negative number for the length
    # of its own test. A narrow slot goes below nothing for exactly that reason (see the
    # framework's `list`), which the first two fit inside a byte:
    #
    #   dir      0..7      which way he faces
    #   turn     0..1      which half of the guards think on this frame
    #   dropped  0..3      nothing, a clip, a machine gun, or the gold key
    #   shown, awake, ambush, noticed   yes or no
    #
    # `wait` is the one that never fits: a reaction is up to 192 units and it is counted
    # down the same way, so it wants -7..192 and a byte stops at 127. It takes a half instead,
    # which is still half a whole number. And x, y and togo carry fractions, which need the
    # whole word — a fraction is mostly its own fractional part.
    #
    # THREE OF THEM DEPEND ON WHAT THE CARTRIDGE HOLDS, so they are asked rather than written:
    #
    #   ticks  ninety of a boss's wind-up is a byte, and 420 of his last words is not.
    #   hp     an SS starts at 100 and a shot can take him past nothing, which is a byte. A
    #          BOSS starts at up to 1200, which is not.
    #   state  every kind's states end to end, and a state number IS the kind. Five kinds is
    #          117 of them and fits; all seven is 156 and does not.
    #
    # Both keep the byte on a cartridge that does not need more, which is the whole bargain
    # these widths are: a game with no boss on any floor pays a boss nothing.
    NARROW = { dir: :byte, turn: :byte, dropped: :byte, door: :byte,
               shown: :byte, awake: :byte, ambush: :byte, noticed: :byte, wait: :half }.freeze

    # How wide a slot has to be to hold every number that can go in it, given the range the
    # cartridge really needs. Signed, because these are counted down past nothing.
    def self.width_for(most)
      most <= 127 ? :byte : :half
    end

    # Does any floor on this cartridge have anybody on it? A cartridge with nobody anywhere
    # declares none of this and pays for none of it.
    def self.needed?(floors) = !floors.no_floor_has?(:guards)

    # +behaviour+ is every state of every kind this cartridge ships, which is what a guard's
    # starting state and toughness are read from. +difficulty+ is how tough the game is set,
    # which decides who stands up when a floor starts. +tables+ is where every floor's guards
    # come from (FloorTables).
    def initialize(build:, floors:, tables:, behaviour:, lasting:, difficulty:)
      @b = build
      @floors = floors
      @tables = tables
      @behaviour = behaviour
      @lasting = lasting
      @difficulty = difficulty
      declare
    end

    # The guards themselves, as the framework's pool: one slot per man on the floor being
    # played, with the fields #declare lists.
    attr_reader :pool

    # POINT AT FLOOR +n+'S SLICE of the tables of where everybody started. Written inside the
    # arm the view runs for that floor as it starts; see FirstPerson#select_floor.
    def select_floor(n)
      @count = @tables.fetch_floor_value(:guards, n)
      @first = @tables.run_start(:guards, n)
    end

    # EVERYBODY OUT, THEN THIS FLOOR'S PEOPLE IN.
    #
    # A KILLED GUARD IS NEVER TAKEN OUT OF THE POOL while a floor is being played — he lies where
    # he fell, in a state that lasts for ever, because a body is part of the room. So the pool
    # arrives here full of whoever was on the last floor, alive or not, and the count is a
    # different one from the floor about to start.
    #
    # Emptying it and filling it again is the honest way to say that, and it is the pool's own
    # two verbs rather than anything reaching inside it. It also costs nothing worth counting:
    # this runs when a floor starts and never while one is being played.
    #
    # AND THIS IS WHERE HOW TOUGH YOU SAID YOU WERE IS SPENT. The floor's slice holds every
    # guard it can ever hold; the ones a game set this way does not have are walked over and
    # never spawned, so they cost this routine one comparison each and the frame nothing.
    #
    # +counts+ is a Hash, so that this reaches the variables in it. Its :slot is working room the
    # view already has, borrowed for the length of this, and its :kill_total is the floor's count of
    # men to kill, which this is what fills. Its :kills is the count of those already dead.
    def refill(counts)
      @pool.each(&:remove)
      # EACH ONE WHO STANDS UP IS ONE MORE TO KILL, which is the floor's kill total: the original
      # adds one in every Spawn (wl_act2.cpp).
      #
      # ...AND WHICH PASS HE THINKS ON is counted the same way, over the guards who really stand
      # up and not over the slots walked — otherwise an easier game, which spawns from scattered
      # slots, could land most of its floor on the same pass and pay for it twice over on that one.
      counts[:kill_total] = 0
      @b.repeat(@count) do |n|
        counts[:slot] = @first + n
        if @difficulty >= @home_from[counts[:slot]]
          at = counts[:slot]
          @pool.spawn x: @home_x[at], y: @home_y[at],
                      dir: @home_dir[at],
                      state: @home_state[at], ticks: @home_ticks[at],
                      hp: @hit_points[@home_tough[at] + @difficulty],
                      wait: 0, togo: 0.0, shown: 0, awake: 0, dropped: 0,
                      ambush: @home_ambush[at], noticed: 0, door: 0, turn: counts[:kill_total] % 2
          counts[:kill_total] += @home_counted[at]
          counts[:kills] += @home_killed[at]
        end
      end
    end

    private

    def declare
      # WHERE THE FLOOR BEING PLAYED HAS ITS SLICE of the tables below, set as each floor starts
      # (#select_floor). They start at the first floor's own numbers, because at boot no floor has
      # been STARTED — the game simply begins on the first one.
      @first = @b.var :_guard_first, @tables.run_start(:guards, 0)
      @count = @tables.declare_floor_value(:_guard_count, :guards)

      # +dropped+ is whether he is lying beside the clip of ammunition he left when he fell. It is
      # a field of his rather than a place of its own because where the clip lies is where he
      # lies — see Pickups#a_guard_fell.
      # +awake+ is whether he has ever been on the screen. Once he has, he thinks for ever after
      # wherever he stands; until then he thinks only while his room is open to the player. That
      # is the original's own rule (it calls him "active") and it is what keeps a floor of
      # twenty-nine guards affordable — see Rooms.
      # +ambush+ is a guard put down lying in wait, who has to SEE you: he is the one a gunshot
      # does not bring. Carried on him rather than read off the map because the original clears
      # it the moment he does see you, and from then on he is a guard like any other.
      # +noticed+ is that he has seen you and has not yet chosen a way to sidestep, which is the one
      # time he is allowed to turn straight round (FL_FIRSTATTACK).
      # +door+ is one more than the number of the door he is waiting at, or nought for none.
      @pool = @lasting.pool :guard, x: 0.0, y: 0.0, dir: 0, state: 0, ticks: 0, wait: 0, togo: 0.0,
                            hp: 0, shown: 0, awake: 0, turn: 0, dropped: 0, ambush: 0, noticed: 0, door: 0,
                            capacity: @floors.room_for(:guards), widths: widths
      first_guards = @tables.first_guards_while_building(Guards::DEFAULT_DIFFICULTY)
      stand_up_first_floor(first_guards) if first_guards
      declare_where_they_start
      stand_up_first_floor_from_tables unless first_guards
    end

    # HOW WIDE EACH SLOT OF A GUARD HAS TO BE, given what this cartridge can really put down.
    # See NARROW for the ones that never change and why these two do.
    def widths
      NARROW.merge(hp: self.class.width_for(@behaviour.hit_points.max),
                   state: self.class.width_for(@behaviour.length),
                   ticks: self.class.width_for(@behaviour.longest))
    end

    # THE FIRST FLOOR'S GUARDS AT BOOT, written out rather than read from the tables, because
    # at boot there is no floor to have started yet. Every floor after this one is filled by
    # #refill from the same tables the first floor's numbers came from.
    #
    # THESE NEED NO TEST AGAINST THE SETTING, where the refill does. Nothing has run yet, so how
    # tough the game is set is still exactly the number the variable was declared with — a fact
    # known while the cartridge is built. So the ones that setting names are written out and the
    # rest are simply not, which is also why this costs no more than the guards it writes.
    def stand_up_first_floor(guards)
      guards.each_with_index do |guard, n|
        # A guard stands in the middle of his cell, like the player does.
        state = @behaviour.starting_state(guard)
        @pool.spawn x: guard.x + 0.5, y: guard.y + 0.5,
                    dir: Guards.direction_of(guard.facing),
                    state: state, ticks: @behaviour.state_at(state).ticks,
                    hp: @behaviour.toughness_of(guard.kind, Guards.number_of(Guards::DEFAULT_DIFFICULTY)),
                    ambush: guard.ambush ? 1 : 0,
                    # ...and thinks on every other frame, alternately with his neighbours, so
                    # the floor's thinking is spread evenly over the frames rather than
                    # arriving all at once.
                    turn: n % 2
      end
    end

    # ...OR, WHERE THE BUILD DOES NOT KNOW THEM (a whole build, whose floors are read from the pack
    # after it is built), the first floor's guards stood up from the tables at power-on, as #refill
    # stands up every later floor's. This is written where the pool is declared, before the game
    # loop, which runs once. The counts it keeps are its own: the floor's tally is set when play
    # starts.
    def stand_up_first_floor_from_tables
      refill(slot: @b.var(:_guard_boot_slot, 0), kill_total: @b.var(:_guard_boot_kill_total, 0),
             kills: @b.var(:_guard_boot_kills, 0))
    end

    # WHERE EVERY GUARD STARTED, so a floor can be started again. All of it is settled while the
    # cartridge is built and none of it ever changes, so it lives in the cartridge — the same
    # facts the first floor's spawns are made of, kept where a routine can read them back by
    # number. Every floor's guards end to end, in the order the floors are played.
    #
    # WHERE HE STANDS AND HOW is a floor's own (FloorTables#declare_items); WHAT HE STARTS AS follows
    # from his kind and whether he patrols, so a whole build keeps that once for each
    # (FloorTables#declare_guard_rule).
    def declare_where_they_start
      tables = @tables
      everyone = ->(floor) { guards_of(floor) }
      @home_x = tables.declare_items(:guard_home_x, slot: :guard_x, plus: 0.5) { |f| guards_of(f).map { |g| g.x + 0.5 } }
      @home_y = tables.declare_items(:guard_home_y, slot: :guard_y, plus: 0.5) { |f| guards_of(f).map { |g| g.y + 0.5 } }
      @home_dir = tables.declare_items(:guard_home_dir, slot: :guard_dir, width: :byte) do |f|
        guards_of(f).map { |g| Guards.direction_of(g.facing) }
      end
      @home_state = tables.declare_guard_rule(:guard_home_state, guards_of: everyone, width: @behaviour.width) do |g|
        @behaviour.starting_state(g)
      end
      # ...and whether he is one of the men to kill. All of them are but the man inside the machine.
      @home_counted = tables.declare_guard_rule(:guard_home_counted, guards_of: everyone, width: :byte) do |g|
        Enemy[g.kind].counted? ? 1 : 0
      end
      # ...and whether he counts as one already killed. See Enemy#killed_from_the_start?.
      @home_killed = tables.declare_guard_rule(:guard_home_killed, guards_of: everyone, width: :byte) do |g|
        Enemy[g.kind].killed_from_the_start? ? 1 : 0
      end
      @home_ticks = tables.declare_guard_rule(:guard_home_ticks, guards_of: everyone, width: @behaviour.ticks_width) do |g|
        @behaviour.state_at(@behaviour.starting_state(g)).ticks
      end
      @home_ambush = tables.declare_items(:guard_home_ambush, slot: :guard_ambush, width: :byte) do |f|
        guards_of(f).map { |g| g.ambush ? 1 : 0 }
      end
      # ...and the easiest setting each one turns up on, which is the whole of how a harder game
      # is a fuller floor. Every floor carries every guard it can ever hold; this is the column
      # that says which of them a given game stands up. See Guards::FROM.
      @home_from = tables.declare_items(:guard_home_from, slot: :guard_from, width: :byte) { |f| guards_of(f).map(&:from) }
      # HOW MUCH KILLING EACH ONE TAKES, which needs two tables and not one: the mutant is the
      # one kind a harder game toughens, and how hard the game is set is picked long after the
      # cartridge is built. So each one carries where ITS four numbers begin, and the floor's
      # start reads the one the setting names.
      @home_tough = tables.declare_guard_rule(:guard_home_tough, guards_of: everyone, width: :byte) do |g|
        @behaviour.hit_points_at(g.kind)
      end
      @hit_points = @b.table :guard_hit_points, @behaviour.hit_points, width: :half
    end

    def guards_of(floor) = floor.guards&.guards || []

    # A table must hold something, and a floor may hold nobody; nothing ever reads the one
    # unused entry because nobody is ever spawned from it.
  end
end
