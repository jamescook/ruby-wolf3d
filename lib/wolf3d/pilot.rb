# frozen_string_literal: true

require_relative "pilot/sight"
require_relative "pilot/walker"
require_relative "pilot/supplies"
require_relative "pilot/gunfight"
require_relative "pilot/ambush"
require_relative "pilot/boss_fight"
require_relative "pilot/secret_plan"
require_relative "pilot/floor_play"

module Wolf3D
  # A PLAYER MADE OF RUBY: asked before each frame what to press, it reads the running game and
  # answers a list of buttons. tools/play_shareware.rb hands it to a playthrough, and every frame
  # goes on the tape, so the tape plays back with none of this present.
  #
  # IT KNOWS THE MAPS AND READS THE REST. FloorReport says how a floor can be finished, and the
  # running game says where the player is and who is alive. Everything is worked out again as it
  # plays, because a guard does what the random numbers say and no list of presses could answer him.
  #
  # IT PLAYS AS A PERSON WOULD, on the easiest setting or the hardest: walk the way out, open the
  # secret wall that hides a better gun, shoot whoever is in sight, fetch what is near and needed. It
  # presses buttons and nothing else, so what it finishes a person can finish.
  #
  # IT TAKES A PERSON'S TIME TO REACT. It has every man's place to the pixel, so left to itself it
  # shoots through the first crack of a door. So it looks through a door only when the door is right
  # open, it walks on for a moment after a man comes into sight, and it fires at once only when he is
  # on top of it or has just hurt it.
  #
  # This class is the menus and the count of passes. Each floor, and each life on it, is a FloorPlay,
  # and what that holds is in pilot/.
  class Pilot
    # The game is over and there is nothing left to steer.
    class Lost < StandardError; end

    # On the menus, frames between two presses of a button read on its edge, and how many it stays
    # down.
    MENU_PRESS_EVERY_FRAMES = 24
    PRESS_FRAMES = 2

    # IT DECIDES ONCE A PASS, because a pass is what the world moves by, and a pass takes two or three
    # frames on a cartridge and one anywhere else. Counted in passes, what it does is the same on every
    # way of running. A flag that flips every pass says when one has gone by. The world stands still
    # for the lift, so this many frames with no flip counts as a pass as well.
    PASS_FLAG = :_gturn
    MOST_FRAMES_A_PASS = 8

    # The original's four settings, top row first (gd_baby and the rest, in wl_def.h).
    DIFFICULTY_NAMES = %w[baby easy medium hard].freeze
    HARDEST_DIFFICULTY = DIFFICULTY_NAMES.length - 1

    # The difficulty screen starts on its top row, and each row down is one press. It fades in first,
    # and it reads a press on a pass that can take a few frames, so each press is held and spaced.
    DIFFICULTY_SETTLE_FRAMES = 40
    DIFFICULTY_PRESS_FRAMES = 4
    DIFFICULTY_PRESS_SPACING = 24

    # How long a person stays on each screen after the win. It is long enough to read a page.
    ENDING_SCREEN_FRAMES = 600

    # +maps+ are the floors of the copy on the cartridge, in the order they are played.
    # +difficulty+ is the row of the difficulty screen, counted from nought. +log+ is told each floor
    # that starts and each death.
    def initialize(maps, difficulty: 0, log: $stderr)
      @difficulty = difficulty
      @log = log
      @levels = Array.new(maps.count) { |n| maps[n] }
      @reports = @levels.map { |level| FloorReport.new(level) }
      @scenery = @levels.map { |level| Scenery.new(level) }
      @frame = 0
      @pass = 0
      @frames_on_pass = 0
      @buttons = []
      @difficulty_frames = 0
    end

    # What to hold for the next frame, or :done on the screen that says you won.
    def buttons_for(game)
      @frame += 1
      screen = game.var(:screen)
      return :done if screen == Menus::WINNING
      return menu_buttons(screen) unless screen == Menus::PLAYING
      return press_periodically(:a) if tally_showing?(game)

      floor = game.var(:floor)
      lives = game.var(:lives)
      raise Lost, "The pilot lost its last life on floor #{floor + 1}, on frame #{@frame}." if lost?(game)

      # Dying puts the floor back as it was, and a life won by score or by a pickup changes nothing.
      if floor != @floor || lives < @lives
        report_floor(game, floor, lives)
        begin_floor(floor)
      end
      @lives = lives
      return [] if game.var(:health) <= 0
      return @buttons unless advance_pass(game)

      @buttons = @floor_play.choose_buttons(game, pass: @pass)
    end

    # What to hold on the screens after the win, which a person reads before pressing on, or :done
    # when they are over: the summary, then each page of the article the episode ends on.
    def ending_buttons(game)
      @frame += 1
      return :done unless [Menus::WINNING, Menus::ARTICLE].include?(game.var(:screen))

      press_periodically(:a, every: ENDING_SCREEN_FRAMES)
    end

    private

    # Counts one frame, and says whether it began a new pass.
    def advance_pass(game)
      flag = game.var(PASS_FLAG)
      @frames_on_pass += 1
      return false if flag == @pass_flag && @frames_on_pass < MOST_FRAMES_A_PASS

      @pass_flag = flag
      @frames_on_pass = 0
      @pass += 1
      true
    end

    # A won game ends through the same flag as a lost one.
    def lost?(game) = game.var(:game_over) != 0 && game.var(:episode_won).zero?

    # A cartridge of one floor has no screen between floors.
    def tally_showing?(game)
      game.var(:_tally_showing) != 0
    rescue ArgumentError
      false
    end

    def menu_buttons(screen)
      return press_periodically(:a) unless screen == Menus::DIFFICULTY && @difficulty.positive?

      @difficulty_frames += 1
      waited = @difficulty_frames - DIFFICULTY_SETTLE_FRAMES
      return [] if waited.negative?
      return press_periodically(:a) if waited >= @difficulty * DIFFICULTY_PRESS_SPACING

      (waited % DIFFICULTY_PRESS_SPACING) < DIFFICULTY_PRESS_FRAMES ? [:down] : []
    end

    def press_periodically(button, every: MENU_PRESS_EVERY_FRAMES) = (@frame % every) < PRESS_FRAMES ? [button] : []

    def report_floor(game, floor, lives)
      lives_left = lives == 1 ? "1 life" : "#{lives} lives"
      @log.puts(if floor == @floor
                  "BJ died on floor #{floor + 1}: #{lives_left} left"
                else
                  "floor #{floor + 1} starts: #{lives_left}, health #{game.var(:health)}, ammo #{game.var(:ammo)}"
                end)
    end

    def begin_floor(floor)
      @floor = floor
      @buttons = []
      @floor_play = FloorPlay.new(level: @levels.fetch(floor), report: @reports.fetch(floor), scenery: @scenery.fetch(floor),
                                  hardest: @difficulty == HARDEST_DIFFICULTY)
    end
  end
end
