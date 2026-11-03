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
  parser.on("--tape PATH") do |path|
    options[:tape] = File.expand_path(path)
    options[:tape_asked] = true
  end
  parser.on("--seed N", Integer) { |n| options[:seed] = n }
  parser.on("--difficulty SETTING") { |setting| options[:difficulty] = setting }
  parser.on("--music") { options[:music] = true }
  parser.on("--verbose") { options[:verbose] = true }
end.parse!

# What cannot go together is refused here, before a minute goes on the build.
logic = options[:on] == "logic"
abort "--repeat cannot go with --on logic. That way writes no tape. Remove --repeat, or use --on emulator." if options[:repeat] && logic
abort "--window cannot go with --on logic. That way has no picture. Remove --window, or use --on emulator." if options[:window] && logic
if options[:window] && options[:repeat]
  abort "--window cannot go with --repeat. A closed window leaves no tape to play back. Remove one of the two."
end

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
run += ["--write-tape", options[:tape]] unless logic
# Only a repeat compares pictures, so only a repeat needs a place for them.
pictures = Dir.mktmpdir("shareware") if options[:repeat]
at_exit { FileUtils.remove_entry(pictures) if pictures }
run += ["--pictures-in", File.join(pictures, "played")] if options[:repeat]

# Each floor the pilot starts, each death, and what the player says about the run. The rest is what
# the build says of its speed.
report_line = lambda { |line| line.match?(/\A(floor \d+ starts|BJ died|Played|  \w+ +frame|Wrote the tape)/) }

# A whole run takes minutes, so each line is shown as it comes. All of it is shown if the run fails,
# unless it failed because BJ died for the last time, which one line says, or --verbose asks for it.
# +building+ and +playing+ say what is going on, before the first line of the report and after it.
lost_run = nil
play_showing_report = lambda do |command, building:, playing:|
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
        puts format("%s: %d seconds so far.", reported ? playing : building,
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
  lost_run = said[/The pilot lost its last life on floor \d+, on frame \d+\./]
  puts said if !status.success? && (lost_run.nil? || options[:verbose])
  status
end

$stdout.sync = true
puts format("The bot plays seed %d on the %s setting, way of running: %s, with %s.", options[:seed],
            names[difficulty], options[:on], options[:music] ? "effects and music" : "the default sound")
puts options[:window] ? "A window opens when the game is built." : "There is no window, so nothing appears on the screen. To watch, add --window."
puts "The game builds first, which takes about a minute. Then each floor is shown as it starts."
puts "--on logic writes no tape, so this run writes nothing to #{options[:tape]}." if logic && options[:tape_asked]
began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
old_tape_time = File.mtime(options[:tape]) if File.exist?(options[:tape])
status = play_showing_report.call(run + seed, building: "Still building", playing: "Still playing")
puts format("%.0f seconds", Process.clock_gettime(Process::CLOCK_MONOTONIC) - began)

# A CLOSED WINDOW IS NOT A FAILURE, so vblank exits as it does at the end of a run. What tells them
# apart is the tape, which is written only when the playing reaches the end.
if status.success? && options[:window] && (!File.exist?(options[:tape]) || File.mtime(options[:tape]) == old_tape_time)
  puts "The window was closed, so the run stopped. No tape was written."
  exit 0
end

puts lost_run if lost_run
puts "The run is over." if status.success?
puts "The run stopped before the end. The output above says why." unless status.success? || lost_run
exit 1 unless status.success?

# THE SAME RUN IS THE SAME SCREENS. A tape says on which frame each moment falls whatever it plays
# on, so the frames prove nothing. The picture at each moment is what the game really came to.
if options[:repeat]
  screens = File.join(pictures, "played")
  replayed = File.join(pictures, "replayed")
  puts "The tape plays back now, to make sure that it gives the same run."
  status = play_showing_report.call(play + ["--tape", options[:tape], "--pictures-in", replayed] + way + seed,
                                    building: "Still playing back", playing: "Still playing back")
  files = Dir.children(screens).sort
  same = status.success? && files.any? && files == Dir.children(replayed).sort &&
         files.all? { |file| FileUtils.identical?(File.join(screens, file), File.join(replayed, file)) }
  puts same ? "The tape played back the same." : "The tape did not play back the same."
  exit same ? 0 : 1
end
