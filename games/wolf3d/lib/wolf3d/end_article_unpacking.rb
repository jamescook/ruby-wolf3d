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
  # branch in it, and every count is a variable of the routine's (#routine_var).
  class EndArticleUnpacking
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
      slots.numbers :article_pages, count: PAGES * page_bytes, width: :byte, signed: false, layout: :gba
      slots.numbers :article_first_page, count: ARTICLES + 1, width: :byte, signed: false, layout: :gba
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
      page = routine_var(:page)
      page.store!(0)
      @pack[:article_first_page][0] = 0
      @b.repeat(ARTICLES) do |episode|
        take_out_returns(episode)
        cut_and_take_out_commands
        lay_out
        page.store!(PAGES) if page > PAGES
        @pack[:article_first_page][episode + 1] = page
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
    # :length. An episode the release does not end has none.
    def take_out_returns(episode)
      length = routine_var(:length)
      length.store!(0)
      held = routine_var(:held)
      held.store!(@pack[:end_article_length][episode])
      @b.repeat(held) do |at|
        byte = routine_var(:byte)
        byte.store!(@pack[:end_articles][(episode * ARTICLE_BYTES) + at])
        if byte != CARRIAGE_RETURN
          @buffer[length] = byte
          length.increase!(1)
        end
      end
      @b.repeat(READ_AHEAD) { |n| @buffer[length + n] = 0 }
    end

    # PASS TWO: everything before the first ^E, with ^Cxx, ^cxx and ^Gn,n,n gone (EndArticle::COMMAND),
    # moved down the list in place; :length becomes what is kept.
    def cut_and_take_out_commands
      length = routine_var(:length)
      read = routine_var(:read)
      kept = routine_var(:kept)
      cut = routine_var(:cut)
      skip = routine_var(:skip)
      read.store!(0)
      kept.store!(0)
      cut.store!(0)
      @b.repeat(ARTICLE_BYTES, stop_when: (read >= length) | (cut == 1)) do
        skip.store!(0)
        hexes = routine_var(:hexes)
        hexes.store!(hex?(@buffer[read + 2]))
        hexes.increase!(hex?(@buffer[read + 3]))
        if @buffer[read] == CARET
          if @buffer[read + 1] == "E".ord
            cut.store!(1)
          elsif ((@buffer[read + 1] == "C".ord) | (@buffer[read + 1] == "c".ord)) & (hexes == 2)
            skip.store!(4)
          elsif @buffer[read + 1] == "G".ord
            skip.store!(picture_command_bytes)
          end
        end
        if cut == 0
          if skip > 0
            read.increase!(skip)
          else
            @buffer[kept] = @buffer[read]
            kept.increase!(1)
            read.increase!(1)
          end
        end
      end
      length.store!(kept)
      @b.repeat(READ_AHEAD) { |n| @buffer[length + n] = 0 }
    end

    # 1 where +byte+ is a hex digit, as a regexp's \h takes one.
    def hex?(byte)
      found = routine_var(:hex)
      found.store!(0)
      found.store!(1) if ((byte >= "0".ord) & (byte <= "9".ord)) | ((byte >= "a".ord) & (byte <= "f".ord)) |
                         ((byte >= "A".ord) & (byte <= "F".ord))
      found
    end

    # How long the ^G command at :read is, three runs of digits between two commas; nought where
    # the bytes there are not one.
    def picture_command_bytes
      at = routine_var(:command_at)
      part = routine_var(:part)
      digits = routine_var(:digits)
      done = routine_var(:done)
      bytes = routine_var(:command_bytes)
      at.store!(routine_var(:read) + 2)
      part.store!(0)
      digits.store!(0)
      done.store!(0)
      @b.repeat(PICTURE_COMMAND_BYTES, stop_when: done == 1) do
        byte = routine_var(:command_byte)
        byte.store!(@buffer[at])
        if (byte >= "0".ord) & (byte <= "9".ord)
          digits.increase!(1)
          at.increase!(1)
        elsif (byte == COMMA) & (digits > 0) & (part < 2)
          part.increase!(1)
          digits.store!(0)
          at.increase!(1)
        else
          done.store!(1)
        end
      end
      bytes.store!(0)
      bytes.store!(at - routine_var(:read)) if (part == 2) & (digits > 0)
      bytes
    end

    # 1 where the byte at +at+ separates words.
    def space?(at)
      found = routine_var(:space)
      found.store!(0)
      SPACES.each { |space| found.store!(1) if @buffer[at] == space }
      found
    end

    # 1 where ^P starts at +at+.
    def page_break?(at)
      found = routine_var(:page_break)
      found.store!(0)
      found.store!(1) if (@buffer[at] == CARET) & (@buffer[at + 1] == "P".ord)
      found
    end

    # PASS THREE: the kept words into pages from :page on, which it leaves at the next page free.
    def lay_out
      length = routine_var(:length)
      read = routine_var(:read)
      page = routine_var(:page)
      line = routine_var(:line)
      open = routine_var(:open)
      new_lines = routine_var(:new_lines)
      read.store!(0)
      line.store!(0)
      open.store!(0)
      new_lines.store!(0)
      @b.repeat(ARTICLE_BYTES, stop_when: read >= length) do
        breaks = routine_var(:breaks)
        spaced = routine_var(:spaced)
        breaks.store!(page_break?(read))
        spaced.store!(space?(read))
        if breaks == 1
          if open == 1
            page.increase!(1)
            line.store!(0)
            open.store!(0)
          end
          new_lines.store!(0)
          read.increase!(2)
        elsif @buffer[read] == NEW_LINE
          new_lines.increase!(1)
          read.increase!(1)
        elsif spaced == 1
          read.increase!(1)
        else
          place_word
        end
      end
      page.increase!(1) if open == 1
    end

    # The word at :read, measured, then put on this line, a new one, or the first of a page.
    def place_word
      read = routine_var(:read)
      line = routine_var(:line)
      wide = routine_var(:wide)
      open = routine_var(:open)
      new_lines = routine_var(:new_lines)
      ends = routine_var(:word_end)
      word_wide = routine_var(:word_wide)
      ended = routine_var(:ended)
      ends.store!(read)
      word_wide.store!(0)
      ended.store!(0)
      @b.repeat(ARTICLE_BYTES, stop_when: ended == 1) do
        stops = routine_var(:stops)
        stops.store!(space?(ends))
        stops.increase!(page_break?(ends))
        if (ends >= routine_var(:length)) | (stops > 0)
          ended.store!(1)
        else
          word_wide.increase!(@widths[@buffer[ends]])
          ends.increase!(1)
        end
      end
      if open == 0
        open.store!(1)
        start_line
      elsif new_lines > 0
        line.increase!(new_lines)
        start_line
      elsif wide + @widths[BLANK] + word_wide > EpisodeEnd::TEXT_WIDTH
        line.increase!(1)
        start_line
      else
        put(BLANK)
        wide.increase!(@widths[BLANK])
      end
      new_lines.store!(0)
      @b.repeat(ends - read) { |n| put(@buffer[read + n]) }
      wide.increase!(word_wide)
      read.store!(ends)
    end

    # A line from its start, on the next page where this one is full.
    def start_line
      page = routine_var(:page)
      line = routine_var(:line)
      page.increase!(line / EpisodeEnd::LINES)
      line.store!(line % EpisodeEnd::LINES)
      routine_var(:column).store!(0)
      routine_var(:wide).store!(0)
    end

    # +byte+ at the line's next column; nothing past its last, or past the last page.
    def put(byte)
      page = routine_var(:page)
      column = routine_var(:column)
      if (page < PAGES) & (column < EpisodeEnd::COLUMNS)
        @pack[:article_pages][(page * self.class.page_bytes) + (routine_var(:line) * EpisodeEnd::COLUMNS) + column] = byte
        @copy.count_written 1
      end
      column.increase!(1)
    end

    # A variable of the routine's, made the first time it is asked for.
    def routine_var(name) = (@routine_vars ||= {})[name] ||= @b.var(:"_end_article_unpacking_#{name}", 0)
  end
end
