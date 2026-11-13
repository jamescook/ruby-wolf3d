# frozen_string_literal: true

module Wolf3D
  # WHAT COMES AFTER YOU HAVE WON: the screen that says so, with the time you took over the episode
  # and what you averaged (Victory, wl_inter.cpp), and then the article the episode ends on.
  class EpisodeEnd
    game_variables :page, :last_page, :base, :code, :kill, :secret, :treasure, :minutes, :seconds,
                   saved: false

    # The original's Write(18, 2, STR_YOUWIN) and the rest, cut for a screen eighty pixels narrower.
    YOU_WIN = "YOU WIN!"
    TOTAL_TIME = "TOTAL TIME"
    AVERAGES = "AVERAGES"
    RATIOS = %w[KILL SECRET TREASURE].freeze

    PRINTED = Ractor.make_shareable(([YOU_WIN, TOTAL_TIME, AVERAGES] + RATIOS).join.delete(" ").chars.uniq +
                                    (0..9).map(&:to_s) + ["%", ":"])

    LETTER = BigLettering::LETTER
    # The ground, the original's VIEWCOLOR, and where the rows go down it.
    GROUND = Tally::GROUND
    HEADING_Y = 4
    TIME_LABEL_Y = 28
    TIME_Y = 46
    AVERAGES_Y = 70
    RATIOS_Y = 90
    PERCENT_X = 200
    FIGURES_X = PERCENT_X - (3 * LETTER)
    GAP = 8
    TIME_X = 72

    MOST_MINUTES = 99 # past this the original shows 99:99

    # AN ARTICLE PAGE, with room for each line and every line kept in a table.
    TEXT_X = 12
    TEXT_Y = 8
    TEXT_WIDTH = 216
    LINES = 11
    LINE_STEP = 13
    COLUMNS = 40

    # +letters+ is the small alphabet, +lettering+ the big one, +records+ the floors of the episode.
    # +source+ is where the build's articles come from (Source).
    def initialize(build:, art:, letters:, lettering:, records:, floor:, floors:, source: Source::BAKED)
      @b = build
      @letters = letters
      @lettering = lettering
      @records = records
      @floor = floor
      @floors = floors
      @articles = source.article_pages(build, art: art, letters: letters, floors: floors)
      declare
    end

    # WORK OUT THE TIME AND THE AVERAGES, once, as the episode ends.
    def add_up_the_episode = @b.call(:add_up_the_episode)
    def draw_summary = @summary.draw
    def draw_page = @page_picture.draw

    # GO TO THE FIRST PAGE OF THE ARTICLE of the episode being played. A copy with no article has none.
    def open_article
      @page = @first_page[@episode_of[@floor]]
      @last_page = @first_page[@episode_of[@floor] + 1]
      @page_picture.changed
    end

    def article_open = @page < @last_page

    # Turn the page.
    def turn_page
      @page += 1
      @page_picture.changed if article_open
    end

    private

    def declare
      b = @b
      @kill = 0
      @secret = 0
      @treasure = 0
      @minutes = 0
      @seconds = 0
      @page = 0
      @last_page = 0
      @base = 0
      @code = 0
      declare_articles
      @episode_of = b.table :article_episode, @floors.map { |f| f.index / Floors::PER_EPISODE }, width: :byte
      @summary = b.keep_showing(:episode_summary) { paint_summary }
      @page_picture = b.keep_showing(:article_page) { paint_page }
      b.func(:add_up_the_episode, fast: false) { add_up }
    end

    # EVERY ARTICLE'S PAGES, LINES rows of COLUMNS bytes each, and where each episode's start.
    def declare_articles
      tables = @articles.declare
      @first_page = tables.first_page
      @text = tables.text
    end

    # The original's sums and divides by eight whatever you played, and its clock stops at 99:99.
    def add_up
      @kill = 0
      @secret = 0
      @treasure = 0
      @seconds = 0
      @b.repeat(FloorRecords::FLOORS) do |n|
        @kill += @records.kills[n]
        @secret += @records.secrets[n]
        @treasure += @records.treasures[n]
        @seconds += @records.seconds[n]
      end
      @kill = @kill / FloorRecords::FLOORS
      @secret = @secret / FloorRecords::FLOORS
      @treasure = @treasure / FloorRecords::FLOORS
      @minutes = @seconds / 60
      @seconds = @seconds % 60
      if @minutes > MOST_MINUTES
        @minutes = MOST_MINUTES
        @seconds = MOST_MINUTES
      end
      @summary.changed
    end

    def paint_summary
      @b.clear_screen colour
      @b.blit :menu_bj_wins, 8, 4
      @lettering.write YOU_WIN, ACROSS_FOR_HEADING, HEADING_Y
      @lettering.write TOTAL_TIME, ACROSS_FOR_HEADING - 24, TIME_LABEL_Y
      @lettering.draw_clock @minutes, @seconds, TIME_X, TIME_Y
      @lettering.write AVERAGES, @lettering.centred(AVERAGES), AVERAGES_Y
      draw_ratio(RATIOS[0], @kill, RATIOS_Y)
      draw_ratio(RATIOS[1], @secret, RATIOS_Y + LETTER)
      draw_ratio(RATIOS[2], @treasure, RATIOS_Y + (2 * LETTER))
    end

    ACROSS_FOR_HEADING = 80

    def draw_ratio(label, value, y)
      @lettering.write label, FIGURES_X - GAP - @lettering.width_of(label), y
      @lettering.draw_a_figure value, FIGURES_X, y, digits: 3
      @lettering.write "%", PERCENT_X, y
    end

    def paint_page
      @b.clear_screen Palette.game[Menus::BACKGROUND]
      @base = @page * LINES * COLUMNS
      @b.repeat(LINES) do |line|
        @letters.start_at(TEXT_X, TEXT_Y + (line * LINE_STEP))
        @b.repeat(COLUMNS) do |n|
          @code = @text[@base + (line * COLUMNS) + n]
          @letters.draw(@code) if @code > 0
        end
      end
    end

    def colour = Palette.game[GROUND]
  end
end
