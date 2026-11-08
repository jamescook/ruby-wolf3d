# frozen_string_literal: true

module Wolf3D
  # ONE PLANE OF A FLOOR, UNPACKED BY THE GAME ITSELF: what Maps reads in Ruby while building, done
  # as game code so a shell can do it on the player's machine at LOAD ROM (VBlank's data pack).
  #
  # A plane in GAMEMAPS is squeezed twice, Carmack over RLEW (wolf4sdl id_ca.cpp, CA_CacheMap:
  # CAL_CarmackExpand, then CA_RLEWexpand), so it comes back the other way round. Carmack's copies
  # point back into what it has already made, so what it makes is kept here, in a list of the
  # routine's own, and RLEW reads that list into the slot. Both carry how long they expand to in
  # their first word. The two codecs are lib/id_software/codec, the answer key for this.
  #
  #   gamemaps.unpack_map_plane at: where, into: pack[:walls], start: cells * 2 * floor, tag: rlew_tag
  #
  # Each cell is two bytes in the slot, low byte first. This file is game code
  # (VBlank.require_game_file): each `if` here is a branch of the routine.
  module MapPlaneFormat
    extend VBlank::Original::Packing::Format
    unpacks :map_plane, tag: 0xABCD
    called "a Wolfenstein map plane (Carmack over RLEW)"

    NEAR = IdSoftware::Codec::Carmack::NEAR
    FAR = IdSoftware::Codec::Carmack::FAR

    # The most words Carmack may make for one plane: what RLEW squeezed a 64 by 64 plane to, which at
    # worst is three words a cell (a lone word equal to the tag is written as a run of one), plus the
    # word that says how long it expands to. A longer one is refused.
    MOST_WORDS = (64 * 64 * 3) + 1

    def self.routine(block)
      at = block.variable(:at)
      words = block.variable(:words)
      made = block.variable(:made)
      word = block.variable(:word)
      count = block.variable(:count)
      back = block.variable(:back)
      cell = block.variable(:cell)
      made_words = block.list(:carmack_words, capacity: MOST_WORDS, width: :half)

      at.store!(block.from)
      words.store!((block.byte(at) | (block.byte(at + 1) << 8)) >> 1)
      at.increase!(2)
      made.store!(0)
      block.emit_wrong_format_fault if words > MOST_WORDS

      # CARMACK: a word whose high byte is NEAR or FAR is a copy of +count+ words from earlier, from a
      # byte's worth of words back or from a word's place; a count of nought is a plain word whose
      # high byte happens to be a marker, its low byte the next byte.
      block.repeat(MOST_WORDS, stop_when: (made >= words) | block.finished) do
        word.store!(block.byte(at) | (block.byte(at + 1) << 8))
        at.increase!(2)
        count.store!(word & 0xFF)
        if ((word >> 8) == NEAR || (word >> 8) == FAR) && count == 0
          made_words[made] = (word & 0xFF00) | block.byte(at)
          at.increase!(1)
          made.increase!(1)
        elsif (word >> 8) == NEAR
          back.store!(made - block.byte(at))
          at.increase!(1)
          block.repeat(count, stop_when: made >= words) do
            made_words[made] = made_words[back]
            made.increase!(1)
            back.increase!(1)
          end
        elsif (word >> 8) == FAR
          back.store!(block.byte(at) | (block.byte(at + 1) << 8))
          at.increase!(2)
          block.repeat(count, stop_when: made >= words) do
            made_words[made] = made_words[back]
            made.increase!(1)
            back.increase!(1)
          end
        else
          made_words[made] = word
          made.increase!(1)
        end
      end

      # RLEW: the tag word, then how many, then the word repeated; any other word is itself. The list
      # gives a word back signed, so a word with its top bit set (the tag, 0xABCD) is masked to what
      # was written.
      block.expect_size(made_words[0] & 0xFFFF)
      cell.store!(1)
      block.repeat(MOST_WORDS, stop_when: (cell >= words) | block.finished) do
        word.store!(made_words[cell] & 0xFFFF)
        if word == block.setting(:tag)
          block.repeat(made_words[cell + 1] & 0xFFFF, stop_when: block.finished) do
            block.write(made_words[cell + 2])
            block.write(made_words[cell + 2] >> 8)
          end
          cell.increase!(3)
        else
          block.write(word)
          block.write(word >> 8)
          cell.increase!(1)
        end
      end
    end
  end
end
