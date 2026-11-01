# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# WHICH COPIES THE BUILD ACCEPTS. Everything here is what a person pointing the build at the wrong
# folder would read, so it is the message that is held to account.
#
# The numbers are read off a real copy of the six-episode release, version 1.4, and written out
# rather than taken from the code, so that a change to the check has something to disagree with.
class TestVanilla < Minitest::Test
  include Wolf3DTest

  Vanilla = Wolf3D::Vanilla
  Refused = Wolf3D::Vanilla::Refused

  Maps = Struct.new(:count)
  Vswap = Struct.new(:wall_count, :sprite_count, :sound_count)
  Graph = Struct.new(:picture_count, :sizes) do
    def size(name) = sizes.fetch(name)
  end

  SIZES = { status_bar: [320, 40], face_1a: [24, 32], digit_0: [8, 16] }.freeze

  def test_a_real_copy_of_the_six_episodes_is_accepted
    game_data_or_skip

    assert_nil Vanilla.check!(set: Wolf3D.data.set, dir: "here", maps: Wolf3D.maps, vswap: Wolf3D.vswap,
                              vgagraph: Wolf3D.vgagraph)
  end

  def test_a_copy_with_the_six_episodes_numbers_is_accepted
    assert_nil check(copy)
  end

  def test_spear_of_destiny_is_refused_by_name
    error = assert_raises(Refused) { check(copy(set: "SOD")) }

    assert_includes error.message, "Spear of Destiny"
    assert_includes error.message, "WL6"
    assert_includes error.message, "/the/copy"
  end

  def test_the_spear_demo_is_refused_by_name
    assert_includes assert_raises(Refused) { check(copy(set: "SDM")) }.message, "Spear of Destiny demo"
  end

  # The numbers are read off wolf3dsw, the shareware at version 1.4.
  def test_a_copy_with_the_shareware_numbers_is_accepted
    assert_nil check(copy(set: "WL1", floors: 10, pictures: 144))
  end

  # A copy is held to its OWN release: sixty floors in a shareware's files is a changed copy.
  def test_a_shareware_copy_is_held_to_the_shareware_numbers
    { { floors: 60 } => /WL1 files.*the number of floors must be 10.*it is 60/m,
      { pictures: 132 } => /the number of pictures must be 144.*it is 132/m }.each do |changes, says|
      error = assert_raises(Refused, changes.to_s) { check(copy(**{ set: "WL1", floors: 10, pictures: 144 }.merge(changes))) }

      assert_match says, error.message
    end
  end

  # Both releases are named, so a person holding the wrong folder knows what either will do.
  def test_a_refusal_names_both_releases
    message = assert_raises(Refused) { check(copy(set: "SOD")) }.message

    assert_includes message, "WL6"
    assert_includes message, "WL1"
    assert_includes message, "free download"
  end

  # A CHANGED COPY IS TOLD WHICH CHECK IT FAILED, with both numbers.
  def test_each_check_names_itself_when_it_fails
    { { floors: 59 } => /GAMEMAPS, the number of floors must be 60.*it is 59/m,
      { walls: 107 } => /VSWAP, the number of walls must be 106.*it is 107/m,
      { sprites: 435 } => /VSWAP, the number of sprites must be 436.*it is 435/m,
      { sounds: 45 } => /VSWAP, the number of sounds must be 46.*it is 45/m,
      { pictures: 144 } => /VGAGRAPH, the number of pictures must be 132.*it is 144/m,
      { sizes: SIZES.merge(status_bar: [320, 48]) } => /status bar must be 320x40.*it is 320x48/m,
      { sizes: SIZES.merge(face_1a: [16, 16]) } => /first face must be 24x32.*it is 16x16/m,
      { sizes: SIZES.merge(digit_0: [16, 16]) } => /first numeral must be 8x16.*it is 16x16/m }.each do |changes, says|
      error = assert_raises(Refused, changes.to_s) { check(copy(**changes)) }

      assert_match says, error.message
    end
  end

  # Apogee's copies of the same version number hold 144 pictures, so the message has to name more
  # than the version, and it has to say what to do.
  def test_the_refusal_says_which_copy_is_needed_and_how_to_point_at_it
    error = assert_raises(Refused) { check(copy(pictures: 144)) }

    assert_includes error.message, "1.4"
    assert_includes error.message, "GOG"
    assert_includes error.message, "Apogee"
    assert_includes error.message, "/the/copy"
    assert_includes error.message, Wolf3D::GameData::ENV_VAR
  end

  # A copy of both games is a folder inside a folder, so the Spear refusal says where to look.
  def test_refusing_spear_says_where_the_six_episodes_usually_are
    assert_includes assert_raises(Refused) { check(copy(set: "SOD")) }.message, "one directory above"
  end

  def test_the_made_up_release_is_refused_by_its_floors
    in_a_copy_of_the_made_up_release do |dir|
      error = assert_raises(Refused) { Wolf3D.check_the_copy!(home: dir, env: env(dir)) }

      assert_includes error.message, "the number of floors must be 60"
    end
  end

  # A SPEAR COPY'S REFUSAL REACHES A BUILD, and the file's own extension is what it goes by.
  def test_a_folder_of_spear_is_refused_by_name
    in_a_copy_of_the_made_up_release("SOD") do |dir|
      error = assert_raises(Refused) { Wolf3D.check_the_copy!(home: dir, env: env(dir)) }

      assert_includes error.message, "Spear of Destiny"
    end
  end

  # A FILE CUT SHORT is a refusal in words rather than whatever the reader tripped over.
  def test_a_file_cut_short_is_refused_in_words
    in_a_copy_of_the_made_up_release do |dir|
      File.truncate(File.join(dir, "VSWAP.WL6"), 3)
      error = assert_raises(Refused) { Wolf3D.check_the_copy!(home: dir, env: env(dir)) }

      assert_includes error.message, "cannot read"
    end
  end

  # A FOLDER THAT WAS NAMED AND CANNOT BE USED STOPS A BUILD, and nothing named at all does not:
  # that is what makes the holding screen, and what a machine with no copy runs the suite on.
  def test_a_folder_with_two_releases_stops_a_build
    in_a_copy_of_the_made_up_release do |dir|
      Wolf3D::Fixture::Release.new(set: "SOD").write(dir)

      assert_raises(Wolf3D::GameData::NotFound) { Wolf3D.check_the_copy!(home: dir, env: env(dir)) }
    end
  end

  def test_a_folder_missing_a_file_stops_a_build
    in_a_copy_of_the_made_up_release do |dir|
      File.delete(File.join(dir, "AUDIOHED.WL6"))

      assert_raises(Wolf3D::GameData::NotFound) { Wolf3D.check_the_copy!(home: dir, env: env(dir)) }
    end
  end

  def test_saying_nothing_about_a_copy_does_not_stop_a_build
    Dir.mktmpdir { |home| assert_nil Wolf3D.check_the_copy!(home: home, env: {}) }
  end

  private

  def in_a_copy_of_the_made_up_release(set = "WL6")
    Dir.mktmpdir do |dir|
      Wolf3D::Fixture::Release.new(set: set).write(dir)
      yield dir
    end
  end

  def env(dir) = { Wolf3D::GameData::ENV_VAR => dir }

  def copy(set: "WL6", floors: 60, walls: 106, sprites: 436, sounds: 46, pictures: 132, sizes: SIZES)
    { set: set, maps: Maps.new(floors), vswap: Vswap.new(walls, sprites, sounds),
      vgagraph: Graph.new(pictures, sizes) }
  end

  def check(parts) = Vanilla.check!(dir: "/the/copy", **parts)
end
