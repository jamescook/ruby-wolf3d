# frozen_string_literal: true

require_relative "test_helper"

# AFTER AN EPISODE IS WON: the summary, read out of Victory (wl_inter.cpp), and the article it ends on,
# read out of EndText and the commands PageLayout obeys (wl_text.cpp).
class TestEpisodeEnd < Minitest::Test
  include Wolf3DTest

  Menus = Wolf3D::Menus
  Article = Wolf3D::EndArticle
  Records = Wolf3D::FloorRecords
  Release = Wolf3D::Fixture::Release

  WON_BY = 20
  ON_THE_SUMMARY = WON_BY + 30

  SAMPLE = "^P\r\n^G16,16,5\r\n^C7eCONGRATULATIONS!\r\n^C00\r\nYou run out of the castle.\r\n^P\r\n^c7eMORE\r\n^c00\r\nAnd in episode three.\r\n^E"
  EVEN = ->(_) { 6 }

  def test_an_article_has_its_two_pages_with_the_commands_gone
    pages = Article.pages(SAMPLE, width: 216, lines: 11, &EVEN)

    assert_equal 2, pages.length
    assert_includes pages[0], "CONGRATULATIONS!"
    assert_includes pages[1], "And in episode three."
    refute pages.flatten.any? { |line| line.include?("^") }, "no command reaches the page"
  end

  def test_a_long_line_wraps_a_word_at_a_time
    pages = Article.pages("^P\nabcd abcd abcd\n^E", width: 60, lines: 11, &EVEN)

    assert_equal ["abcd abcd", "abcd"], pages[0]
  end

  def test_a_page_too_long_for_the_screen_goes_on_to_another
    pages = Article.pages("^P\none\ntwo\nthree\n^E", width: 216, lines: 2, &EVEN)

    assert_equal [%w[one two], %w[three]], pages
  end

  def test_nothing_at_all_is_no_pages
    assert_empty Article.pages("", width: 216, lines: 11, &EVEN)
  end

  # THE AVERAGES ARE OVER ALL EIGHT FLOORS, whichever you played (LRpack). Eighty per cent on one floor
  # and nothing on seven is ten.
  def test_winning_puts_up_the_sum_of_the_episode
    run = won(ON_THE_SUMMARY)

    assert_equal Menus::WINNING, run[:screen]
    assert_equal [10, 5, 2], [run[:_end_kill], run[:_end_secret], run[:_end_treasure]]
    assert_equal [1, 5], [run[:_end_minutes], run[:_end_seconds]]
  end

  # A COPY WITH NO ARTICLE, which is what the fixture is, goes on to the table.
  def test_a_press_goes_on_to_the_high_scores
    run = won(ON_THE_SUMMARY + 40) { |f| f == ON_THE_SUMMARY + 2 ? [:a] : [] }

    assert_includes [Menus::SCORES, Menus::NAMING], run[:screen]
  end

  def test_a_new_game_forgets_the_last_ones_floors
    assert_equal [0] * Records::FLOORS, Reference.new.run(cartridge(:new_game), frames: 6).list(:floor_kill_ratio)
  end

  private

  def won(frames)
    Reference.new.input_each_frame { |f| f < WON_BY ? [:down] : (block_given? ? yield(f) : []) }
             .run(cartridge(:wins), frames: frames)
  end

  def fixture = @fixture ||= Release.new(set: "WL6", walls: (Wolf3D::Elevator::PULLED * 2) + 2)

  def cartridge(way)
    Ractor.current[:"episode_end_#{way}"] ||= begin
      art = Wolf3D::MenuArt.of(fixture.pictures)
      view_of(way_out_level, sound: 1) do |b, view, sound_on|
        menus = Menus.new(build: b, view: view, art: art, palette: Wolf3D::Palette.game, sound_on: sound_on,
                          starting_on: Menus::PLAYING)
        once = b.var :_test_once, 0
        b.game_loop do
          if once == 0
            once = 1
            if way == :wins
              b.call :test_filled_records
            else
              view.records.record(0, kill: 80, secret: 40, treasure: 16)
              view.records.start_again
            end
          end
          menus.update
        end
        b.func(:test_filled_records) do
          view.records.record(0, kill: 80, secret: 40, treasure: 16)
          view.records.seconds[0] = 65
        end
      end
    end
  end
end
