# frozen_string_literal: true

# THE SHAREWARE PLAYED START TO FINISH WITH NOBODY AT THE CONTROLS, on fixed random numbers. It says
# the frame each floor ended on.
#
#   ruby tools/play_shareware.rb                     on the emulator, as fast as it will go
#   ruby tools/play_shareware.rb --window            in a window, at the console's frame rate
#   ruby tools/play_shareware.rb --on native         or interpreter, web, ruby, emulator
#   ruby tools/play_shareware.rb --floors 2          stops when two floors are done
#   ruby tools/play_shareware.rb --difficulty hard   baby, easy, medium or hard, or 1 to 4. Default baby
#   ruby tools/play_shareware.rb --music             with effects and music on, whichever way it runs
#   ruby tools/play_shareware.rb --repeat            plays the run back from its tape, and says if
#                                                    it came out the same
#   ruby tools/play_shareware.rb --tape run.tape     writes the tape there
#
# Each way of running is a run of its own, because a pass that takes two frames on the console takes
# one on a computer. A tape is a list of presses and holds nothing of the game's own, so it plays only
# on the way it was recorded on, built with the same settings.

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
require "bundler/setup"
require "English"
require "fileutils"
require "open3"
require "optparse"
require "tmpdir"

options = { on: "emulator", window: false, floors: nil, repeat: false, tape: "tmp/shareware.tape", seed: 1 }
OptionParser.new do |parser|
  parser.on("--on WAY") { |way| options[:on] = way }
  parser.on("--window") { options[:window] = true }
  parser.on("--floors N", Integer) { |n| options[:floors] = n }
  parser.on("--repeat") { options[:repeat] = true }
  parser.on("--tape PATH") { |path| options[:tape] = File.expand_path(path) }
  parser.on("--seed N", Integer) { |n| options[:seed] = n }
  parser.on("--difficulty SETTING") { |setting| options[:difficulty] = setting }
  parser.on("--music") { options[:music] = true }
end.parse!

ENV["WOLF3D_COPY"] = "shareware"
ENV["WOLF3D_PILOT_FLOORS"] = options[:floors].to_s if options[:floors]
require_relative "../lib/wolf3d"

names = Wolf3D::Pilot::DIFFICULTY_NAMES
asked = options.fetch(:difficulty, names.first)
difficulty = names.index(asked) || (asked.match?(/\A[1-#{names.length}]\z/) ? asked.to_i - 1 : nil)
abort "--difficulty cannot read #{asked.inspect}. The game has #{names.length} settings. Give #{names.join(', ')}, or 1 to #{names.length}." unless difficulty
ENV["WOLF3D_PILOT_DIFFICULTY"] = difficulty.to_s

unless Wolf3D::GameData.config_value(Wolf3D.home, "shareware")
  puts "Skipped: there is no copy of the shareware. Set shareware in #{Wolf3D::GameData::CONFIG_FILE}."
  exit 0
end

Dir.chdir(File.expand_path("..", __dir__))
FileUtils.mkdir_p(File.dirname(options[:tape]))

play = %w[bundle exec vblank play wolf3d.rb]
seed = ["--set", "seed=#{options[:seed]}", *("music=on" if options[:music])]
way = ["--on", options[:on]]
run = play + ["--script", "tools/shareware_playthrough.rb"] + way
run << "--window" if options[:window]
run += ["--write-tape", options[:tape]] unless options[:on] == "logic"
screens = File.join(Dir.mktmpdir("shareware"), "played")
run += ["--pictures-in", screens] if options[:repeat]

# Each floor the pilot starts, and what the player says about the run, which begins at this line.
# The rest is what the build says of its speed.
report_line = lambda { |line| line.match?(/\A(frame \d+:|Played|  \w+ +frame)/) || line.include?("tape") }

# A whole run takes minutes, so each line is shown as it comes. All of it is shown if the run fails.
play_showing_report = lambda do |command|
  # A window is the player's own process, with this terminal as its own.
  if options[:window]
    system(*command)
    next $CHILD_STATUS
  end

  said = +""
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  reported = false
  status = Open3.popen2e(*command) do |_input, output, thread|
    # The build says nothing for about a minute and a floor can take minutes, so this keeps saying
    # what is going on until the run is over.
    waiting = Thread.new do
      loop do
        sleep 10
        puts format("%s: %d seconds so far.", reported ? "Still playing" : "Still building",
                    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      end
    end
    output.each_line do |line|
      said << line
      next unless report_line.call(line)

      reported = true
      print line
    end
    waiting.kill
    thread.value
  end
  puts said unless status.success?
  status
end

$stdout.sync = true
puts format("The bot plays seed %d on the %s setting, way of running: %s, with %s.", options[:seed],
            names[difficulty], options[:on], options[:music] ? "effects and music" : "the default sound")
puts options[:window] ? "A window opens when the game is built." : "There is no window, so nothing appears on the screen. To watch, add --window."
puts "The game builds first, which takes about a minute. Then each floor is shown as it starts."
began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
status = play_showing_report.call(run + seed)
puts format("%.0f seconds", Process.clock_gettime(Process::CLOCK_MONOTONIC) - began)
puts status.success? ? "The run is over." : "The run stopped before the end. The output above says why."
exit 1 unless status.success?

# THE SAME RUN IS THE SAME SCREENS. A tape says on which frame each moment falls whatever it plays
# on, so the frames prove nothing. The picture at each moment is what the game really came to.
if options[:repeat]
  replayed = File.join(File.dirname(screens), "replayed")
  status = play_showing_report.call(play + ["--tape", options[:tape], "--pictures-in", replayed] + way + seed)
  files = Dir.children(screens).sort
  same = status.success? && files.any? && files == Dir.children(replayed).sort &&
         files.all? { |file| FileUtils.identical?(File.join(screens, file), File.join(replayed, file)) }
  puts same ? "The tape played back the same." : "The tape did not play back the same."
  exit same ? 0 : 1
end
