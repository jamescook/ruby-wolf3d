# frozen_string_literal: true

module Wolf3D
  # THE SEVEN BEST GAMES ON THIS CARTRIDGE, each a name, the floor it ended on and a score. They
  # survive the power going off, and a new cartridge starts with the seven names the original ships
  # (id_us_1.cpp, Scores).
  #
  # A NAME IS HELD AS LETTERS, one list for all seven, and drawn a letter at a time. See SmallLetters.
  #
  # ON A PAD a name is picked a letter at a time, which the original has no need of: up and down
  # change the letter, left and right change which one.
  class HighScores
    game_variables :row, :letter, :column, :spot, :from, :wait, :earned_floor, :earned_episode, :new_row,
                   :number, saved: false

    ROWS = 7

    # ROOM FOR THE LONGEST NAME THE ORIGINAL SHIPS, and a typed one stops sooner so that a name of
    # wide letters still clears the next column.
    NAME_ROOM = 15
    TYPED_LETTERS = 12

    STARTING_SCORE = 10_000
    STARTING_FLOOR = 1
    STARTING_EPISODE = 1 # the original's table starts at zero, and prints one more than it holds
    STARTING_NAMES = ["id software-'92", "Adrian Carmack", "John Carmack", "Kevin Cloud",
                      "Tom Hall", "John Romero", "Jay Wilbur"].freeze

    # What a letter picked with the pad runs through, from a blank.
    ALPHABET = " ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-'./"

    # Where the three columns go, and the rows. The original's are for a screen 320 by 200.
    NAME_X = 16
    FLOOR_X = 138
    SCORE_X = 186
    SCORE_DIGITS = 6
    FLOOR_DIGITS = 2
    DIGIT_WIDTH = 8
    NAME_LABEL_Y = 50
    TOP_ROW = 62
    ROW_STEP = 13

    # White, the original's SETFONTCOLOR(15, ...), on the ground every menu here is drawn on.
    INK = 15

    # How many passes a held button waits between letters.
    HELD_REPEAT = 8

    NOBODY = -1

    # +setting+ is the SOUND row's variable, which this record keeps too. A record takes a whole
    # stretch of the save memory however small it is, and the saved games leave no room for another,
    # so the one thing the game remembers between games goes with the other. The original keeps both
    # in files of their own.
    def initialize(build:, letters:, palette:, view:, player:, floor:, setting:)
      @b = build
      @letters = letters
      @palette = palette
      @player = player
      @floor = floor
      @floors = view.floors
      @setting = setting
      declare
    end

    # What the SOUND row has just changed, written down.
    def save_setting = @record[0].save

    # Which row a game has just earned, or NOBODY.
    attr_reader :new_row

    # WHERE A FINISHED GAME GOES ON THE TABLE (CheckHighScore, wl_inter.cpp): above the first row it
    # beats, on the score and then on the floor reached, and the rows under it move down one.
    def enter_game = @b.call(:enter_high_score)

    # One pass of picking a name. The row is left with what has been picked so far.
    def edit_name = @b.call(:edit_high_score_name)

    # The name is finished, and now the table is worth keeping.
    def finish_name
      @new_row = NOBODY
      @record[0].save
    end

    # THE WHOLE TABLE, every pass the screen is up.
    def draw
      @b.call :draw_high_score_names
      draw_cursor if @new_row != NOBODY
    end

    private

    def declare
      b = @b
      @scores = b.list :high_score_points, capacity: ROWS
      @levels = b.list :high_score_floor, capacity: ROWS, width: :byte
      @episodes = b.list :high_score_episode, capacity: ROWS, width: :byte
      @names = b.list :high_score_names, capacity: ROWS * NAME_ROOM, width: :byte
      ROWS.times do |row|
        @scores << STARTING_SCORE
        @levels << STARTING_FLOOR
        @episodes << STARTING_EPISODE
        NAME_ROOM.times { |n| @names << (STARTING_NAMES[row][n] || " ").ord }
      end
      @record = b.save_data :high_scores, copies: 1, fast: false
      [@scores, @levels, @episodes, @names, @setting].each { |kept| @record.keep kept }
      @record[0].load

      @new_row = NOBODY
      @number = 0
      @row = 0
      @letter = 0
      @column = 0
      @spot = 0
      @from = 0
      @wait = 0
      @earned_floor = 0
      @earned_episode = 0
      @alphabet = b.table :high_score_alphabet, ALPHABET.chars.map(&:ord), width: :byte
      @floor_number = b.table :high_score_floor_number, @floors.map { |f| (f.index % Floors::PER_EPISODE) + 1 }, width: :byte
      @episode_number = b.table :high_score_episode_number, @floors.map { |f| (f.index / Floors::PER_EPISODE) + 1 }, width: :byte
      b.func(:enter_high_score, fast: false) { insert_game }
      b.func(:edit_high_score_name, fast: false) { edit_letter }
      b.func(:draw_high_score_names, fast: false) { draw_names }
    end

    def insert_game
      @earned_floor = @floor_number[@floor]
      @earned_episode = @episode_number[@floor]
      @new_row = NOBODY
      @row = 0
      @b.repeat(ROWS, stop_when: @new_row != NOBODY) do
        @new_row = @row if beats_row
        @row += 1
      end
      open_row if @new_row != NOBODY
    end

    def beats_row
      (@player.score > @scores[@row]) ||
        ((@player.score == @scores[@row]) & (@earned_floor > @levels[@row]))
    end

    def open_row
      @row = ROWS - 1
      @b.repeat(ROWS - 1 - @new_row) { move_row_down }
      @scores[@new_row] = @player.score
      @levels[@new_row] = @earned_floor
      @episodes[@new_row] = @earned_episode
      @spot = @new_row * NAME_ROOM
      @b.repeat(NAME_ROOM) do |n|
        @names[@spot + n] = " ".ord
      end
      @letter = 0
      @column = 0
      @wait = 0
    end

    def move_row_down
      @scores[@row] = @scores[@row - 1]
      @levels[@row] = @levels[@row - 1]
      @episodes[@row] = @episodes[@row - 1]
      @spot = @row * NAME_ROOM
      @b.repeat(NAME_ROOM) do |n|
        @names[@spot + n] = @names[@spot - NAME_ROOM + n]
      end
      @row -= 1
    end

    def edit_letter
      @wait -= 1 if @wait > 0
      move_letter(1) if ready_to_move(:up)
      move_letter(-1) if ready_to_move(:down)
      if @b.pressed(:right)
        @column += 1 if @column < TYPED_LETTERS - 1
        @letter = 0
      end
      if @b.pressed(:left)
        @column -= 1 if @column > 0
        @letter = 0
      end
    end

    # A press moves at once, and held it goes on moving.
    def ready_to_move(button) = @b.pressed(button) || (@b.held(button) && (@wait == 0))

    def move_letter(by)
      @wait = HELD_REPEAT
      @letter = (@letter + by + ALPHABET.length) % ALPHABET.length
      @names[(@new_row * NAME_ROOM) + @column] = @alphabet[@letter]
    end

    def draw_names
      @b.repeat(ROWS) do |row|
        @letters.start_at(NAME_X, TOP_ROW + (row * ROW_STEP))
        @spot = row * NAME_ROOM
        @b.repeat(NAME_ROOM) { |n| @letters.draw(@names[@spot + n]) }
        draw_figures(row)
      end
    end

    # WHICH FLOOR, AS THE ORIGINAL WRITES IT, E1/L3, and the score against the right of its room. In
    # these little pictures rather than `draw_number`, whose digits each take the width of the widest
    # letter in the alphabet, which leaves a score running off the screen.
    def draw_figures(row)
      @letters.start_at(FLOOR_X, TOP_ROW + (row * ROW_STEP))
      @letters.draw("E".ord)
      @number = @episodes[row]
      draw_digits(1)
      @letters.draw("/".ord)
      @letters.draw("L".ord)
      @number = @levels[row]
      draw_digits(FLOOR_DIGITS)
      @letters.start_at(SCORE_X, TOP_ROW + (row * ROW_STEP))
      @number = @scores[row]
      draw_digits(SCORE_DIGITS)
    end

    # @number, in +digits+ places, with places it has not reached left bare.
    def draw_digits(digits)
      digits.times do |i|
        place = 10**(digits - 1 - i)
        if place == 1 || @number >= place
          @letters.draw("0".ord + ((@number / place) % 10))
        else
          @letters.skip(DIGIT_WIDTH)
        end
      end
    end

    # A line under the letter being picked. The width of the letters before it is walked again.
    def draw_cursor
      @letters.start_at(NAME_X, 0)
      @spot = @new_row * NAME_ROOM
      @b.repeat(@column) { |n| @letters.skip_past(@names[@spot + n]) }
      @b.draw_rect_at @letters.x, TOP_ROW + (@new_row * ROW_STEP) + 11, SmallLetters::BLANK_WIDTH, 1, @palette[INK]
    end
  end
end
