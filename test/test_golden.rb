# frozen_string_literal: true

require_relative "test_helper"

# THE LIST `rake test:golden` PLAYS. A name left behind by a renamed file would stop the run, and a
# list that grew to the whole suite would be no quicker check than the suite.
class TestGolden < Minitest::Test
  include Wolf3DTest

  ROOT = File.expand_path("..", __dir__)

  def listed = File.readlines(File.join(ROOT, "test/golden.txt"), chomp: true).grep(/\Atest/)

  def test_every_file_on_the_list_exists
    listed.each { |file| assert_path_exists File.join(ROOT, file) }
  end

  def test_the_list_is_under_a_third_of_the_suite
    assert_operator listed.length * 3, :<, Dir[File.join(ROOT, "test/test_*.rb")].length
  end
end
