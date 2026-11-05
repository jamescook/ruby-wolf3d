# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# FINDING YOUR COPY. Where the settings point and how a missing or wrong path is put in words is the
# framework's (VBlank::Original::Game), and tested there; what is this game's is what a folder of
# Wolfenstein holds, which release that is, and which line of wolf3d.yml names it.
#
# The folders here hold made-up bytes, which the build refuses, so a test of where the settings
# point reads the folder the refusal names.
class TestGameData < Minitest::Test
  include Wolf3DTest

  Data = Wolf3D::GameData
  WrongCopy = VBlank::Original::WrongCopy

  def test_it_finds_a_complete_set_and_says_which_release_it_is
    with_release("WL6") do |dir|
      data = Data.at(dir)

      assert_equal "WL6", data.set
      assert_includes data.label, "registered"
      assert_includes data.describe, dir
    end
  end

  # The files are upper-case on the original disks and often lower-case after a copy through
  # another system, so neither can be assumed.
  def test_it_finds_files_whatever_case_they_are_in
    with_release("WL1", downcase: true) do |dir|
      data = Data.at(dir)

      assert_equal "WL1", data.set
      assert_equal "raw vswap", File.binread(data.path("VSWAP"))
    end
  end

  # The operator's own copy has spaces in its path, and so do most GOG installs.
  def test_it_handles_a_folder_whose_name_has_spaces
    Dir.mktmpdir do |tmp|
      dir = File.join(tmp, "GOG Games", "Wolfenstein 3D")
      write_release(dir, "WL6")

      assert_equal "WL6", Data.at(dir).set
    end
  end

  # Spear of Destiny ships inside the Wolfenstein folder. Reading flat rather than searching
  # downward is what keeps that from being read as two releases in one place.
  def test_a_release_in_a_sub_folder_is_not_mixed_into_its_parent
    Dir.mktmpdir do |tmp|
      write_release(tmp, "WL6")
      write_release(File.join(tmp, "m1"), "SOD")

      assert_equal "WL6", Data.at(tmp).set
      assert_equal "SOD", Data.at(File.join(tmp, "m1")).set
    end
  end

  def test_an_incomplete_set_is_not_a_release
    with_release("WL6") do |dir|
      File.delete(File.join(dir, "MAPHEAD.WL6"))

      error = assert_raises(WrongCopy) { Data.at(dir) }
      assert_includes error.message, "MAPHEAD"
    end
  end

  def test_two_releases_in_one_folder_asks_which
    Dir.mktmpdir do |dir|
      write_release(dir, "WL6")
      write_release(dir, "WL1")

      error = assert_raises(WrongCopy) { Data.at(dir) }
      assert_includes error.message, "WL6"
      assert_includes error.message, "WL1"
    end
  end

  # THE COPY IS ASKED OF THE FOLDER THE SETTINGS NAME: the environment over the file, and a path in
  # the file read from the game's folder.
  def test_the_environment_wins_over_the_config_file
    with_release("WL6") do |env_dir|
      with_release("WL1") do |config_dir|
        File.write(File.join(config_dir, Data::CONFIG_FILE), { "data" => config_dir }.to_yaml)

        assert_refused_naming(env_dir) { Data.locate(home: config_dir, env: env(env_dir)) }
        assert_refused_naming(config_dir) { Data.locate(home: config_dir, env: {}) }
      end
    end
  end

  def test_a_config_file_path_is_read_relative_to_the_game
    with_release("WL1", into: "beside") do |dir|
      home = File.expand_path("..", dir)
      File.write(File.join(home, Data::CONFIG_FILE), { "data" => "beside" }.to_yaml)

      assert_refused_naming(dir) { Data.locate(home: home, env: {}) }
    end
  end

  # TWO COPIES SIDE BY SIDE: the data line is the one a build reads unless told, and WOLF3D_COPY
  # picks the other.
  def test_the_shareware_line_is_picked_by_name
    with_release("WL6") do |full|
      with_release("WL1") do |shareware|
        Dir.mktmpdir do |home|
          File.write(File.join(home, Data::CONFIG_FILE), "data: #{full}\nshareware: #{shareware}\n")

          assert_refused_naming(full) { Data.locate(home: home, env: {}) }
          assert_refused_naming(shareware) { Data.locate(home: home, env: { Data::COPY_VAR => "shareware" }) }
        end
      end
    end
  end

  def test_a_copy_nobody_named_is_a_friendly_error
    Dir.mktmpdir do |home|
      error = assert_raises(WrongCopy) { Data.locate(home: home, env: { Data::COPY_VAR => "spear" }) }

      assert_includes error.message, "shareware"
    end
  end

  # NOTHING NAMED AT ALL is the one case a build carries on from, to the holding screen; the message
  # says both ways to name a copy, and what the folder must hold.
  def test_saying_nothing_at_all_explains_both_ways_to_say_it
    Dir.mktmpdir do |home|
      error = assert_raises(VBlank::Original::NotSet) { Data.locate(home: home, env: {}) }

      assert_includes error.message, "WOLF3D_DATA"
      assert_includes error.message, Data::CONFIG_FILE
      assert_includes error.message, "VSWAP"
      assert_includes error.message, "WL6"
      assert_includes error.message, "WL1", "the free copy is one way to start, so it says so"
      assert_nil Data.locate_if_set(home: home, env: {})
    end
  end

  # The message tells you to copy a file, beside the one it reads, so that file has to be there.
  def test_the_example_config_it_tells_you_to_copy_is_really_there
    Dir.mktmpdir do |home|
      FileUtils.cp(File.join(Wolf3D.home, "wolf3d.example.yml"), home)

      error = assert_raises(VBlank::Original::NotSet) { Data.locate(home: home, env: {}) }
      assert_includes error.message, File.join(home, "wolf3d.example.yml")
    end
  end

  # A config that only makes sense if the example it is copied from parses and names the key
  # the loader reads.
  def test_the_example_config_parses_and_uses_the_key_the_loader_reads
    example = YAML.safe_load_file(File.join(Wolf3D.home, "wolf3d.example.yml"))

    assert_kind_of Hash, example
    refute_nil example["data"]
  end

  def test_a_path_that_is_not_there_says_so_and_names_where_it_came_from
    Dir.mktmpdir do |home|
      missing = File.join(home, "nowhere")

      error = assert_raises(WrongCopy) { Data.locate(home: home, env: env(missing)) }
      assert_includes error.message, missing
      assert_includes error.message, "WOLF3D_DATA"
    end
  end

  private

  # The build refused the folder it was pointed at, and said which.
  def assert_refused_naming(dir, &)
    error = assert_raises(WrongCopy, &)

    assert_includes error.message, dir
  end

  def with_release(set, downcase: false, into: nil)
    Dir.mktmpdir do |tmp|
      dir = into ? File.join(tmp, into) : tmp
      write_release(dir, set, downcase: downcase)
      yield dir
    end
  end

  def write_release(dir, set, downcase: false)
    FileUtils.mkdir_p(dir)
    Data::STEMS.each do |stem|
      name = "#{stem}.#{set}"
      File.binwrite(File.join(dir, downcase ? name.downcase : name), "raw #{stem.downcase}")
    end
  end

  # An environment of this test's own that points at +dir+. The real one belongs to every test
  # running at the same time, so it is never changed here.
  def env(dir) = { Data::ENV_VAR => dir }
end
