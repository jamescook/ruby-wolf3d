# frozen_string_literal: true

module Wolf3D
  # WHAT THE BOSSES THROW: syringes, rockets and fire. The first things in the game that move through
  # the world on their own, and the only ones that move in a straight line.
  #
  # A THROWN THING IS A STATE MACHINE LIKE A GUARD, and smaller: a place, a heading, a picture that
  # cycles, and what to do when the picture has run out (wl_act2.cpp, T_Projectile and the state
  # tables above each thrower). Its smoke and its burst are the same thing with no heading, so they
  # keep a slot here too, which is what the original does with them.
  #
  # THE COLLISION IS NOT A GUARD'S. A guard walks from the middle of one cell to the middle of the
  # next and asks about one cell. One of these crosses cells in mid-flight, so it asks about the four
  # corners of a small box around itself (ProjectileTryMove), and a door or a barrel stops it just as
  # a wall does.
  #
  # NO ANGLES. The original works out an arctangent to aim and then a sine and a cosine each move, and
  # this has neither. What it wants is a step with the right length pointing the right way, which is
  # the line to the player scaled once when the thing is thrown. That length is got without a square
  # root, by the long side plus two fifths of the short one, which is out by a few parts in a hundred
  # at worst, and the speed of a rocket can stand that.
  class Thrown
    # Throwing one (#throw_from, #throw_it, #pick_the_way): what is thrown and from where, the line
    # to the player, its long and short sides, what scales that line to the thrown thing's speed,
    # and which of the eight ways it heads.
    game_variables :what, :fromx, :fromy, :dx, :dy, :long, :short, :scale, :way, saved: false
    # One thing's pass (#move, #fly, #age): the row of the table it is on, and whether it is gone
    # or has burst, so nothing more happens to it this pass.
    game_variables :row, :gone, saved: false

    # One row of the table: the picture, whether it turns with where you stand from it (a rocket
    # does), how long it lasts in the original's units, whether it moves on every pass, what comes
    # after it (nil for nothing, and the slot is given back), and what is hung on its end. +smokes+
    # leaves a puff behind and bursts on a wall, and +hits+ is what a blow takes off you before the
    # random part.
    #
    # +hops+ IS FIRE, WHICH MOVES ONLY AS EACH PICTURE ENDS. The original hangs T_Projectile on the end
    # of s_fire1 and s_fire2 where it hangs it on the think of everything else (wl_act2.cpp), so a
    # flame creeps a step every six units. That is what makes it something you can walk away from.
    Row = Data.define(:name, :picture, :turns, :ticks, :flies, :after, :smokes, :hits, :hops)

    def self.row(name, picture, ticks, after, turns: false, flies: false, smokes: false, hits: 0, hops: false)
      Row.new(name:, picture:, turns:, ticks:, flies:, after:, smokes:, hits:, hops:)
    end

    # Twenty and thirty, and nothing for fire, with a random part on top of each. From T_Projectile.
    NEEDLE_HITS = 20
    ROCKET_HITS = 30

    NEEDLES = Enemy::THROWN_PICTURES.fetch(:needle)
    FLAMES = Enemy::THROWN_PICTURES.fetch(:flame)
    ROCKET = Enemy::THROWN_PICTURES.fetch(:rocket).first
    SMOKE = ROCKET + 8 # after the eight sides of the rocket...
    BOOM = SMOKE + 4   # ...and the four puffs of smoke

    ROWS = Ractor.make_shareable([
      row(:needle1, NEEDLES[0], 6, :needle2, flies: true, hits: NEEDLE_HITS),
      row(:needle2, NEEDLES[1], 6, :needle3, flies: true, hits: NEEDLE_HITS),
      row(:needle3, NEEDLES[2], 6, :needle4, flies: true, hits: NEEDLE_HITS),
      row(:needle4, NEEDLES[3], 6, :needle1, flies: true, hits: NEEDLE_HITS),
      row(:rocket, ROCKET, 3, :rocket, turns: true, flies: true, smokes: true, hits: ROCKET_HITS),
      row(:fire1, FLAMES[0], 6, :fire2, hops: true),
      row(:fire2, FLAMES[1], 6, :fire1, hops: true),
      row(:smoke1, SMOKE, 3, :smoke2),
      row(:smoke2, SMOKE + 1, 3, :smoke3),
      row(:smoke3, SMOKE + 2, 3, :smoke4),
      row(:smoke4, SMOKE + 3, 3, nil),
      row(:boom1, BOOM, 6, :boom2),
      row(:boom2, BOOM + 1, 6, :boom3),
      row(:boom3, BOOM + 2, 6, nil)
    ])

    def self.number_of(name) = ROWS.index { |row| row.name == name }

    # WHAT EACH THING THROWN STARTS AS, and how fast it goes, in cells a unit of the original's time:
    # its speeds are 0x2000 and 0x1200 of 0x10000. In the order Enemy::THROWN numbers them.
    STARTS = Ractor.make_shareable([[:needle1, 0x2000], [:rocket, 0x2000], [:fire1, 0x1200]])

    # A pass of this game is one of the original's units, as it is for every enemy. Everything here
    # counts sixths of one and comes down by Enemy::SIXTHS_A_PASS.
    SIXTHS = Enemy::SIXTHS
    PER_PASS = Enemy::SIXTHS_A_PASS
    def self.speed_of(raw) = raw * PER_PASS / SIXTHS / Enemy::CELL.to_f

    # HOW NEAR COUNTS: a box of an eighth of a cell each way for walls (PROJSIZE), and three quarters
    # of a cell each way for the player (PROJECTILESIZE).
    SIZE = 0x2000 / Enemy::CELL.to_f
    REACH = 0xc000 / Enemy::CELL.to_f

    # The most that can be in the air at once. The original shares 150 slots with everything else
    # and stops throwing when they run out, and this stops the same way. A rocket trails six puffs
    # of smoke, so this is about two rockets and their smoke, or a burst of fire and a bit.
    MOST = 16

    # WHICH OF THE EIGHT WAYS A HEADING IS NEAREST, by whether it goes left, nowhere or right and up,
    # nowhere or down, as Guards::WAYS numbers them. The rocket's eight pictures are read by this.
    # The middle holds east, which nothing can land on because a heading has some length to it.
    OCTANTS = [3, 2, 1, 4, 0, 0, 5, 6, 7].freeze

    # A heading counts as along one axis when the other is under this share of it: tan 22.5 degrees.
    SQUARE_ON = 0.41

    # What the player stands to lose to a blow, past the fixed part: an eighth of a random byte.
    ROLLS = 256
    ROLL_PART = 8

    # +mind+ is what says whether a cell can be flown through and what a blow does to the player.
    def initialize(build:, mind:, player:, things:, lasting:)
      @b = build
      @mind = mind
      @player = player
      @things = things
      @pool = lasting.pool :thrown, x: 0.0, y: 0.0, dx: 0.0, dy: 0.0, row: 0, ticks: 0, dir: 0,
                                    capacity: MOST, widths: { row: :byte, ticks: :byte, dir: :byte }
      declare
    end

    # The pool itself, which the view walks to draw them, and what each row wears and whether it turns.
    attr_reader :pool, :shape_of, :turns_of

    # One pass of everything in the air.
    def update = @b.call(:thrown_things_move)

    # EVERYTHING GOES when a floor starts, whatever was in the air as the last one ended.
    def clear = @pool.each(&:remove)

    def full? = @pool.full?

    # ONE IS THROWN FROM WHERE +thrower+ STANDS AT THE PLAYER. +what+ is its number in Enemy::THROWN.
    def throw_from(thrower, what)
      @what = what
      @fromx = thrower.x
      @fromy = thrower.y
      @b.call :throw_at_the_player
    end

    private

    def declare
      b = @b
      @shape_of = b.table :thrown_shape, ROWS.map { |r| @things.position_of(r.picture) || 0 }, width: :half
      @turns_of = b.table :thrown_turns, ROWS.map { |r| r.turns ? 1 : 0 }, width: :byte
      @ticks_of = b.table :thrown_ticks, ROWS.map { |r| r.ticks * SIXTHS }, width: :byte
      @flies = b.table :thrown_flies, ROWS.map { |r| r.flies ? 1 : 0 }, width: :byte
      @hops = b.table :thrown_hops, ROWS.map { |r| r.hops ? 1 : 0 }, width: :byte
      @smokes = b.table :thrown_smokes, ROWS.map { |r| r.smokes ? 1 : 0 }, width: :byte
      @hits = b.table :thrown_hits, ROWS.map(&:hits), width: :byte
      # What comes next, and one past the last row means nothing does.
      @after = b.table :thrown_after, ROWS.map { |r| r.after ? self.class.number_of(r.after) : ROWS.length },
                       width: :byte
      @first = b.table :thrown_first, STARTS.map { |(name, _)| self.class.number_of(name) }, width: :byte
      @pace_of = b.table :thrown_pace, STARTS.map { |(_, raw)| self.class.speed_of(raw) }
      @octant = b.table :thrown_octant, OCTANTS, width: :byte
      declare_the_scratch
      b.func(:throw_at_the_player) { throw_it }
      @pool.func(:thrown_thing_flies) { |shot| fly(shot) }
      @pool.func(:thrown_thing_ages) { |shot| age(shot) }
      b.func(:thrown_things_move) { @pool.each { |shot| move(shot) } }
    end

    def declare_the_scratch
      b = @b
      @what = 0
      @fromx = 0.0
      @fromy = 0.0
      @dx = 0.0
      @dy = 0.0
      @long = 0.0
      @short = 0.0
      @scale = 0.0
      @way = 0

      @row = 0
      @gone = 0
    end

    # THE LINE TO THE PLAYER, TURNED INTO A STEP. See the top of the file for why there is no root.
    def throw_it
      @dx = @player.x - @fromx
      @dy = @player.y - @fromy
      @long = @dx.abs
      @short = @dy.abs
      if @short > @long
        @scale = @long
        @long = @short
        @short = @scale
      end
      @scale = @pace_of[@what] / (@long + (@short * 0.4))
      pick_the_way
      @row = @first[@what]
      @pool.spawn x: @fromx, y: @fromy, dx: @dx * @scale, dy: @dy * @scale, row: @row,
                  ticks: @ticks_of[@row], dir: @way
    end

    def pick_the_way
      @long = @long * SQUARE_ON
      @way = 4
      @way = 3 if @dx < -@long
      @way = 5 if @dx > @long
      @way += 3 if @dy > -@long
      @way += 3 if @dy > @long
      @way -= 3
      @way = @octant[@way]
    end

    # One thing, one pass. It moves, and if that is the end of it there is nothing left to age.
    def move(shot)
      @gone = 0
      @row = shot.row
      @b.call :thrown_thing_flies if @flies[@row] == 1
      @b.call :thrown_thing_ages if @gone == 0
    end

    # INTO A WALL, or into you, in that order, which is the original's: a rocket that reaches a wall
    # beside you bursts on the wall.
    def fly(shot)
      shot.x += shot.dx
      shot.y += shot.dy
      if @mind.blocked_around(shot.x, shot.y, SIZE)
        hit_a_wall(shot)
      elsif (@player.x - shot.x).abs < REACH && (@player.y - shot.y).abs < REACH
        @mind.hit_the_player(shot, @hits[@row] + (@b.rand(0..ROLLS - 1) / ROLL_PART))
        finish(shot)
      end
    end

    # A ROCKET BURSTS. A syringe and a flame are simply gone.
    def hit_a_wall(shot)
      if @smokes[@row] == 1
        @row = self.class.number_of(:boom1)
        shot.row = @row
        shot.ticks = @ticks_of[@row]
        @gone = 1
      else
        finish(shot)
      end
    end

    def finish(shot)
      shot.remove
      @gone = 1
    end

    # THE PICTURE RUNS OUT. A rocket leaves a puff where it is each time round, and a puff or a burst
    # that has shown its last picture gives its slot back.
    def age(shot)
      shot.ticks -= PER_PASS
      if shot.ticks <= 0
        @b.call :thrown_thing_flies if @hops[@row] == 1
        next_picture(shot) if @gone == 0
      end
    end

    def next_picture(shot)
      leave_some_smoke(shot) if @smokes[@row] == 1
      @row = @after[@row]
      if @row == ROWS.length
        shot.remove
      else
        shot.row = @row
        shot.ticks += @ticks_of[@row]
      end
    end

    def leave_some_smoke(shot)
      @pool.spawn x: shot.x, y: shot.y, dx: 0.0, dy: 0.0, row: self.class.number_of(:smoke1),
                  ticks: 2 * @ticks_of[self.class.number_of(:smoke1)], dir: 0
    end
  end
end
