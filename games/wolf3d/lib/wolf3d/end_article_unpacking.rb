# frozen_string_literal: true

module Wolf3D
  # EACH EPISODE'S END ARTICLE LAID OUT INTO PAGES BY THE GAME ITSELF into the data pack (DataPack),
  # out of the words VgagraphUnpacking left in end_articles: what EndArticle.pages does in Ruby for a
  # trimmed build, with SmallLetters' widths, into the shape EpisodeEnd reads. article_pages holds
  # every page one after another, EpisodeEnd::LINES rows of EpisodeEnd::COLUMNS bytes each, nought
  # past a line's end; article_first_page where each episode's pages start, and one more for where
  # the last ends.
  #
  # THREE PASSES OVER EACH ARTICLE, in a list of the routine's: the carriage returns taken out; the
  # words cut at ^E and the colour and picture commands taken out, in place (what is kept never
  # gets ahead of what is read); then the words wrapped a word at a time, each line as wide as fits
  # EpisodeEnd::TEXT_WIDTH, a blank between words, each run of new lines between two words a new line
  # and a blank line for every one after the first, ^P a new page, and a page's lines going on to
  # another past EpisodeEnd::LINES (EndArticle.pages, .wrap).
  #
  # This file is game code (VBlank.require_game_file): an `if` on a number the routine reads is a
  # branch in it, and a number one method sets and another reads is one of its game_variables.
  class EndArticleUnpacking
    # Where the passes stand in the list: how many bytes it holds, and the place each pass reads
    # from. The page goes on from one episode to the next.
    game_variables :length, :read, :page
    # Pass two's working room: where the next kept byte goes, how far a command makes the reading
    # jump, and whether ^E has cut the article.
    game_variables :kept, :skip, :cut
    # Measuring a ^G command (#picture_command_length): where it has read to, which of its three
    # numbers it is in, that number's digits so far, and whether it has stopped.
    game_variables :command_at, :part, :digits, :command_ended
    # Pass three's place on the page: the line and column the next letter goes at, how wide the
    # line is in pixels so far, whether a page has been begun, and the new lines read since the
    # last word.
    game_variables :line, :column, :wide, :open, :new_lines
    # The word pass three is placing (#place_word): where it ends, how wide it is, and whether its
    # end has been found.
    game_variables :word_end, :word_wide, :word_ended

    ARTICLES = VgagraphUnpacking::ARTICLES
    ARTICLE_BYTES = VgagraphUnpacking::ARTICLE_BYTES

    # THE MOST PAGES AN ARTICLE MAKES: four, the six episodes' first, second, third and sixth and the
    # shareware's one, at 216 pixels and eleven lines; a page past them is left out.
    PAGES_EACH = 4
    PAGES = ARTICLES * PAGES_EACH

    # The longest a ^G command's three numbers and two commas run, and room past the words for
    # reading a byte or two ahead.
    PICTURE_COMMAND_BYTES = 32
    READ_AHEAD = PICTURE_COMMAND_BYTES + 2

    CARRIAGE_RETURN = 13
    NEW_LINE = 10
    CARET = "^".ord
    BLANK = " ".ord
    COMMA = ",".ord
    # What separates words, as Ruby's String#split takes it: blank, tab, new line, vertical tab, form
    # feed and carriage return.
    SPACES = [BLANK, 9, NEW_LINE, 11, 12, CARRIAGE_RETURN].freeze

    def self.page_bytes = EpisodeEnd::LINES * EpisodeEnd::COLUMNS

    def self.declare(slots)
      slots.numbers :article_pages, count: PAGES * page_bytes, width: :byte, signed: false
      slots.numbers :article_first_page, count: ARTICLES + 1, width: :byte, signed: false
    end

    # +b+ is the routine's builder, and +copy+, +pack+ and +release+ what `fill_from_copy` hands it.
    def initialize(b, copy, pack, release)
      @b = b
      @copy = copy
      @pack = pack
      @release = release
    end

    def fill
      @buffer = @b.list(:_article_buffer, capacity: ARTICLE_BYTES + READ_AHEAD)
      @widths = @b.table(:article_letter_width, letter_widths, width: :byte)
      @b.repeat(ARTICLE_BYTES + READ_AHEAD) { @buffer << 0 }
      @length = 0
      @read = 0
      @page = 0
      @kept = 0
      @skip = 0
      @cut = false
      @command_at = 0
      @part = 0
      @digits = 0
      @command_ended = false
      @line = 0
      @column = 0
      @wide = 0
      @open = false
      @new_lines = 0
      @word_end = 0
      @word_wide = 0
      @word_ended = false
      @pack[:article_first_page][0] = 0
      @b.repeat(ARTICLES) do |episode|
        take_out_returns(episode)
        cut_and_take_out_commands
        lay_out
        @page = PAGES if @page > PAGES
        @pack[:article_first_page][episode + 1] = @page
      end
    end

    private

    # How wide SmallLetters draws each character code: a letter at its even width, anything else a
    # blank's.
    def letter_widths
      widths = SmallLetterUnpacking.letters.to_h { |letter| [letter.code, letter.even_width] }
      (0..255).map { |code| widths.fetch(code, SmallLetters::BLANK_WIDTH) }
    end

    # PASS ONE: episode +episode+'s words into the list, with no carriage return; their count in
    # @length. An episode the release does not end has none.
    def take_out_returns(episode)
      @length = 0
      @b.repeat(@pack[:end_article_length][episode]) do |at|
        byte = @pack[:end_articles][(episode * ARTICLE_BYTES) + at]
        if byte != CARRIAGE_RETURN
          @buffer[@length] = byte
          @length += 1
        end
      end
      @b.repeat(READ_AHEAD) { |n| @buffer[@length + n] = 0 }
    end

    # PASS TWO: everything before the first ^E, with ^Cxx, ^cxx and ^Gn,n,n gone (EndArticle::COMMAND),
    # moved down the list in place; @length becomes what is kept.
    def cut_and_take_out_commands
      @read = 0
      @kept = 0
      @cut = false
      @b.repeat(ARTICLE_BYTES, stop_when: (@read >= @length) || @cut) do
        @skip = 0
        if @buffer[@read] == CARET
          if @buffer[@read + 1] == "E".ord
            @cut = true
          elsif ((@buffer[@read + 1] == "C".ord) || (@buffer[@read + 1] == "c".ord)) &&
                hex_digit?(@buffer[@read + 2]) && hex_digit?(@buffer[@read + 3])
            @skip = 4
          elsif @buffer[@read + 1] == "G".ord
            @skip = picture_command_length
          end
        end
        unless @cut
          if @skip > 0
            @read += @skip
          else
            @buffer[@kept] = @buffer[@read]
            @kept += 1
            @read += 1
          end
        end
      end
      @length = @kept
      @b.repeat(READ_AHEAD) { |n| @buffer[@length + n] = 0 }
    end

    # Whether +byte+ is a hex digit, as a regexp's \h takes one.
    def hex_digit?(byte)
      ((byte >= "0".ord) && (byte <= "9".ord)) || ((byte >= "a".ord) && (byte <= "f".ord)) ||
        ((byte >= "A".ord) && (byte <= "F".ord))
    end

    # How long the ^G command at @read is, three runs of digits between two commas; nought where
    # the bytes there are not one.
    def picture_command_length
      @command_at = @read + 2
      @part = 0
      @digits = 0
      @command_ended = false
      @b.repeat(PICTURE_COMMAND_BYTES, stop_when: @command_ended) do
        byte = @buffer[@command_at]
        if (byte >= "0".ord) && (byte <= "9".ord)
          @digits += 1
          @command_at += 1
        elsif (byte == COMMA) && (@digits > 0) && (@part < 2)
          @part += 1
          @digits = 0
          @command_at += 1
        else
          @command_ended = true
        end
      end
      length = 0
      length = @command_at - @read if (@part == 2) && (@digits > 0)
      length
    end

    # Whether the byte at +at+ separates words.
    def space?(at) = SPACES.map { |space| @buffer[at] == space }.reduce(:|)

    # Whether ^P starts at +at+.
    def page_break?(at) = (@buffer[at] == CARET) & (@buffer[at + 1] == "P".ord)

    # PASS THREE: the kept words into pages from @page on, which it leaves at the next page free.
    def lay_out
      @read = 0
      @line = 0
      @open = false
      @new_lines = 0
      @b.repeat(ARTICLE_BYTES, stop_when: @read >= @length) do
        if page_break?(@read)
          if @open
            @page += 1
            @line = 0
            @open = false
          end
          @new_lines = 0
          @read += 2
        elsif @buffer[@read] == NEW_LINE
          @new_lines += 1
          @read += 1
        elsif space?(@read)
          @read += 1
        else
          place_word
        end
      end
      @page += 1 if @open
    end

    # The word at @read, measured, then put on this line, a new one, or the first of a page.
    def place_word
      @word_end = @read
      @word_wide = 0
      @word_ended = false
      @b.repeat(ARTICLE_BYTES, stop_when: @word_ended) do
        if (@word_end >= @length) || space?(@word_end) || page_break?(@word_end)
          @word_ended = true
        else
          @word_wide += @widths[@buffer[@word_end]]
          @word_end += 1
        end
      end
      if !@open
        @open = true
        start_line
      elsif @new_lines > 0
        @line += @new_lines
        start_line
      elsif @wide + @widths[BLANK] + @word_wide > EpisodeEnd::TEXT_WIDTH
        @line += 1
        start_line
      else
        put(BLANK)
        @wide += @widths[BLANK]
      end
      @new_lines = 0
      @b.repeat(@word_end - @read) { |n| put(@buffer[@read + n]) }
      @wide += @word_wide
      @read = @word_end
    end

    # A line from its start, on the next page where this one is full.
    def start_line
      @page += @line / EpisodeEnd::LINES
      @line %= EpisodeEnd::LINES
      @column = 0
      @wide = 0
    end

    # +byte+ at the line's next column; nothing past its last, or past the last page.
    def put(byte)
      if (@page < PAGES) && (@column < EpisodeEnd::COLUMNS)
        @pack[:article_pages][(@page * self.class.page_bytes) + (@line * EpisodeEnd::COLUMNS) + @column] = byte
        @copy.count_written 1
      end
      @column += 1
    end
  end
end
