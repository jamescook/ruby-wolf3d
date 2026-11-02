# frozen_string_literal: true

# THE SHAREWARE PLAYED START TO FINISH WITH NOBODY AT THE CONTROLS, on the emulator, on fixed random
# numbers. It says the frame each floor ended on, and writes the run as a tape of presses.
#
#   ruby tools/play_shareware.rb                 plays to the winning screen
#   ruby tools/play_shareware.rb --floors 2      stops when two floors are done
#   ruby tools/play_shareware.rb --repeat        plays the tape back and says if it came out the same
#   ruby tools/play_shareware.rb --tape run.tape writes the tape there
#
# A tape is a list of presses and holds nothing of the game's own.

require "bundler/setup"
require "optparse"
require "stringio"

options = { floors: nil, repeat: false, tape: "tmp/shareware.tape", seed: 1 }
OptionParser.new do |parser|
  parser.on("--floors N", Integer) { |n| options[:floors] = n }
  parser.on("--repeat") { options[:repeat] = true }
  parser.on("--tape PATH") { |path| options[:tape] = path }
  parser.on("--seed N", Integer) { |n| options[:seed] = n }
end.parse!

ENV["WOLF3D_COPY"] = "shareware"
require_relative "../lib/wolf3d"

unless Wolf3D::GameData.config_value(Wolf3D.home, "shareware")
  puts "Skipped: there is no copy of the shareware. Set shareware in #{Wolf3D::GameData::CONFIG_FILE}."
  exit 0
end

FRAMES_FOR_A_FLOOR = 30_000
MOST_FLOORS_PLAYED = 9

rom = Wolf3D.build_rom(out: StringIO.new, err: StringIO.new, settings: { seed: options[:seed] })
pilot = Wolf3D::Pilot.new(Wolf3D.maps)
stop_after = options[:floors]
floors_played = (1...MOST_FLOORS_PLAYED).select { |floor| stop_after.nil? || floor <= stop_after }

run = VBlank.playthrough "the shareware" do
  floors_played.each do |floor|
    steer("finish floor #{floor}", within: FRAMES_FOR_A_FLOOR) do |game|
      next :done if game.var(:floor) >= floor

      pilot.buttons_for(game)
    end
    moment :"floor_#{floor}_done"
  end
  if stop_after.nil?
    steer("reach the winning screen", within: FRAMES_FOR_A_FLOOR) { |game| pilot.buttons_for(game) }
    moment :won
  end
end

played = run.play(rom)
played.moments.each { |name, frame| puts "#{name}: frame #{frame}" }
game = played.game
puts "lives #{game.var(:lives)}, health #{game.var(:health)}, score #{game.var(:score)}, #{played.frames} frames"
File.dirname(options[:tape]).then { |folder| Dir.mkdir(folder) unless Dir.exist?(folder) }
played.tape.write(options[:tape])
puts "tape: #{options[:tape]}"

if options[:repeat]
  again = played.tape.play(rom)
  same = again.frames == played.frames && %i[score health lives floor px py].all? { |name| again.game.var(name) == game.var(name) }
  puts same ? "The tape played back the same." : "The tape did not play back the same."
  exit same ? 0 : 1
end
