# frozen_string_literal: true

# THE SHAREWARE PLAYED START TO FINISH WITH NOBODY AT THE CONTROLS, on fixed random numbers. It says
# the frame each floor ended on.
#
#   ruby tools/play_shareware.rb                     on the emulator, as fast as it will go
#   ruby tools/play_shareware.rb --window            in a window, at the console's frame rate
#   ruby tools/play_shareware.rb --on native         or interpreter, web, ruby, emulator
#   ruby tools/play_shareware.rb --floors 2          stops when two floors are done
#   ruby tools/play_shareware.rb --hardest           on the hardest setting, and not the easiest
#   ruby tools/play_shareware.rb --repeat            plays the run back from its tape, and says if
#                                                    it came out the same (emulator only)
#   ruby tools/play_shareware.rb --tape run.tape     writes the tape there
#
# Each way of running is a run of its own, because a pass that takes two frames on the console takes
# one on a computer. A tape is a list of presses and holds nothing of the game's own.

require "bundler/setup"
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
  parser.on("--tape PATH") { |path| options[:tape] = path }
  parser.on("--seed N", Integer) { |n| options[:seed] = n }
  parser.on("--hardest") { options[:hardest] = true }
end.parse!

ENV["WOLF3D_COPY"] = "shareware"
ENV["WOLF3D_PILOT_FLOORS"] = options[:floors].to_s if options[:floors]
ENV["WOLF3D_PILOT_HARDEST"] = "1" if options[:hardest]
require_relative "../lib/wolf3d"

unless Wolf3D::GameData.config_value(Wolf3D.home, "shareware")
  puts "Skipped: there is no copy of the shareware. Set shareware in #{Wolf3D::GameData::CONFIG_FILE}."
  exit 0
end

Dir.chdir(File.expand_path("..", __dir__))
FileUtils.mkdir_p(File.dirname(options[:tape]))

play = %w[bundle exec vblank play wolf3d.rb]
seed = ["--set", "seed=#{options[:seed]}"]
run = play + ["--script", "tools/shareware_playthrough.rb", "--on", options[:on]]
run << "--window" if options[:window]
run += ["--write-tape", options[:tape]] if options[:on] == "emulator"
screens = File.join(Dir.mktmpdir("shareware"), "played")
run += ["--pictures-in", screens] if options[:repeat]

# Each floor the pilot starts, and what the player says about the run, which begins at this line.
# The rest is what the build says of its speed.
report_from = lambda { |said| said.lines.select { |line| line.match?(/\A(frame \d+:|Played|  \w+ +frame)/) || line.include?("tape") }.join }

began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
said, status = Open3.capture2e(*(run + seed))
puts status.success? ? report_from.call(said) : said
puts format("%.0f seconds", Process.clock_gettime(Process::CLOCK_MONOTONIC) - began)
exit 1 unless status.success?

# THE SAME RUN IS THE SAME SCREENS. A tape says on which frame each moment falls whatever it plays
# on, so the frames prove nothing. The picture at each moment is what the game really came to.
if options[:repeat]
  replayed = File.join(File.dirname(screens), "replayed")
  again, status = Open3.capture2e(*(play + ["--tape", options[:tape], "--pictures-in", replayed] + seed))
  puts status.success? ? report_from.call(again) : again
  files = Dir.children(screens).sort
  same = status.success? && files.any? && files == Dir.children(replayed).sort &&
         files.all? { |file| FileUtils.identical?(File.join(screens, file), File.join(replayed, file)) }
  puts same ? "The tape played back the same." : "The tape did not play back the same."
  exit same ? 0 : 1
end
