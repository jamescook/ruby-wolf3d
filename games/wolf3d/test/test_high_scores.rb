# frozen_string_literal: true

require_relative "test_helper"

# THE SEVEN BEST GAMES, read out of DrawHighScores and CheckHighScore (wl_inter.cpp) and the table the
# original ships with (id_us_1.cpp). The game is ended by a guard ring, and the score set by a dial
# would be nothing a player does, so the table's own rule is read through a finished game.
class TestHighScores < Minitest::Test
  include Wolf3DTest

  Menus = Wolf3D::Menus
  Scores = Wolf3D::HighScores
  Release = Wolf3D::Fixture::Release

  OPEN_MENU = 2
  WALKED_OUT_BY = 40
  NAMING_BY = WALKED_OUT_BY + 40
  VIEW_ROW_DOWNS = [6, 10, 14].freeze # Load, Sound (over the dim Save), View Scores
  PICK = 20

  def test_a_new_cartridge_has_the_originals_seven_names
    run = viewing_scores

    assert_equal Menus::SCORES, run[:menus_screen]
    assert_equal [Scores::STARTING_SCORE] * Scores::ROWS, run.list(:high_score_points)
    assert_equal "id software-'92", name_in(run, 0)
    assert_equal "Jay Wilbur", name_in(run, 6)
  end

  # The attract loop has three still screens, and the third is this (wl_main.cpp, DemoLoop).
  def test_the_table_follows_the_credits_in_the_attract_loop
    frames = Menus::NOTICE_FRAMES + Menus::TITLE_FRAMES + Menus::CREDITS_FRAMES + 1
    assert_equal Menus::SCORES, Reference.new.run(cartridge, frames: frames)[:menus_screen]

    assert_equal Menus::TITLE, Reference.new.run(cartridge, frames: frames + Menus::SCORES_FRAMES)[:menus_screen]
  end

  def test_from_the_menu_it_waits_for_a_press
    assert_equal Menus::SCORES, viewing_scores(frames: PICK + Menus::SCORES_FRAMES + 60)[:menus_screen]
    run = viewing_scores(frames: PICK + 100) { |f| f == PICK + 90 ? [:a] : [] }

    assert_equal Menus::MENU, run[:menus_screen]
  end

  # A SCORE UNDER THE LOWEST ROW GOES STRAIGHT TO THE TABLE AND ASKS NOTHING.
  def test_a_low_score_earns_no_row
    run = ended_game(frames: NAMING_BY, score: 5_000)

    assert_equal Menus::SCORES, run[:menus_screen]
    assert_equal [10_000] * Scores::ROWS, run.list(:high_score_points)
  end

  # A SCORE THAT BEATS A ROW GOES IN ABOVE IT and the rest move down, the last falling off.
  def test_a_high_score_takes_its_row
    run = named_game(frames: NAMING_BY)

    assert_equal Menus::NAMING, run[:menus_screen]
    assert_equal 1, run[:high_scores_new_row]
    assert_equal [30_000, 12_000, 10_000, 10_000, 10_000, 10_000, 10_000], run.list(:high_score_points)
    assert_equal "", name_in(run, 1), "with an empty name to fill"
    assert_equal "Adrian Carmack", name_in(run, 2), "and the row it took moved down"
  end

  def test_a_name_is_picked_with_the_pad
    run = named_game(frames: NAMING_BY + 20) do |f|
      { NAMING_BY => [:up], NAMING_BY + 4 => [:right], NAMING_BY + 8 => [:up], NAMING_BY + 16 => [:up] }.fetch(f, [])
    end

    assert_equal "AB", name_in(run, 1)
  end

  # THE TABLE OUTLIVES THE POWER, and a score does nothing to it until the name is done.
  def test_the_table_survives_the_power_going_off
    image = SaveImage.new
    finished = named_game(frames: NAMING_BY + 30, image: image) do |f|
      { NAMING_BY => [:up], NAMING_BY + 10 => [:a] }.fetch(f, [])
    end

    assert_equal Menus::SCORES, finished[:menus_screen]
    run = viewing_scores(frames: 140, image: image)

    assert_equal 12_000, run.list(:high_score_points)[1]
    assert_equal "A", name_in(run, 1)
  end

  # A PICKED LETTER REACHES THE SCREEN, drawn at run time. The fixture's alphabet holds an I, which
  # is nine presses up from a blank.
  def test_a_picked_letter_is_drawn_on_its_row
    run = named_game(frames: NAMING_BY + 44) { |f| (f - NAMING_BY).between?(0, 35) && (f - NAMING_BY) % 4 == 0 ? [:up] : [] }
    y = Scores::TOP_ROW + Scores::ROW_STEP
    ink = (Scores::NAME_X...(Scores::NAME_X + 8)).count { |x| run.screen.pixel(x, y) == palette[Scores::INK] }

    assert_equal "I", name_in(run, 1)
    assert_operator ink, :>, 0, "its pixels are on the row it earned"
  end

  # THE SAME SAVE MEMORY ON THE CONSOLE, which starts up reading the table out of it.
  def test_the_console_reads_the_table_back
    image = table_in(SaveImage.new, cartridge(:scores), last_score: 23_456)
    backend = GBA.new
    rom = ROM.assemble(backend.lower(cartridge(:scores)), title: "SCORES")
    console = Verifier.new(rom, frames: 20, vars: backend.var_addresses, save: image)

    assert_equal Menus::SCORES, console.var(:menus_screen)
    # Read over several frames, because a picture is drawn across a frame and this may catch it part way.
    figures = Array.new(12) do
      console.step
      console.var(:high_scores_number)
    end

    assert_includes figures, 23_456, "a figure the screen drew"
  end

  private

  def name_in(run, row)
    run.list(:high_score_names).each_slice(Scores::NAME_ROOM).to_a[row].map(&:chr).join.rstrip
  end

  def viewing_scores(frames: PICK + 40, image: SaveImage.new)
    presses = lambda do |f|
      next [:a] if [OPEN_MENU, PICK].include?(f)
      next [:down] if VIEW_ROW_DOWNS.include?(f)

      block_given? ? yield(f) : []
    end
    Reference.new(save: image).input_each_frame(&presses).run(cartridge, frames: frames)
  end

  # WALK BACK ONTO THE WAY OUT, which is right behind you, and press START on the game it ends.
  def ended_game(frames:, score:, image: SaveImage.new)
    presses = lambda do |f|
      next [:down] if f < WALKED_OUT_BY
      next [:start] if f == WALKED_OUT_BY + 4

      block_given? ? yield(f) : []
    end
    Reference.new(save: image).input_each_frame(&presses).run(cartridge(:ended, score: score), frames: frames)
  end

  def named_game(frames:, image: SaveImage.new, &)
    table_in(image, cartridge(:ended, score: 12_000), last_score: 10_000)
    ended_game(frames: frames, score: 12_000, image: image, &)
  end

  # A table with thirty thousand at the top and +last_score+ at the bottom.
  def table_in(image, program, last_score:)
    Reference.save_into(image, program, :high_scores, 0,
                        high_score_points: [30_000] + ([10_000] * 5) + [last_score],
                        high_score_floor: [1] * Scores::ROWS, high_score_episode: [1] * Scores::ROWS,
                        high_score_names: Scores::STARTING_NAMES.flat_map { |name| name.ljust(Scores::NAME_ROOM).bytes })
  end

  def fixture = @fixture ||= Release.new(set: "WL6", walls: (Wolf3D::Elevator::PULLED * 2) + 2)

  # +:ended+ boots into the game with the score given, a step from the way out.
  def cartridge(way = :boot, score: 0)
    Ractor.current[:"high_scores_#{way}_#{score}"] ||= begin
      art = Wolf3D::MenuArt.of(fixture.pictures)
      screen = { boot: Menus::NOTICE, ended: Menus::PLAYING, scores: Menus::SCORES }.fetch(way)
      view_of(way_out_level, sound: 1) do |b, view, sound_setting|
        menus = Menus.new(build: b, view: view, art: art, palette: Wolf3D::Palette.game, sound_setting: sound_setting,
                          starting_on: screen)
        once = b.var :_test_ended, 0
        b.game_loop do
          if way == :ended && once == 0
            view.player.score = score
            once = 1
          end
          menus.update
        end
      end
    end
  end
end
