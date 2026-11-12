# frozen_string_literal: true

require_relative "../test_helper"

# BOTH REAL COPIES UNPACKED WHOLE BY THE GAME ITSELF, every slot held to the Ruby readers and every
# song to Opl2Track: the check of the data pack against the world. Unpacking a whole copy plays all
# its music through the chip, which is minutes, so this runs with `rake e2e`, not `rake test`.
class TestWholeCopiesUnpack < Minitest::Test
  include Wolf3DTest
  include UnpackedPack

  # A real copy's status bar and shortened title too, which the made-up release's plate is not
  # painted to be measured for.
  def test_the_six_episodes_unpack_as_the_readers_read_them
    pack = unpacked(original_of(real_copy))
    assert_unpacked_as_read Wolf3D.maps, Wolf3D.vswap, Wolf3D.vgagraph, pack
    assert_same_adlib_effects Wolf3D.adlib, pack
    assert_same_music Wolf3D::AdlibMusic.from(real_copy), pack, played: songs_held(Wolf3D::AdlibMusic.from(real_copy))
    assert_same_bar Wolf3D.vgagraph, pack
    assert_same_screens Wolf3D.vgagraph, pack
  end

  # The shareware's ten floors fill the same slots, and the pack says it has ten.
  def test_the_shareware_unpacks_as_the_readers_read_it
    data = real_shareware
    graph = Wolf3D::Vgagraph.from(data)
    pack = unpacked(original_of(data))
    assert_unpacked_as_read Wolf3D::Maps.from(data), Wolf3D::Vswap.from(data), graph, pack
    assert_same_adlib_effects Wolf3D::AdlibSounds.from(data), pack
    assert_same_music Wolf3D::AdlibMusic.from(data), pack, played: songs_held(Wolf3D::AdlibMusic.from(data))
    assert_same_bar graph, pack
    assert_same_screens graph, pack
  end

  private

  # Every song a whole build holds that +music+ has a track for.
  def songs_held(music) = Wolf3D::MusicUnpacking.numbers.reject { |number| music.writes(number).empty? }
end
