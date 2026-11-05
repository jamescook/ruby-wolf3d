# frozen_string_literal: true

module Wolf3D
  # HOW EACH FLOOR OF THE EPISODE WENT, for the screen at the end of it (LevelRatios, wl_inter.cpp). The
  # original keeps eight, the eight ordinary floors, and adds what you took on each. So a floor skipped
  # by a lift counts as nothing rather than being left out of the average.
  #
  # THE FLOOR'S CLOCK LIVES HERE TOO, because that time is one of the things kept. It is GAME time, not
  # a stopwatch: it counts passes of the game loop, and so it slows down exactly as the world does when
  # a heavy view takes longer to draw. Stand by a door and you lose nothing against par for it.
  class FloorRecords
    FLOORS = 8

    # THE ORIGINAL'S CLOCK COUNTS SEVENTY TICS A SECOND (gamestate.TimeCount), and a pass of this game
    # moves the player about a tic's worth, so a pass counts as one tic. That rate is held against the
    # original in test_guards.rb.
    PASSES_PER_SECOND = 70

    # sec > 99 * 60 in LevelCompleted: the clock stops there.
    MOST_SECONDS = 99 * 60

    def initialize(build:, lasting:)
      @b = build
      @kills = lasting.list :floor_kill_ratio, capacity: FLOORS, width: :byte
      @secrets = lasting.list :floor_secret_ratio, capacity: FLOORS, width: :byte
      @treasures = lasting.list :floor_treasure_ratio, capacity: FLOORS, width: :byte
      @seconds = lasting.list :floor_seconds, capacity: FLOORS, width: :half
      FLOORS.times do
        [@kills, @secrets, @treasures, @seconds].each { |list| list << 0 }
      end
      @passes = lasting.var :floor_passes, 0
      @slot = @b.var :_record_slot, 0
      @seconds_played = @b.var :_tally_seconds_played, 0
    end

    # What the clock read when it was last stopped.
    attr_reader :kills, :secrets, :treasures, :seconds, :seconds_played

    # One pass of a floor being played.
    def tick
      @passes += 1
    end

    # A floor started again takes its clock with it.
    def start_floor
      @passes = 0
    end

    # THE FLOOR IS OVER: read the clock, whole seconds and rounded down.
    def stop_clock
      @seconds_played = @passes / PASSES_PER_SECOND
      @seconds_played = MOST_SECONDS if @seconds_played > MOST_SECONDS
    end

    # A NEW GAME FORGETS THE LAST ONE'S FLOORS.
    def start_again
      @b.repeat(FLOORS) do |n|
        @kills[n] = 0
        @secrets[n] = 0
        @treasures[n] = 0
        @seconds[n] = 0
      end
    end

    # THE FLOOR IN SLOT +map+ IS DONE, at these percentages, in the time on the stopped clock.
    def record(map, kill:, secret:, treasure:)
      @slot = map
      @kills[@slot] = kill
      @secrets[@slot] = secret
      @treasures[@slot] = treasure
      @seconds[@slot] = @seconds_played
    end
  end
end
