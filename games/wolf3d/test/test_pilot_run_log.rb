# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "stringio"

# WHAT THE RUN LOG SAYS HAPPENED, given what the game showed frame by frame. The game is the same
# stand-in test_pilot.rb uses: a player in the middle of a cell and men at places of their own.
class TestPilotRunLog < Minitest::Test
  include Wolf3DTest

  Pilot = Wolf3D::Pilot
  START = { screen: Wolf3D::Menus::PLAYING, floor: 0, lives: 3, view: 0, health: 100, ammo: 50, keys: 0, weapon: 1,
            weapon_best: 1, weapon_stage: -1 }.freeze

  # What the cartridge would answer on one frame. +men+ are [x, y, hit points].
  class Frame
    def initialize(at:, men:, **player)
      @vars = START.merge(player, px: at[0] + 0.5, py: at[1] + 0.5)
      @men = men
    end

    def var(name) = @vars.fetch(name)
    def list(_name) = []

    def pool(_name, field)
      case field
      when :x then @men.map { |x, _, _| x + 0.5 }
      when :y then @men.map { |_, y, _| y + 0.5 }
      when :hp then @men.map { |_, _, hit_points| hit_points }
      else @men.map { 0 }
      end
    end
  end

  # A field with a guard who starts three cells east of the player.
  def level = @level ||= arena(guards: [[11, 8, :west]], player: [8, 8])

  # Plays +frames+, each a Hash of what changes from the start, and answers the events written.
  def log_of(*frames)
    io = StringIO.new
    log = Pilot::RunLog.new(io, about: { seed: 4 })
    report = Wolf3D::FloorReport.new(level)
    frames.each_with_index do |frame, n|
      game = Frame.new(at: [8, 8], men: [[11, 8, 25]], **frame)
      log.record(game, floor: 0, level: level, report: report, frame: n + 1, tactic: :fight_from_cover, difficulty: 3)
    end
    io.string.lines.map { |line| JSON.parse(line) }
  end

  def events(log, kind) = log.select { |event| event["event"] == kind }

  def test_the_run_and_the_floor_start_are_written_first
    log = log_of({})

    assert_equal [%w[run 4 hard], ["floor_start", 1, 100, 50]],
                 [log[0].values_at("event", "seed", "difficulty").map(&:to_s), log[1].values_at("event", "floor", "health", "ammo")]
  end

  def test_a_wound_names_the_man_with_a_line_by_his_kind_and_starting_cell
    wound = events(log_of({}, { health: 70 }), "wound").first

    assert_equal [30, "fight_from_cover", "guard", [11, 8], 3.0],
                 [wound["damage"], wound["tactic"], wound.dig("by", "kind"), wound.dig("by", "home"), wound.dig("by", "distance")]
  end

  def test_a_round_that_takes_hit_points_is_a_hit
    hit = { ammo: 49, men: [[11, 8, 20]] }
    shots = events(log_of({}, hit, *Array.new(Pilot::RunLog::SHOT_FRAMES + 1) { hit }), "shot")

    assert_equal [[true, 3.0]], shots.map { |shot| shot.values_at("hit", "distance") }
  end

  def test_a_round_that_takes_nothing_is_a_miss
    spent = { ammo: 49 }
    shots = events(log_of({}, spent, *Array.new(Pilot::RunLog::SHOT_FRAMES + 1) { spent }), "shot")

    assert_equal [false], shots.map { |shot| shot["hit"] }
  end

  def test_a_man_at_nought_is_a_kill
    kills = events(log_of({}, { men: [[11, 8, 0]] }), "kill")

    assert_equal [["guard", [11, 8]]], kills.map { |kill| kill.values_at("kind", "home") }
  end

  def test_bj_at_nought_is_a_death_by_the_man_who_shot_last
    deaths = events(log_of({}, { health: 0 }), "death")

    assert_equal [["guard", [11, 8]]], deaths.map { |death| death["by"].values_at("kind", "home") }
  end

  def test_a_death_starts_the_floor_again
    log = log_of({}, { health: 0 }, { lives: 2 })

    assert_equal [3, 2], events(log, "floor_start").map { |start| start["lives"] }
  end
end
