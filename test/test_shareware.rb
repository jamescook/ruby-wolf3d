# frozen_string_literal: true

require_relative "test_helper"

# THE SHAREWARE AGAINST A REAL COPY, because what this game knows of it is one sum: every picture
# of the six episodes, twelve later. A sum read from the original's headers is a good guess, and
# the copy is what says whether it is right.
#
# The sizes here are read off wolf3dsw, version 1.4, and written out so a change to the names has
# something to disagree with.
class TestShareware < Minitest::Test
  include Wolf3DTest

  def shareware = Wolf3D::Vgagraph.from(shareware_or_skip)

  def test_a_real_copy_is_accepted
    assert_nil Wolf3D::Vanilla.check_files!(shareware_or_skip)
  end

  def test_the_pictures_found_by_name_are_the_size_they_should_be
    graph = shareware

    { status_bar: [320, 40], title: [320, 200], credits: [320, 200], menu_gun: [24, 16],
      menu_heading: [152, 48], digit_0: [8, 16], face_1a: [24, 32], bj_wins: [88, 88], difficulty_baby: [24, 32],
      tally_0: [16, 16], tally_z: [16, 16] }.each do |name, size|
      assert_equal size, graph.size(name), name.to_s
    end
  end

  # EVERY NAME AGAINST THE SIX EPISODES, which are the same pictures: only the numbers moved.
  def test_every_name_is_the_same_picture_size_as_in_the_six_episodes
    full = game_data_or_skip
    skip("the suite's own copy is the shareware") unless full.set == "WL6"
    six = Wolf3D::Vgagraph.from(full)
    graph = shareware

    six.names.each { |name| assert_equal six.size(name), graph.size(name), name.to_s }
  end

  # T_ENDART1 is the last chunk of the file, and the original starts an article with ^P.
  def test_the_first_episode_ends_on_its_own_article
    article = shareware.then { |graph| graph.text(graph.end_article_chunk(0)) }

    assert article.start_with?("^P"), "an article starts with the mark for a page"
    assert_includes article, "Eisenfaust", "and goes on to the next mission"
  end
end
