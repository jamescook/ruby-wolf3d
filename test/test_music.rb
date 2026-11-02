# frozen_string_literal: true

require_relative "test_helper"

# THE MUSIC, heard the way the game asks for it. The songs here are made up, so no copy of the game
# is needed, and which song goes where is the original's own table (`songs` in wl_play.cpp).
class TestMusic < Minitest::Test
  include Wolf3DTest

  Music = Wolf3D::Music

  # Stands where AdlibMusic does: every track it holds is half a second of a square wave.
  class HeldTracks
    def initialize(*numbers) = @numbers = numbers
    def writes(number) = @numbers.include?(number) ? [[0, 0, 0]] : []
    def recording(_number, renderer:) = (([60] * 40) + ([-60] * 40)).cycle.first(3500).pack("c*")
  end

  Floor = Data.define(:index)

  def game_with(setting:, tracks: HeldTracks.new(Music::GETTHEM, Music::SEARCHN), floors: [Floor.new(0), Floor.new(1)], which: 0)
    VBlank.game("MUSIC", consoles: %i[gba]) do
      enable_sound
      sound = var(:sound_setting, setting)
      music = Music.new(build: self, tracks: tracks, floors: floors, setting: sound)
      floor = var(:floor_now, which)
      game_loop { music.update(music.floor_song(floor)) }
    end.program
  end

  def heard(program)
    run = Reference.new
    run.run(program, frames: 30)
    run.sound_owners
  end

  def test_with_music_on_a_song_sounds
    assert_includes heard(game_with(setting: Music::EFFECTS_AND_MUSIC)).map(&:first), :song
  end

  def test_with_effects_only_no_song_sounds
    refute_includes heard(game_with(setting: Music::EFFECTS_ONLY)).map(&:first), :song
  end

  def test_with_sound_off_no_song_sounds
    refute_includes heard(game_with(setting: Music::OFF)).map(&:first), :song
  end

  def test_a_copy_without_a_track_is_left_without_it
    built = {}
    VBlank.game("MUSIC", consoles: %i[gba]) do
      enable_sound
      sound = var(:sound_setting, 2)
      music = Music.new(build: self, tracks: HeldTracks.new(Music::GETTHEM), floors: [Floor.new(0), Floor.new(1)], setting: sound)
      built[:held] = music.song(Music::GETTHEM)
      built[:missing] = music.song(Music::SEARCHN)
      game_loop { music.update(0) }
    end.program

    assert_equal 0, built[:held]
    assert_equal 1, built[:missing], "past the end of the list of one, which names no song"
  end

  def test_a_build_with_no_tracks_plays_no_music
    refute_includes heard(game_with(setting: Music::EFFECTS_AND_MUSIC, tracks: nil)).map(&:first), :song
  end

  # The first episode's floors, by wl_play.cpp: four themes twice over, the boss, the secret floor.
  def test_each_floor_of_the_first_episode_has_the_originals_song
    assert_equal [Music::GETTHEM, Music::SEARCHN, Music::POW, Music::SUSPENSE], Music::FLOOR_SONGS.first(4)
    assert_equal Music::WARMARCH, Music::FLOOR_SONGS[8]
    assert_equal Music::CORNER, Music::FLOOR_SONGS[9]
    assert_equal 60, Music::FLOOR_SONGS.length
    assert_equal Music::FUNKYOU, Music::FLOOR_SONGS.last
  end
end
