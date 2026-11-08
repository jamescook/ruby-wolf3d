# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# WHICH COPIES THE BUILD ACCEPTS: the two releases Vanilla lists, known by their files' SHA-1.
# Everything here is what a person pointing the build at the wrong folder would read, so it is the
# message that is held to account.
class TestVanilla < Minitest::Test
  include Wolf3DTest

  Vanilla = Wolf3D::Vanilla
  GameData = Wolf3D::GameData
  WrongCopy = VBlank::Original::WrongCopy

  def test_a_real_copy_of_the_six_episodes_is_accepted
    assert_equal "WL6", GameData.locate.set
  end

  def test_a_real_copy_of_the_shareware_is_accepted
    assert_equal "WL1", real_shareware.set
  end

  # Every file the build reads is one the shell checks, so the two never disagree about a copy.
  def test_each_release_lists_every_file_the_build_reads
    Vanilla::RELEASES.each do |set, release|
      assert_equal GameData::STEMS.map { |stem| "#{stem}.#{set}" }.sort, release.fetch("files").keys.sort, set
    end
  end

  # A COPY WITH ONE FILE CHANGED IS REFUSED NAMING THAT FILE. The made-up release has every name
  # right and no byte right, so the first file is the one named.
  def test_a_changed_copy_is_refused_naming_a_file
    in_a_copy_of_the_made_up_release do |dir|
      error = assert_raises(WrongCopy) { GameData.locate(home: dir, env: env(dir)) }

      assert_includes error.message, File.join(dir, "VSWAP.WL6")
    end
  end

  def test_a_file_cut_short_is_refused_naming_it
    in_a_copy_of_the_made_up_release do |dir|
      File.truncate(File.join(dir, "VSWAP.WL6"), 3)

      assert_includes assert_raises(WrongCopy) { GameData.locate(home: dir, env: env(dir)) }.message, "VSWAP.WL6"
    end
  end

  # A Spear of Destiny folder holds none of the files, so it is told which ones a copy must have.
  def test_a_folder_of_spear_is_told_what_a_copy_holds
    in_a_copy_of_the_made_up_release("SOD") do |dir|
      error = assert_raises(WrongCopy) { GameData.locate(home: dir, env: env(dir)) }

      assert_includes error.message, "VSWAP.WL6"
      assert_includes error.message, "VSWAP.WL1"
    end
  end

  def test_a_folder_missing_a_file_is_refused_naming_it
    in_a_copy_of_the_made_up_release do |dir|
      File.delete(File.join(dir, "AUDIOHED.WL6"))

      assert_includes assert_raises(WrongCopy) { GameData.locate(home: dir, env: env(dir)) }.message, "AUDIOHED.WL6"
    end
  end

  # NOTHING NAMED AT ALL DOES NOT STOP A BUILD: that is what makes the holding screen.
  def test_saying_nothing_about_a_copy_does_not_stop_a_build
    Dir.mktmpdir { |home| assert_nil GameData.locate_if_set(home: home, env: {}) }
  end

  private

  def in_a_copy_of_the_made_up_release(set = "WL6")
    Dir.mktmpdir do |dir|
      Wolf3D::Fixture::Release.new(set: set).write(dir)
      yield dir
    end
  end

  def env(dir) = { GameData::ENV_VAR => dir }
end
