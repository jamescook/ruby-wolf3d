# frozen_string_literal: true

# EVERYTHING HERE KNOWS NOTHING ABOUT ONE GAME. The three compressions id Software's DOS games
# keep their data in: RLEW and Carmack over a map's words, Huffman over its pictures and text.
# Wolfenstein 3D, Spear of Destiny and Blake Stone read them the same way, and none of them is
# named here. What belongs to Wolfenstein 3D is in games/wolf3d/.
module IdSoftware
end

require_relative "id_software/codec/rlew"
require_relative "id_software/codec/carmack"
require_relative "id_software/codec/huffman"
