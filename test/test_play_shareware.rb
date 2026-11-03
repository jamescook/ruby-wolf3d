# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

# THE PILOT ON THE REAL SHAREWARE, for as far as two floors take: the menus, a floor's guards and
# keys, a lever, the screen between floors, and the same run again from its tape. The whole episode
# takes minutes, so `ruby tools/play_shareware.rb --repeat` is what plays that.
#
# A run of its own process, because the copy a build reads is the whole process's.
class TestPlayShareware < Minitest::Test
  include Wolf3DTest

  TOOL = File.expand_path("../tools/play_shareware.rb", __dir__)
  RUBY = RbConfig.ruby

  # Asked before the tool looks for a copy, so it says the same on every machine.
  def test_a_difficulty_the_game_does_not_have_is_refused
    said, status = Open3.capture2e(RUBY, TOOL, "--difficulty", "nightmare")

    refute_predicate status, :success?
    assert_includes said, "--difficulty"
    assert_includes said, "baby, easy, medium, hard"
  end

  def test_the_pilot_finishes_two_floors_and_its_tape_repeats
    shareware_or_skip
    name = "wolf3d-pilot-#{Process.pid}.tape"
    tape = File.join(Dir.tmpdir, name)
    said, status = Open3.capture2e(RUBY, TOOL, "--floors", "2", "--repeat", "--tape", name, chdir: Dir.tmpdir)

    assert_predicate status, :success?, said
    assert_match(/floor_1_done\s+frame \d+/, said)
    assert_match(/floor_2_done\s+frame \d+/, said)
    assert_includes said, "The tape played back the same."
    assert_path_exists tape, "a relative --tape is relative to where the tool was run from"
  ensure
    FileUtils.rm_f(tape) if tape
  end
end
