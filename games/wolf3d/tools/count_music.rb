# frozen_string_literal: true

# THE TWO TABLES AdlibMusic KEEPS FOR EACH TRACK, counted off both copies through the chip as it is
# now: TICKS, the longest the track runs in either, and LOUDEST, the loudest step it reaches in
# either (Opl2Track.loudest). Run it after any change to Opl2::Operator or Opl2Track that changes
# what they play, and paste what it prints over the two tables. A few minutes.
#
#   ruby games/wolf3d/tools/count_music.rb

require "bundler/setup"
require_relative "../lib/wolf3d"

copies = [Wolf3D::GameData.locate, Wolf3D::GameData.locate(env: { Wolf3D::GameData::COPY_VAR => "shareware" })]
tracks = copies.map { |data| Wolf3D::AdlibMusic.from(data) }
numbers = (0...Wolf3D::AdlibMusic::TRACKS)

ticks = numbers.map { |number| tracks.map { |music| music.writes(number).sum(&:last) }.max }
loudest = numbers.map do |number|
  tracks.map { |music| music.writes(number) }.reject(&:empty?).map { |writes| Wolf3D::Opl2Track.loudest(writes) }.max || 1
end

puts "TICKS = #{ticks.inspect}", "LOUDEST = #{loudest.inspect}"
