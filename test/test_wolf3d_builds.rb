# frozen_string_literal: true

require_relative "test_helper"

# The wiring: a game living outside the framework can require ruby-gba, build a program, run it
# on the interpreter, and lower it to a real cartridge. Everything after this assumes that works.
class TestWolf3DBuilds < Minitest::Test
  include Wolf3DTest

  # The console reads a cartridge's name out of a fixed place in the header, which is stamped
  # last — so reading it back also proves the build ran to completion. True whether or not a
  # copy of the game is here to build from.
  def test_the_game_lowers_to_a_valid_cartridge
    rom = a_small_cartridge
    stamped = rom.buffer[ROM::HEADER_TITLE, ROM::TITLE_LENGTH].delete("\x00")

    assert_predicate rom.size, :positive?
    assert_equal Wolf3D::TITLE, stamped
  end
end

# WHICH EPISODES THE CARTRIDGE HOLDS, said in episodes because that is how the game is divided
# and the only unit somebody building it thinks in. The whole game by default; trimmed when you
# are building over and over.
class TestWhichEpisodes < Minitest::Test
  include Wolf3DTest

  def asking(**dials) = Wolf3D.which_floors(**dials)

  # THE COMMAND LINE STILL SPEAKS IN WOLF3D_*, and those become the build's settings — only the
  # ones actually set, so a dial left empty takes the game's own default.
  def test_the_environment_dials_become_the_builds_settings
    env = { "WOLF3D_FLOORS" => "1", "WOLF3D_FROM" => "8", "WOLF3D_EPISODES" => "", "PATH" => "/bin" }

    assert_equal({ from: "8", floors: "1" }, Wolf3D.settings_from(env))
  end

  def test_it_ships_every_episode_the_copy_holds_unless_told_otherwise
    game_data_or_skip

    assert_equal Wolf3D.maps.count, asking.length, "the whole game is the default"
  end

  def test_one_episode_is_that_episodes_floors_and_no_others
    game_data_or_skip

    assert_equal (0..9).to_a, asking(episodes: "1")
    assert_equal (10..19).to_a, asking(episodes: "2")
  end

  def test_a_list_and_a_range_both_read
    game_data_or_skip

    assert_equal (0..9).to_a + (20..29).to_a, asking(episodes: "1,3")
    assert_equal (10..39).to_a, asking(episodes: "2-4")
    assert_equal (0..19).to_a + (50..59).to_a, asking(episodes: "1-2,6")
  end

  # ...and the floor dials still trim what the episodes picked, which is what makes the fastest
  # possible build and what measuring a LATER floor's cost needs.
  def test_the_floor_dials_trim_the_episodes_that_were_picked
    game_data_or_skip

    assert_equal [0], asking(floors: "1")
    assert_equal [10], asking(episodes: "2", floors: "1")
    assert_equal [1], asking(from: "1", floors: "1")
  end

  def test_an_episode_that_is_not_there_says_how_many_are
    game_data_or_skip
    error = assert_raises(ArgumentError) { asking(episodes: "7") }

    assert_match(/episode 7/, error.message)
    assert_match(/holds #{Wolf3D.maps.episodes}/, error.message)
    assert_match(/1 to #{Wolf3D.maps.episodes}/, error.message, "and how to say it properly")
  end

  def test_something_that_is_not_a_number_says_what_one_looks_like
    game_data_or_skip
    error = assert_raises(ArgumentError) { asking(episodes: "two") }

    assert_match(/cannot read "two"/, error.message)
    assert_match(/range like 2-4/, error.message)
  end
end

# The holding screen on its own, in a program of its own. It used to be tested through the whole
# game, which quietly stopped working the moment the game had data to draw instead.
class TestTitleScreen < Minitest::Test
  include Wolf3DTest

  def program
    RubyGBA.game("TITLE") do
      screen :bitmap
      screen_title = Wolf3D::Title.new(self)
      game_loop { screen_title.update }
    end.program
  end

  def test_it_draws_its_lettering
    run = Reference.new.run(program, frames: 2)

    lit = (0...240).sum { |x| (40...80).count { |y| run.screen.pixel(x, y) != run.screen.pixel(0, 0) } }
    assert_operator lit, :>, 100, "expected the title lettering to be drawn"
  end

  # A blinking prompt means the frame loop is running, not that the screen was painted once.
  def test_the_prompt_blinks
    interpreter = Reference.new
    early = prompt_pixels(interpreter.run(program, frames: 2))
    later = prompt_pixels(interpreter.run(program, frames: 70))

    assert_operator early, :>, 0, "expected the prompt to be showing early in the cycle"
    assert_equal 0, later, "expected the prompt to be dark later in the cycle"
  end

  private

  def prompt_pixels(run)
    background = run.screen.pixel(0, 0)
    (0...240).sum { |x| (100...112).count { |y| run.screen.pixel(x, y) != background } }
  end
end
