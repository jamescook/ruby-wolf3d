# frozen_string_literal: true

require_relative "test_helper"

# The codecs against the world rather than against themselves; the repository's test/test_codec.rb
# holds them to their own bytes. Skips without a copy of the game.
class TestCodecAgainstRealMaps < Minitest::Test
  include Wolf3DTest

  def test_every_level_expands_to_a_64_by_64_grid_and_round_trips
    data = game_data_or_skip
    maphead = data.read("MAPHEAD")
    gamemaps = data.read("GAMEMAPS")
    rlew = IdSoftware::Codec::RLEW.new(tag: maphead[0, 2].unpack1("v"))
    offsets = maphead[2..].unpack("V*").take_while(&:positive?)

    refute_empty offsets

    offsets.each_with_index do |off, level|
      head = gamemaps[off, 42]
      plane_offs = head[0, 12].unpack("V3")
      plane_lens = head[12, 6].unpack("v3")

      (0..1).each do |plane|
        packed = gamemaps[plane_offs[plane], plane_lens[plane]]
        carmacked = IdSoftware::Codec::Carmack.expand(packed)
        grid = rlew.expand(carmacked[2..])

        assert_equal 8192, grid.bytesize, "level #{level} plane #{plane}"
        assert_equal 8192, carmacked[0, 2].unpack1("v"), "level #{level} plane #{plane} header"
        assert_equal grid, rlew.expand(rlew.compress(grid))
      end
    end
  end
end
