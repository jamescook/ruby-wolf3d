# frozen_string_literal: true

require_relative "test_helper"

# THE FLOORS WORKED OUT BY THE GAME ITSELF (FloorUnpacking), into a whole build's data pack, held to
# what the Ruby readers work out while a trimmed build is made: Maps for the planes, and Doors,
# Pushwalls and Elevator for what each cell means to the walk. The made-up release has a door, a
# wall that moves and a key in one room; e2e/test_whole_copies_unpack holds both real copies.
class TestFloorUnpacking < Minitest::Test
  include Wolf3DTest
  include UnpackedPack

  def test_the_made_up_release_unpacks_as_the_readers_read_it
    Dir.mktmpdir do |dir|
      # The second sound left out, as the shareware leaves out the lift's.
      release = Wolf3D::Fixture::Release.new(set: "WL6", left_out: [1])
      release.write(dir)
      maps = Wolf3D::Maps.new(maphead: release.files["MAPHEAD"], gamemaps: release.files["GAMEMAPS"])
      pack = unpacked(made_up_original(dir))

      assert_unpacked_as_read maps, Wolf3D::Vswap.new(release.files["VSWAP"]), release.pictures, pack
      assert_same_adlib_effects Wolf3D::AdlibSounds.new(head: release.files["AUDIOHED"], audio: release.files["AUDIOT"]), pack
    end
  end

  # A COPY DAMAGED WHERE A PLACE POINTS OUTSIDE ITS FILE, or outside its page, unpacks nothing from
  # that place rather than reading whatever the copy holds after it, and the rest of the pack is
  # unpacked as the readers read the undamaged copy. One damaged file a case, so a guard that fails
  # cannot hide another.
  #
  # Its floor's walls said to start past the end of GAMEMAPS: no floor the routine can read.
  def test_a_floor_past_gamemaps_is_not_unpacked
    pack, release = unpacked_with_damage("GAMEMAPS.WL6") do |maps, dir|
      level_at = File.binread(File.join(dir, "MAPHEAD.WL6"))[2, 4].unpack1("V")
      maps[level_at, 4] = [maps.bytesize + 100].pack("V")
    end

    assert_equal 0, pack.fetch(:floor_count).getbyte(0), "a floor past GAMEMAPS"
    assert_same_walls Wolf3D::Vswap.new(release.files["VSWAP"]), pack
    assert_same_named_pictures release.pictures, pack
  end

  # Its first wall page said to start past the end of VSWAP: that page left at place nought.
  def test_a_wall_page_past_vswap_is_not_unpacked
    pack, release = unpacked_with_damage("VSWAP.WL6") do |vswap|
      vswap[Wolf3D::Vswap::HEADER_BYTES, 4] = [vswap.bytesize + 100].pack("V")
    end
    walls = pack.fetch(:wall_pictures)

    assert_equal [0], (0...SIDE).flat_map { |y| walls.byteslice(y * Wolf3D::Holding::WALL_PAGES * SIDE, SIDE).bytes }.uniq,
                 "a wall page past VSWAP"
    assert_same_sprites Wolf3D::Vswap.new(release.files["VSWAP"]), pack
    assert_same_world Wolf3D::Maps.new(maphead: release.files["MAPHEAD"], gamemaps: release.files["GAMEMAPS"]), pack
  end

  # Its first sprite's header naming columns outside its square: left see-through, with no edges.
  def test_a_sprite_past_its_page_is_not_unpacked
    pack, release = unpacked_with_damage("VSWAP.WL6") do |vswap|
      first_sprite = vswap[2, 2].unpack1("v")
      sprite_at = vswap[Wolf3D::Vswap::HEADER_BYTES + (4 * first_sprite), 4].unpack1("V")
      vswap[sprite_at + 2, 2] = [200].pack("v")
    end
    sprites = pack.fetch(:sprite_pictures)
    sprite_across = Wolf3D::Holding::SPRITES * SIDE

    assert_equal [Wolf3D::PictureUnpacking::SEE_THROUGH],
                 (0...SIDE).flat_map { |y| sprites.byteslice(y * sprite_across, SIDE).bytes }.uniq, "a sprite's columns"
    assert_equal [0, 0], [pack.fetch(:sprite_first_column).getbyte(0), pack.fetch(:sprite_last_column).getbyte(0)]
    assert_same_walls Wolf3D::Vswap.new(release.files["VSWAP"]), pack
  end

  # VGAGRAPH's picture table said by VGAHEAD to start past the file: a release of no pictures, so no
  # named picture, no shortened screen and no piece of the bar, while its fonts and the end of each
  # episode, chunks of their own, are read as ever.
  def test_a_picture_table_past_vgagraph_is_not_unpacked
    pack, release = unpacked_with_damage("VGAHEAD.WL6") do |head, dir|
      past = File.size(File.join(dir, "VGAGRAPH.WL6")) + 100
      head[0, Wolf3D::Vgagraph::OFFSET_BYTES] = [past].pack("V")[0, Wolf3D::Vgagraph::OFFSET_BYTES]
    end

    assert_equal 0, pack.fetch(:picture_count).unpack1("v"), "a chunk past VGAGRAPH"
    assert_equal [0], pack.fetch(:picture_sizes).unpack("v*").uniq
    %i[vga_pictures screen_pictures bar_pictures].each do |slot|
      assert_equal [0], pack.fetch(slot).bytes.uniq, "#{slot} with no pictures to make them of"
    end
    assert_same_fonts release.pictures, pack
    assert_same_end_articles release.pictures, pack
    assert_same_small_letters release.pictures, pack
  end

  # THE MADE-UP RELEASE'S ADLIB EFFECTS, two of those the game plays (the wall and the knife), played
  # through the chip by the routine as Opl2 plays them, and the rest it lacks left silent.
  def test_the_made_up_releases_adlib_effects_are_played_as_the_chip_plays_them
    Dir.mktmpdir do |dir|
      release = Wolf3D::Fixture::Release.new(set: "WL6", adlib: MADE_UP_EFFECTS)
      release.write(dir)
      adlib = Wolf3D::AdlibSounds.new(head: release.files["AUDIOHED"], audio: release.files["AUDIOT"])

      refute_nil adlib.recording(MADE_UP_EFFECTS.first), "the made-up effect should make a sound"
      assert_same_adlib_effects adlib, unpacked(made_up_original(dir))
    end
  end

  MADE_UP_EFFECTS = [0, 23].freeze

  # An effect said to start past the end of AUDIOT, and of every file after it: nothing is read
  # there, its room is left silent and its numbers nought, and the other effect is played as the
  # chip plays it.
  def test_an_effect_past_audiot_is_not_played
    first_chunk = Wolf3D::AdlibSounds::FIRST_CHUNK
    pack, release = unpacked_with_damage("AUDIOHED.WL6", adlib: MADE_UP_EFFECTS) do |head|
      head[4 * first_chunk, 8] = [PAST_THE_COPY, PAST_THE_COPY + 100].pack("V2")
    end
    adlib = Wolf3D::AdlibSounds.new(head: release.files["AUDIOHED"], audio: release.files["AUDIOT"])
    knife = Wolf3D::AdlibUnpacking.numbers.index(MADE_UP_EFFECTS.last)
    room = Wolf3D::AdlibUnpacking::ROOM[knife]
    pcm = samples_in_room(adlib.recording(MADE_UP_EFFECTS.last), room)

    assert_equal [0], pack.fetch(:adlib_samples).byteslice(0, Wolf3D::AdlibUnpacking::ROOM[0]).bytes.uniq, "the effect past AUDIOT"
    assert_equal [0, 0, 0], %i[adlib_length adlib_note_frames adlib_priority].map { |slot| pack.fetch(slot).unpack1("v") }
    assert_equal pcm + ([0] * (room - pcm.length)),
                 pack.fetch(:adlib_samples).unpack("c*")[Wolf3D::AdlibUnpacking::EFFECT_AT[knife], room], "the knife"
  end

  # THE MADE-UP RELEASE'S MUSIC, one track in the roster's place, played through the whole chip by
  # the routine as Opl2Track plays it: feedback, an additive channel, the deep wobbles, writes while
  # a note sounds. Every other song it lacks, so their rooms are silent and their lengths nought.
  def test_the_made_up_releases_music_is_played_as_the_chip_plays_it
    Dir.mktmpdir do |dir|
      release = Wolf3D::Fixture::Release.new(set: "WL6", music: [Wolf3D::Music::ROSTER_SONG])
      release.write(dir)
      music = Wolf3D::AdlibMusic.new(head: release.files["AUDIOHED"], audio: release.files["AUDIOT"])

      assert_same_music music, unpacked(made_up_original(dir)), played: [Wolf3D::Music::ROSTER_SONG]
    end
  end

  # A track said to start past the end of AUDIOT, and of every file after it: nothing is read there,
  # and its room is left silent and its length nought.
  def test_a_track_past_audiot_is_not_played
    chunk = Wolf3D::AdlibMusic::FIRST_CHUNK + Wolf3D::Music::ROSTER_SONG
    pack, = unpacked_with_damage("AUDIOHED.WL6", music: [Wolf3D::Music::ROSTER_SONG]) do |head|
      head[4 * chunk, 4] = [PAST_THE_COPY].pack("V")
    end
    roster = Wolf3D::MusicUnpacking.numbers.index(Wolf3D::Music::ROSTER_SONG)
    room = Wolf3D::MusicUnpacking.rooms[roster]

    assert_equal 0, pack.fetch(:music_length).unpack("V*")[roster]
    assert_equal [0], pack.fetch(:music_samples).byteslice(Wolf3D::MusicUnpacking.song_at[roster], room).bytes.uniq
  end
end
