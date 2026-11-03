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
    def recording(_number, rate:) = (([60] * 40) + ([-60] * 40)).cycle.first(3500).pack("c*")
  end

  Floor = Data.define(:index)

  # Plays the first floor for ten frames and then the second.
  def game_with(setting:, tracks: HeldTracks.new(Music::GETTHEM, Music::SEARCHN))
    VBlank.game("MUSIC", consoles: %i[gba]) do
      enable_sound
      sound = var(:sound_setting, setting)
      music = Music.new(build: self, tracks: tracks, floors: [Floor.new(0), Floor.new(1)], setting: sound)
      frame = var(:_frame, 0)
      floor = var(:_floor_now, 0)
      game_loop do
        frame += 1
        floor = 1 if frame > 10
        music.update(music.floor_song(floor))
      end
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

  # The second floor's track is missing, so the song the first floor started plays on through it.
  def test_a_copy_without_a_track_plays_the_last_song_on
    program = game_with(setting: Music::EFFECTS_AND_MUSIC, tracks: HeldTracks.new(Music::GETTHEM))

    assert_includes heard(program).map(&:first), :song
  end

  def test_a_build_with_no_tracks_plays_no_music
    refute_includes heard(game_with(setting: Music::EFFECTS_AND_MUSIC, tracks: nil)).map(&:first), :song
  end

  # A TRACK IN THE FILE, as AUDIOT lays it out: two bytes of length, the writes, and the composer's
  # notes after them. The shareware's missing tracks are only the notes.
  def audio_with_a_track_and_a_gap
    track = [0x20, 0x21, 7, 0xb0, 0x30, 9].pack("CCvCCv")
    held = [track.bytesize].pack("v") + track + ("x" * 86)
    gap = [0].pack("v") + ("x" * 86)
    first = Wolf3D::AdlibMusic::FIRST_CHUNK
    offsets = Array.new(first, 0) + [0, held.bytesize, held.bytesize + gap.bytesize]
    Wolf3D::AdlibMusic.new(head: offsets.pack("V*"), audio: held + gap)
  end

  def test_a_track_reads_as_register_value_and_wait
    assert_equal [[0x20, 0x21, 7], [0xb0, 0x30, 9]], audio_with_a_track_and_a_gap.writes(0)
  end

  def test_a_slot_the_copy_left_empty_reads_as_nothing
    assert_empty audio_with_a_track_and_a_gap.writes(1)
  end

  def test_a_number_past_the_end_of_the_file_reads_as_nothing
    assert_empty audio_with_a_track_and_a_gap.writes(2)
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
