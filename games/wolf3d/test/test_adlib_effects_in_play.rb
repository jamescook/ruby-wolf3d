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
    program = view_of(level, drawing: false, sounds_from: { adlib: adlib_sounds }, **options)
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
    program = view_of(level, drawing: false, sounds_from: { adlib: adlib })
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

  # ONCE AN EFFECT'S NOTES HAVE ENDED ANY EFFECT REPLACES IT, its fade and all: SD_PlaySound tests
  # the priority only against SoundPriority, which the chip's own count puts back to nought when the
  # notes run out (id_sd.cpp). The knife, of the higher priority, is asked for, and the wall long
  # after its notes and well inside its fade.
  def test_an_effect_fading_gives_way_to_a_lower_one
    program = VBlank.game("FADE", consoles: %i[gba]) do
      sounds = Wolf3D::Sounds.new(build: self, recordings: Wolf3D::Recordings::Baked.new(self, adlib: FADING_EFFECTS))
      frame = var(:_frame, 0)
      game_loop do
        frame += 1
        sounds.update
        sounds.play_adlib_named(:knife) if frame == 2
        sounds.play_adlib_named(:hit_wall) if frame == FADE_ASKED
      end
    end.program
    heard = []
    player = Reference.new
    player.input_each_frame do
      heard << player.active_samples.uniq
      []
    end
    player.run(program, frames: FADE_ASKED + 10)

    assert_includes heard[FADE_ASKED - 4], KNIFE, "the knife still fading when the wall is asked for"
    assert_includes heard.last, HIT_WALL
    refute_includes heard.last, KNIFE
  end

  FADE_ASKED = 30

  # Two effects, each a second of tone whose notes last five frames: the knife at priority 9, the
  # wall at nought.
  FADING_EFFECTS = Class.new do
    def recording(number)
      priority = { Sounds::ADLIB_EFFECT_NUMBERS.fetch(:knife) => 9, Sounds::ADLIB_EFFECT_NUMBERS.fetch(:hit_wall) => 0 }[number]
      return if priority.nil?

      Wolf3D::AdlibSounds::Recording.new(pcm: (([60] * 20) + ([-60] * 20)).cycle.first(Wolf3D::Opl2::RENDER_RATE),
                                          rate: Wolf3D::Opl2::RENDER_RATE, priority: priority, note_frames: 5)
    end
  end.new
end
