# frozen_string_literal: true

require_relative "test_helper"

# THE EFFECTS THAT ARE RECIPES, HEARD. Where each is played is the original's (wl_agent.cpp,
# wl_act1.cpp), and a wall waiting for silence is ClipMove's.
class TestAdlibEffectsInPlay < Minitest::Test
  include Wolf3DTest

  Sounds = Wolf3D::Sounds
  HIT_WALL = :"adlib_#{Sounds::ADLIB_EFFECT_NUMBERS.fetch(:hit_wall)}".freeze
  NO_WAY = :"adlib_#{Sounds::ADLIB_EFFECT_NUMBERS.fetch(:no_way)}".freeze
  AMMO = :"adlib_#{Sounds::ADLIB_EFFECT_NUMBERS.fetch(:ammo)}".freeze
  KNIFE = :"adlib_#{Sounds::ADLIB_EFFECT_NUMBERS.fetch(:knife)}".freeze
  CLIP_PIECE = 26
  FRAMES = 120

  def fixture = @fixture ||= Wolf3D::Fixture::Release.new(adlib: Sounds::ADLIB_EFFECT_NUMBERS.values)

  def adlib(release = fixture) = Wolf3D::AdlibSounds.new(head: release.files["AUDIOHED"], audio: release.files["AUDIOT"])

  # What sounded on each frame of a run.
  def frames_heard(level, frames: FRAMES, adlib_sounds: adlib, keys: ->(_frame) { [:up] }, **options)
    program = view_of(level, drawing: false, adlib: adlib_sounds, **options)
    heard = []
    player = Reference.new
    player.input_each_frame do |frame|
      heard << player.active_samples.uniq
      keys.call(frame)
    end
    player.run(program, frames: frames)
    heard
  end

  def heard(...) = frames_heard(...).flatten.uniq

  def locked_door_ahead = arena(player: [9, 8], walls: (1..14).map { |y| [10, y] } - [[10, 8]],
                                cells: { [10, 8] => Wolf3D::Level::LOCKED_DOORS.first })

  def test_walking_into_a_wall_is_heard
    assert_includes heard(arena(player: [14, 8])), HIT_WALL
  end

  def test_walking_in_the_open_is_not
    refute_includes heard(arena(player: [2, 8]), frames: 20), HIT_WALL
  end

  def test_a_locked_door_says_no
    assert_includes heard(locked_door_ahead, keys: ->(frame) { frame == 3 ? [:a] : [] }), NO_WAY
  end

  def test_picking_up_a_clip_is_heard
    assert_includes heard(arena(player: [8, 8], ahead: [CLIP_PIECE]), frames: 40), AMMO
  end

  def test_a_knife_swing_at_nothing_is_heard
    swing = ->(frame) { frame == 3 ? [:b] : [] }

    assert_includes heard(arena, keys: swing, armed_with: Wolf3D::Weapons::KNIFE), KNIFE
  end

  # ClipMove plays the wall only with nothing sounding, so a wall cannot cut a pickup short.
  def test_a_wall_waits_for_a_pickup_to_finish
    near_a_wall = arena(player: [13, 8], ahead: [CLIP_PIECE])
    sounding = frames_heard(near_a_wall)
    ammo_frames = sounding.count { |names| names.include?(AMMO) }
    first_ammo = sounding.index { |names| names.include?(AMMO) }
    first_wall = sounding.index { |names| names.include?(HIT_WALL) }

    assert_operator ammo_frames, :>=, 5, "the whole of it is heard"
    assert_operator first_wall, :>, first_ammo + ammo_frames - 1
  end

  # The count of what is sounding keeps real time, so three frames to a pass take three off it.
  def test_the_count_of_a_sounding_effect_goes_by_the_frame
    level = arena(player: [8, 8], ahead: [CLIP_PIECE])
    program = view_of(level, drawing: false, adlib: adlib)
    walking = Reference.new.input_each_frame { [:up] }
    fast = walking.run(program, frames: 40)[:_adlib_frames_left]
    slow = Reference.new.input_each_frame { [:up] }.frames_each_pass { 3 }.run(program, frames: 22)[:_adlib_frames_left]

    assert_operator fast, :>=, 0
    assert_operator slow, :>=, 0
    assert_operator slow, :<=, fast, "more frames have gone by in the same walk"
  end

  def test_the_menu_switch_silences_them
    assert_empty heard(arena(player: [14, 8]), sound: 0)
  end

  def test_a_copy_without_the_recipes_builds_and_stays_quiet
    assert_empty heard(arena(player: [14, 8]), adlib_sounds: adlib(Wolf3D::Fixture::Release.new))
  end

  def test_a_copy_missing_one_plays_the_others
    held = Wolf3D::Fixture::Release.new(adlib: [Sounds::ADLIB_EFFECT_NUMBERS.fetch(:ammo)])
    sounds = heard(arena(player: [13, 8], ahead: [CLIP_PIECE]), adlib_sounds: adlib(held))

    assert_equal [AMMO], sounds
  end
end
