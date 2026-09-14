# frozen_string_literal: true

# WHERE THE BUILD'S TIME GOES — which is not where the GAME's time goes.
#
# Two different questions, two different clocks, and they are easy to mix up:
#
#   this file    Ruby running on your machine, between typing the command and holding a
#                cartridge. Sampled with stackprof, read as a flame graph.
#   rom.profile  the console running the finished cartridge, where each of its 228 scanlines
#                a frame went. Nothing to do with this.
#
# Run it with `rake build:profile`. It leaves two files: the sampler's own dump, and the JSON
# that speedscope.org reads. Open https://speedscope.org and drag the JSON onto it.
#
# WHAT IS SAMPLED is the BUILD. Reading your copy of Wolfenstein and declaring the game happen
# when this file requires the game, before the sampler starts, and are timed separately below
# so that a reading always says how big that part was rather than leaving it to be assumed.

require "bundler/setup"
require "fileutils"
require "stackprof"
require "stringio"

module ProfileBuild
  OUT_DIR = File.expand_path("../tmp", __dir__)

  # Wall-clock microseconds between samples. A build of every floor runs for tens of seconds,
  # so a sample every millisecond is tens of thousands of them: enough for the small routines
  # to show up, and small enough that the sampling itself is not what you are measuring.
  INTERVAL = 1000

  # How many of the heaviest routines to print. The flame graph is the real answer; this is so
  # that a run says something without opening a browser.
  SHOWN = 15

  def self.run
    FileUtils.mkdir_p(OUT_DIR)
    stamp = Time.now.strftime("%Y%m%d-%H%M%S")
    dump = File.join(OUT_DIR, "build-#{stamp}.dump")
    json = File.join(OUT_DIR, "build-#{stamp}.json")

    declared = time_it { require_relative "../lib/wolf3d" }
    built = nil
    # mode: :wall counts time as a clock does, so waiting counts. :cpu would hide anything the
    # build spends reading files, which is a fair share of what it does.
    # raw: true keeps every sample's whole stack rather than only the totals, which is the part
    # a flame graph is drawn from — without it speedscope has nothing to show.
    StackProf.run(mode: :wall, raw: true, interval: INTERVAL, out: dump) do
      built = time_it { Wolf3D.build_rom(out: StringIO.new, err: StringIO.new) }
    end

    report = StackProf::Report.new(Marshal.load(File.binread(dump)))
    File.open(json, "w") { |file| report.print_json(file) }

    say(declared, built, report, dump, json)
  end

  def self.time_it
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  def self.say(declared, built, report, dump, json)
    puts format("reading the game and declaring it   %6.2fs   (not sampled)", declared)
    puts format("building the cartridge              %6.2fs   %d samples", built,
                report.data[:samples])
    puts
    report.print_text(false, SHOWN)
    puts
    puts "Flame graph: open https://speedscope.org and drop #{json} onto it."
    puts "The sampler's own dump is #{dump}."
  end
end

ProfileBuild.run if $PROGRAM_NAME == __FILE__
