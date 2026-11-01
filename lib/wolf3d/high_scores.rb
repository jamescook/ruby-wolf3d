# frozen_string_literal: true

module Wolf3D
  # THE SEVEN BEST GAMES ON THIS CARTRIDGE, each a name, the floor it ended on and a score. They
  # survive the power going off, and a new cartridge starts with the seven names the original ships
  # (id_us_1.cpp, Scores).
  #
  # A NAME IS HELD AS LETTERS, one list for all seven, and that is why it is drawn a letter at a time.
  # The framework's words are painted into the cartridge as it is built, so a word nobody has typed
  # yet cannot be one of them. Each letter of the small alphabet is a little picture instead, and the
  # columns they land on are even because that is all a picture here can start on.
  #
  # ON A PAD a name is picked a letter at a time, which the original has no need of: up and down
  # change the letter, left and right change which one.
  class HighScores
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
    # ...and every character a name on this table can hold.
    LETTERS = Ractor.make_shareable((ALPHABET + STARTING_NAMES.join).chars.uniq - [" "])

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

    # A BLANK IS AS WIDE AS A THIN LETTER.
    BLANK_WIDTH = 6

    # How many passes a held button waits between letters.
    HELD_REPEAT = 8

    NOBODY = -1

    def initialize(build:, art:, palette:, view:, player:, floor:)
      @b = build
      @art = art
      @palette = palette
      @player = player
      @floor = floor
      @floors = view.floors
      declare
    end

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
      [@scores, @levels, @episodes, @names].each { |list| @record.keep list }
      @record[0].load

      @new_row = b.var :_score_new_row, NOBODY
      @number = b.var :_score_number, 0
      @row = b.var :_score_row, 0
      @letter = b.var :_score_letter, 0
      @column = b.var :_score_column, 0
      @code = b.var :_score_code, 0
      @half_x = b.var :_score_half_x, 0
      @y = b.var :_score_y, 0
      @spot = b.var :_score_spot, 0
      @from = b.var :_score_from, 0
      @wait = b.var :_score_wait, 0
      @earned_floor = b.var :_score_earned_floor, 0
      @earned_episode = b.var :_score_earned_episode, 0
      @alphabet = b.table :high_score_alphabet, ALPHABET.chars.map(&:ord), width: :byte
      @floor_number = b.table :high_score_floor_number, @floors.map { |f| (f.index % Floors::PER_EPISODE) + 1 }, width: :byte
      @episode_number = b.table :high_score_episode_number, @floors.map { |f| (f.index / Floors::PER_EPISODE) + 1 }, width: :byte
      declare_letters
      b.func(:enter_high_score, fast: false) { insert_game }
      b.func(:edit_high_score_name, fast: false) { edit_letter }
      b.func(:draw_high_score_names, fast: false) { draw_names }
      b.func(:draw_high_score_letter, fast: false) { draw_letter }
    end

    # EVERY LETTER AS A PICTURE, in its own width made up to an even number. See the class.
    def declare_letters
      glyphs = @art.font(0)
      @pictured = LETTERS.select { |char| glyphs[char] }
      @pictured.each do |char|
        rows = glyphs[char]
        wide = even_width(rows)
        @b.image letter_picture(char), width: wide, height: rows.length,
                                       data: rows.flat_map { |row| painted(row, wide) }
      end
      widths = (0..127).map { |code| glyphs[code.chr] && code.chr != " " ? even_width(glyphs[code.chr]) : BLANK_WIDTH }
      @width_of = @b.table :high_score_letter_width, widths, width: :byte
    end

    def even_width(rows) = (rows.first.length + 1) & ~1

    def painted(row, wide)
      ground = @palette[Menus::BACKGROUND]
      row.map { |ink| ink.zero? ? ground : @palette[INK] } + ([ground] * (wide - row.length))
    end

    def letter_picture(char) = :"score_letter_#{char.ord}"

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
        @half_x = NAME_X / 2
        @y = TOP_ROW + (row * ROW_STEP)
        @spot = row * NAME_ROOM
        @b.repeat(NAME_ROOM) do |n|
          @code = @names[@spot + n]
          @b.call :draw_high_score_letter
          @half_x += @width_of[@code] / 2
        end
        draw_figures(row)
      end
    end

    # ONE TEST PER LETTER, once, and every place calls it.
    def draw_letter
      @pictured.each { |char| @b.blit letter_picture(char), @half_x * 2, @y if @code == char.ord }
    end

    # WHICH FLOOR, AS THE ORIGINAL WRITES IT, E1/L3, and the score against the right of its room. In
    # these little pictures rather than `draw_number`, whose digits each take the width of the widest
    # letter in the alphabet, which leaves a score running off the screen.
    def draw_figures(row)
      @half_x = FLOOR_X / 2
      draw_character("E")
      @number = @episodes[row]
      draw_digits(1)
      draw_character("/")
      draw_character("L")
      @number = @levels[row]
      draw_digits(FLOOR_DIGITS)
      @half_x = SCORE_X / 2
      @number = @scores[row]
      draw_digits(SCORE_DIGITS)
    end

    def draw_character(char)
      @code = char.ord
      @b.call :draw_high_score_letter
      @half_x += @width_of[@code] / 2
    end

    # @number, in +digits+ places, with places it has not reached left bare.
    def draw_digits(digits)
      digits.times do |i|
        place = 10**(digits - 1 - i)
        if place == 1 || @number >= place
          @code = "0".ord + ((@number / place) % 10)
          @b.call :draw_high_score_letter
        end
        @half_x += DIGIT_WIDTH / 2
      end
    end

    # A line under the letter being picked. The width of the letters before it is walked again.
    def draw_cursor
      @half_x = NAME_X / 2
      @spot = @new_row * NAME_ROOM
      @b.repeat(@column) { |n| @half_x += @width_of[@names[@spot + n]] / 2 }
      @b.draw_rect_at @half_x * 2, TOP_ROW + (@new_row * ROW_STEP) + 11, BLANK_WIDTH, 1, @palette[INK]
    end
  end
end
