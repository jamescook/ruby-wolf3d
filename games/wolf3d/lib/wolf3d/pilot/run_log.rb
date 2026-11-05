# frozen_string_literal: true

require "json"

module Wolf3D
  class Pilot
    # WHAT HAPPENED IN A RUN, one JSON object a line, for working out where the pilot loses. It
    # watches the same game the pilot does and writes:
    #
    # - +run+, first: whatever the caller said about the run (its seed, say) and the setting.
    # - +floor_start+ and +floor_end+: health, ammunition, gun and lives as a floor begins and ends.
    #   A death starts the floor again, so it starts once for each life spent on it.
    # - +wound+: health lost, what the pilot was doing (FloorPlay::TACTICS), where BJ stood, how many
    #   men had a line to him, and +by+, the man most likely to have fired.
    # - +shot+: a round spent, the gun, how far off the nearest man in line stood, and whether any man
    #   lost hit points before the next round or SHOT_FRAMES had passed.
    # - +kill+: a man who fell, and where.
    # - +death+: BJ's, where, and +by+ as on his last wound.
    # - +end+: won or lost, on which floor and frame.
    #
    # A MAN IS NAMED BY WHERE HE STANDS WHEN THE FLOOR STARTS, with his kind: the map's own place for
    # him, the same on every run, which is what lets runs on other seeds be added together. His slot
    # in the pool says nothing, for the pool is filled in an order of its own.
    class RunLog
      # A guard's hit lands within a few frames of the round going, so this long without one is a miss.
      SHOT_FRAMES = 10

      # +io+ is written a line at a time and flushed, so a run that stops still leaves its log.
      # +about+ goes on the +run+ line.
      def initialize(io, about: {})
        @io = io
        @about = about
        @sights = {}
        @kinds = {}
      end

      # Called each frame of play, after the pilot has chosen. +level+ and +report+ are the floor's.
      def record(game, floor:, level:, report:, frame:, tactic:, difficulty:)
        write(event: :run, difficulty: Pilot::DIFFICULTY_NAMES[difficulty], **@about) unless @begun
        @begun = true
        sight = (@sights[floor] ||= Sight.new(level, report.doors))
        sight.read(game, pass: 0)
        @frame = frame
        @floor = floor + 1
        lives = game.var(:lives)
        start_floor(game, level, sight, lives) if floor + 1 != @floor_started || lives < @lives
        @lives = lives
        @sight = sight
        @tactic = tactic
        note_health(sight)
        note_shots(sight)
        note_kills(sight)
      end

      # The run is over: +won+ or not.
      def finish(won:, frame:)
        close_shot
        write(event: :end, won: won, floor: @floor, frame: frame)
      end

      private

      def write(**event)
        @io.puts(JSON.generate(event))
        @io.flush
      end

      def start_floor(game, level, sight, lives)
        if @floor_started && @floor_started != @floor
          write(event: :floor_end, floor: @floor_started, frame: @frame, health: @health, ammo: @ammo, lives: lives)
        end
        close_shot
        @floor_started = @floor
        @health = sight.health
        @ammo = sight.ammo
        @hit_points = sight.guards.to_h { |man| [man.number, man.hit_points] }
        @names = sight.guards.to_h { |man| [man.number, name_man(level, man)] }
        write(event: :floor_start, floor: @floor, frame: @frame, health: sight.health, ammo: sight.ammo,
              weapon: sight.weapon, lives: lives)
      end

      def name_man(level, man)
        kinds = (@kinds[level] ||= Guards.new(level).guards.to_h { |guard| [[guard.x, guard.y], guard.kind] })
        home = [man.x.floor, man.y.floor]
        { kind: kinds.fetch(home, :unknown), home: home }
      end

      def note_health(sight)
        if sight.health < @health
          @last_shooter = shooter(sight)
          write(event: :wound, floor: @floor, frame: @frame, damage: @health - sight.health, health: sight.health,
                ammo: sight.ammo, weapon: sight.weapon, tactic: @tactic, at: [sight.x.round(1), sight.y.round(1)],
                men_with_line: men_with_line(sight).length, by: @last_shooter)
          if sight.health <= 0
            write(event: :death, floor: @floor, frame: @frame, at: [sight.x.round(1), sight.y.round(1)], tactic: @tactic,
                  by: @last_shooter)
          end
        end
        @health = sight.health
      end

      def men_with_line(sight) = sight.men.select { |man| sight.clear_line_to?(man.x, man.y) }

      # The nearest man with a line to BJ is the likeliest to have fired. With nobody in line, the
      # nearest man at all, marked +no_line+: the pilot's line and the game's disagree about him.
      def shooter(sight)
        in_line = men_with_line(sight).min_by { |m| sight.distance_to_man(m) }
        man = in_line || sight.men.min_by { |m| sight.distance_to_man(m) }
        return nil unless man

        named = @names.fetch(man.number, {}).merge(distance: sight.distance_to_man(man).round(1),
                                                   in_front: sight.in_view?(man.x, man.y))
        in_line ? named : named.merge(no_line: true)
      end

      # A hit can land on the frame the round goes, so a new shot is opened before hits are counted.
      # The round that kills a man has him fall on the same frame, so how far off he stood is read
      # from the frame before.
      def note_shots(sight)
        if sight.ammo < @ammo
          close_shot
          @shot = { weapon: sight.weapon, distance: @nearest_in_line&.round(1), hit: false, frames: 0 }
        end
        @ammo = sight.ammo
        @nearest_in_line = men_with_line(sight).map { |man| sight.distance_to_man(man) }.min
        return unless @shot

        now = sight.guards.to_h { |man| [man.number, man.hit_points] }
        @shot[:hit] ||= @hit_points.any? { |number, points| now.fetch(number, points) < points }
        @shot[:frames] += 1
        close_shot if @shot[:frames] > SHOT_FRAMES
      end

      def close_shot
        return unless @shot

        write(event: :shot, floor: @floor, frame: @frame, weapon: @shot[:weapon], distance: @shot[:distance], hit: @shot[:hit])
        @shot = nil
      end

      def note_kills(sight)
        sight.guards.each do |man|
          before = @hit_points[man.number].to_i
          if before.positive? && !man.alive?
            write(event: :kill, floor: @floor, frame: @frame, **@names.fetch(man.number, { kind: :unknown }),
                  at: [man.x.round(1), man.y.round(1)], distance: @sight.distance_to_man(man).round(1))
          end
          @hit_points[man.number] = man.hit_points
        end
      end
    end
  end
end
