# frozen_string_literal: true

# EVERY FLOOR OF YOUR COPY, written out for planning a run: where it starts, what lies about, who
# stands where and a route to the way out. WOLF3D_COPY=shareware reads the second copy.
#
#   ruby tools/floor_report.rb                    prints it
#   ruby tools/floor_report.rb hard > tmp/f.txt   at another difficulty
#
# It is read out of the game's own maps, so what it prints stays out of the repository.

require "bundler/setup"
require_relative "../lib/wolf3d"

difficulty = (ARGV.first || "easy").to_sym
data = Wolf3D::GameData.locate
maps = Wolf3D::Maps.from(data)
puts data.describe

maps.count.times do |n|
  level = maps[n]
  report = Wolf3D::FloorReport.new(level)
  route = report.route
  puts "", "Floor #{n + 1}: #{level.name}, starts at #{report.start.x},#{report.start.y} facing #{report.start.facing}"
  puts "  way out: #{route ? "#{route.ends_at}, #{route.cells.length} cells" : 'NO ROUTE'}"
  puts "  route: #{route.cells.map { |x, y| "#{x},#{y}" }.join(' ')}" if route
  puts "  doors: #{report.doors.length}, secret walls: #{report.pushwalls.length}"
  report.guards(difficulty).each { |g| puts "  guard: #{g.kind} at #{g.x},#{g.y} #{g.facing}#{' patrolling' if g.patrolling}" }
  report.pickups.each { |p| puts "  pickup: #{p.bonus.join(' ')} at #{p.x},#{p.y}" }
end
