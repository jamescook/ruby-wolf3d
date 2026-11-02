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

  def test_the_pilot_finishes_two_floors_and_its_tape_repeats
    shareware_or_skip
    tape = File.join(Dir.tmpdir, "wolf3d-pilot-#{Process.pid}.tape")
    said, status = Open3.capture2e(RUBY, TOOL, "--floors", "2", "--repeat", "--tape", tape)

    assert_predicate status, :success?, said
    assert_match(/floor_1_done\s+frame \d+/, said)
    assert_match(/floor_2_done\s+frame \d+/, said)
    assert_includes said, "The tape played back the same."
  ensure
    FileUtils.rm_f(tape) if tape
  end
end
