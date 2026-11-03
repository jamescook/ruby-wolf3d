# frozen_string_literal: true

# WHERE THE PILOT LOSES, summed over the run logs that tools/play_shareware.rb --run-log writes.
#
#   ruby tools/pilot_hot_spots.rb run1.jsonl run2.jsonl ...
#
# It says how each run ended, then for all of them together: what each floor costs, which men hurt
# BJ and kill him most, which die most, where on each floor he is hurt most, what he was doing, how
# near the men stood, and how often a shot hits. A man is named by his kind and the cell he starts
# in, so the same man on another seed adds to the same line.

require "json"

abort "Give one or more run logs. tools/play_shareware.rb --run-log FILE writes one." if ARGV.empty?

runs = ARGV.map { |path| [path, File.readlines(path).map { |line| JSON.parse(line) }] }
events = runs.flat_map(&:last)
of = ->(kind) { events.select { |event| event["event"] == kind } }
wounds = of["wound"]
damage = wounds.sum { |wound| wound["damage"] }

def man_name(man) = man ? "#{man['kind']} from #{man['home']&.join(',')}" : "nobody with a line"

def show(title, rows, limit: 12)
  puts "\n#{title}"
  rows.first(limit).each { |row| puts "  #{row}" }
end

def share(part, whole) = whole.zero? ? 0 : (100.0 * part / whole).round

puts "RUNS"
runs.each do |path, run|
  about = run.find { |event| event["event"] == "run" } || {}
  ending = run.reverse.find { |event| event["event"] == "end" }
  deaths = run.select { |event| event["event"] == "death" }.map { |event| event["floor"] }
  outcome = ending ? "#{ending['won'] ? 'won' : 'lost'} on floor #{ending['floor']}" : "stopped before the end"
  puts format("  %-28s seed %-4s %-6s %-20s died on floors %s", File.basename(path), about["seed"], about["difficulty"],
              outcome, deaths.empty? ? "none" : deaths.join(","))
end

puts "\n#{wounds.length} wounds, #{damage} health lost, #{of['death'].length} deaths, #{of['kill'].length} men killed"

floors = events.map { |event| event["floor"] }.compact.uniq.sort
show("EACH FLOOR (summed over runs): health lost, deaths, rounds fired, hits", floors.map do |floor|
  hurt = wounds.select { |wound| wound["floor"] == floor }.sum { |wound| wound["damage"] }
  shots = of["shot"].select { |shot| shot["floor"] == floor }
  format("floor %-2d %5d health  %2d deaths  %5d rounds  %3d%% hit", floor, hurt,
         of["death"].count { |death| death["floor"] == floor }, shots.length, share(shots.count { |shot| shot["hit"] }, shots.length))
end, limit: floors.length)

killers = of["death"].group_by { |death| [death["floor"], man_name(death["by"])] }
show("WHO KILLS BJ: floor, man, deaths", killers.sort_by { |_, list| -list.length }.map do |(floor, man), list|
  format("floor %-2d %-26s %d", floor, man, list.length)
end)

hurters = wounds.group_by { |wound| [wound["floor"], man_name(wound["by"])] }
show("WHO HURTS BJ MOST: floor, man, health, wounds", hurters.map do |(floor, man), list|
  [floor, man, list.sum { |wound| wound["damage"] }, list.length]
end.sort_by { |row| -row[2] }.map { |floor, man, hurt, count| format("floor %-2d %-26s %5d health %4d wounds", floor, man, hurt, count) })

show("WHO HURTS BJ, by kind", wounds.group_by { |wound| wound.dig("by", "kind") || "nobody with a line" }.map do |kind, list|
  hurt = list.sum { |wound| wound["damage"] }
  [kind, hurt, share(hurt, damage)]
end.sort_by { |row| -row[1] }.map { |kind, hurt, pct| format("%-20s %5d health %3d%%", kind, hurt, pct) })

show("WHO DIES, by kind", of["kill"].group_by { |kill| kill["kind"] }.map { |kind, list| [kind, list.length] }
  .sort_by { |row| -row[1] }.map { |kind, count| format("%-20s %4d", kind, count) })

# A hot spot is a square of four cells by four on one floor.
spots = wounds.group_by { |wound| [wound["floor"], wound["at"].map { |n| (n / 4).floor * 4 }] }
show("WHERE BJ IS HURT: floor, the cells of a 4 by 4 square, health, deaths there", spots.map do |(floor, (x, y)), list|
  died = of["death"].count { |death| death["floor"] == floor && death["at"].map { |n| (n / 4).floor * 4 } == [x, y] }
  [floor, x, y, list.sum { |wound| wound["damage"] }, died]
end.sort_by { |row| -row[3] }.map do |floor, x, y, hurt, died|
  format("floor %-2d cells %2d-%-2d, %2d-%-2d %5d health %2d deaths", floor, x, x + 3, y, y + 3, hurt, died)
end)

show("WHAT IT WAS DOING WHEN HURT", wounds.group_by { |wound| wound["tactic"] || "starting" }.map do |tactic, list|
  hurt = list.sum { |wound| wound["damage"] }
  [tactic, hurt, share(hurt, damage)]
end.sort_by { |row| -row[1] }.map { |tactic, hurt, pct| format("%-18s %5d health %3d%%", tactic, hurt, pct) })

near = lambda do |distance|
  next "nobody with a line" unless distance
  next "under 2 cells" if distance < 2
  next "2 to 4 cells" if distance < 4
  next "4 to 7 cells" if distance < 7

  "7 cells or more"
end
show("HOW FAR OFF THE MAN WHO HURT BJ STOOD", wounds.group_by { |wound| near.call(wound.dig("by", "distance")) }.map do |where, list|
  hurt = list.sum { |wound| wound["damage"] }
  [where, hurt, share(hurt, damage)]
end.sort_by { |row| -row[1] }.map { |where, hurt, pct| format("%-20s %5d health %3d%%", where, hurt, pct) })

guns = { 1 => "pistol", 2 => "machine gun", 3 => "chain gun" }
show("SHOTS: gun, distance to the nearest man in line, rounds, hits", of["shot"].group_by do |shot|
  [guns.fetch(shot["weapon"], shot["weapon"].to_s), near.call(shot["distance"])]
end.sort.map do |(gun, where), list|
  format("%-12s %-20s %5d rounds %3d%% hit", gun, where, list.length, share(list.count { |shot| shot["hit"] }, list.length))
end, limit: 20)
