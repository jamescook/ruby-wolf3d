# frozen_string_literal: true

module Wolf3D
  # BJ RUNS OUT OF THE CASTLE, which is what walking onto the way out does (VictoryTile, wl_agent.cpp).
  # You stop being the player and become the camera: the view swings round to face back the way you
  # came and drifts backwards, and BJ appears a cell behind where you stood and runs past, jumps, and
  # yells (SpawnBJVictory, T_BJRun, VictorySpin).
  #
  # HE IS NOT AN ENEMY, so he is not in the guards' pool. He is one thing standing in the room, drawn
  # the way a rocket is, and he has no mind: only a list of pictures to go through, the last four of
  # which are the jump.
  class VictoryMarch
    # The pictures of him, in the order of the original's table: four running, four jumping.
    FIRST_PICTURE = 408
    PICTURES = Ractor.make_shareable((FIRST_PICTURE...(FIRST_PICTURE + 8)).to_a)

    # WHICH OF THEM, FOR HOW LONG, AND WHETHER HE MOVES WHILE IT LASTS (s_bjrun1 on, wl_act2.cpp). The
    # four short rows of the run are the original's way of giving a stride a beat on the ground.
    Pose = Data.define(:picture, :ticks, :moves)
    RUN = Ractor.make_shareable([Pose.new(0, 12, true), Pose.new(0, 3, false), Pose.new(1, 8, true),
                                 Pose.new(2, 12, true), Pose.new(2, 3, false), Pose.new(3, 8, true)])
    JUMP = Ractor.make_shareable([Pose.new(4, 14, true), Pose.new(5, 14, true), Pose.new(6, 14, true),
                                  Pose.new(7, 300, false)])
    POSES = Ractor.make_shareable(RUN + JUMP)
    FIRST_JUMP = RUN.length
    # He yells as the second picture of the jump ends (T_BJYell) and it is over as the last does.
    YELL_POSE = FIRST_JUMP + 1
    LAST_POSE = POSES.length - 1

    # HOW FAST, in the original's units a tic, and turned into cells a pass (BJRUNSPEED, BJJUMPSPEED).
    TICS_A_PASS = Enemy::SIXTHS_A_PASS.to_f / Enemy::SIXTHS
    RUN_STEP = 2048 / Enemy::CELL.to_f * TICS_A_PASS
    JUMP_STEP = 680 / Enemy::CELL.to_f * TICS_A_PASS
    # ...and the camera backing away (VictorySpin): 4096 a tic, as far as five cells and a bit.
    CAMERA_STEP = 4096 / Enemy::CELL.to_f * TICS_A_PASS
    CAMERA_TRAVEL = 5 + (0x3000 / Enemy::CELL.to_f)
    # The original turns three of its 360 degrees a tic.
    TURN_STEP = [(FirstPerson::TURN * 3 * Enemy::SIXTHS_A_PASS) / (360 * Enemy::SIXTHS), 1].max

    # He starts in the cell south of you, and the first thing T_BJRun does is arrive there, so six
    # tiles to run is five cells.
    CELLS_TO_RUN = 5

    # Only a cartridge with a floor that can be walked out of, on a copy holding his pictures.
    def self.pictures(floors, vswap)
      return [] unless vswap && vswap.sprite_count > PICTURES.last
      return [] unless floors.any? { |floor| floor.level.each_cell.any? { |x, y| floor.level.exit?(x, y) } }

      PICTURES
    end

    # +things+ is the row of pictures he is drawn from, and +sounds+ is the recorded sounds or nil.
    def initialize(build:, player:, victory:, things:, sounds: nil)
      @b = build
      @player = player
      @victory = victory
      @sounds = sounds
      @first_picture = things.position_of(FIRST_PICTURE)
      declare
    end

    # 1 while it runs, which stops the game being the player's and the menu opening.
    attr_reader :running

    # Where he is, which picture, for the view.
    attr_reader :x, :y, :picture

    # YOU HAVE REACHED THE WAY OUT.
    def begin_march
      if @running == 0
        @running = 1
        @x = @player.x.to_i.to_f + 0.5
        @y = @player.y.to_i.to_f + 1.5
        @togo = 1.0
        @cells = CELLS_TO_RUN
        @pose = 0
        @ticks = POSES.first.ticks * Enemy::SIXTHS
        @camera_stop = @player.y.to_i.to_f - CAMERA_TRAVEL
      end
    end

    # One pass of it. Nothing but this moves.
    def update = @b.call(:victory_march_step)

    # A NEW GAME HAS NO MARCH LEFT OVER.
    def start_again = @running = 0

    private

    def declare
      b = @b
      @running = b.var :_march_running, 0
      @x = b.var :_march_x, 0.0
      @y = b.var :_march_y, 0.0
      @togo = b.var :_march_togo, 0.0
      @camera_stop = b.var :_march_camera_stop, 0.0
      @cells = b.var :_march_cells, 0
      @pose = b.var :_march_pose, 0
      @ticks = b.var :_march_ticks, 0
      @picture = b.var :_march_picture, 0
      @south = FirstPerson::QUARTER
      @pose_picture = b.table :march_pose_picture, POSES.map { |pose| pose.picture + @first_picture }, width: :half
      @pose_ticks = b.table :march_pose_ticks, POSES.map { |pose| pose.ticks * Enemy::SIXTHS }, width: :half
      @pose_moves = b.table :march_pose_moves, POSES.map { |pose| pose.moves ? 1 : 0 }, width: :byte
      b.func(:victory_march_step, fast: false) { step }
    end

    def step
      if @running == 1
        swing_the_camera
        back_the_camera_away
        move_him
        count_down_the_pose
        @picture = @pose_picture[@pose]
      end
    end

    def swing_the_camera
      if @player.angle > @south
        @player.angle -= TURN_STEP
        @player.angle = @south if @player.angle < @south
      elsif @player.angle < @south
        @player.angle += TURN_STEP
        @player.angle = @south if @player.angle > @south
      end
    end

    def back_the_camera_away
      if @player.y > @camera_stop
        @player.y -= CAMERA_STEP
        @player.y = @camera_stop if @player.y < @camera_stop
      end
    end

    def move_him
      if @pose_moves[@pose] == 1
        if @pose >= FIRST_JUMP
          @y -= JUMP_STEP
        else
          @y -= RUN_STEP
          @togo -= RUN_STEP
          arrive_at_a_cell if @togo <= 0.0
        end
      end
    end

    def arrive_at_a_cell
      @togo = 1.0
      @cells -= 1
      if @cells <= 0
        @pose = FIRST_JUMP
        @ticks = @pose_ticks[FIRST_JUMP]
      end
    end

    def count_down_the_pose
      @ticks -= Enemy::SIXTHS_A_PASS
      next_pose if @ticks <= 0
    end

    def next_pose
      @sounds&.yeah if @pose == YELL_POSE
      if @pose == LAST_POSE
        @running = 0
        @victory.won
      else
        @pose += 1
        @pose = 0 if @pose == FIRST_JUMP && @cells > 0
        @ticks = @pose_ticks[@pose]
      end
    end
  end
end
