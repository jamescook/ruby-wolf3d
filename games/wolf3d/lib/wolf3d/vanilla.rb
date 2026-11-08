# frozen_string_literal: true

module Wolf3D
  # WHICH COPIES OF THE GAME THIS BUILDS FROM: version 1.4 of the registered six episodes, in the
  # edition GOG sells, and version 1.4 of the shareware episode.
  #
  # Files with the right names are not enough. Much of what this game knows about the files is not
  # in the files: it is a number read off one release, like which picture is the status bar, where
  # the first guard starts, which recording is a scream, and all 256 colours. Spear of Destiny has
  # the same eight files with four more sprites before its first guard, which puts a marble pillar
  # where this game expects him.
  #
  # THE SHAREWARE SHARES NEARLY ALL OF THIS WITH THE SIX EPISODES: the same walls, sprites, sounds
  # and colours, and fewer floors. What differs is its pictures, because Apogee's list has twelve
  # more help screens early in VGAGRAPH, so every number after those moves. Compare gfxv_apo.h with
  # gfxv_wl6.h in the original's source; version.h and wl_def.h say which build reads which.
  #
  # A COPY IS KNOWN BY ITS FILES' SHA-1, each of the eight, so the build and the shell's LOAD ROM
  # (VBlank::Original::Shell) accept exactly the same copies, and an edited or other copy is refused
  # naming the first file that differs. Another store's copy of the same release, if its files
  # differ, is one more entry here, read off that copy.
  module Vanilla
    # Each file of a release, its SHA-1 and its size in bytes, as VBlank's Original::Game takes them.
    # Read off GOG's six episodes and wolf3dsw, the shareware, both version 1.4.
    RELEASES = Ractor.make_shareable(
      { "WL6" => { "files" => {
          "VSWAP.WL6" => { "sha1" => "e604f436f31a456b003e99f8a3d14fe3ecdcec23", "size" => 1_544_376 },
          "GAMEMAPS.WL6" => { "sha1" => "22bfcde221efec232b48258117d7fc04337cce3a", "size" => 150_652 },
          "MAPHEAD.WL6" => { "sha1" => "1b5bf23e6edae13f6a582a44f72729c6e5a0e692", "size" => 402 },
          "VGAGRAPH.WL6" => { "sha1" => "f04ee31c8193d4cdc2dd48a6bf34445345652d68", "size" => 275_774 },
          "VGADICT.WL6" => { "sha1" => "4883109b6e3b9eb989fbadaff456410522f3e843", "size" => 1024 },
          "VGAHEAD.WL6" => { "sha1" => "19444414fe3e7b1ceb95a8cfd60a8ac54c69daaf", "size" => 450 },
          "AUDIOT.WL6" => { "sha1" => "8a1e19ec1dc669ebe6916b1e24a261d10d9d5ff3", "size" => 320_209 },
          "AUDIOHED.WL6" => { "sha1" => "2a8407cd436250b6df9d6022c971030882ae37ca", "size" => 1156 }
        } },
        "WL1" => { "files" => {
          "VSWAP.WL1" => { "sha1" => "63134a2e3165b5291ece7b8a4145d2bd67d4f787", "size" => 742_912 },
          "GAMEMAPS.WL1" => { "sha1" => "d49fc8a7887d7e73be7c813177307b68206f8147", "size" => 27_425 },
          "MAPHEAD.WL1" => { "sha1" => "b3942ddb4f6bb671b026a3f85611bf314acefce7", "size" => 402 },
          "VGAGRAPH.WL1" => { "sha1" => "3ad077aca0e775bd6a241515c8b2874d4fa4099a", "size" => 326_568 },
          "VGADICT.WL1" => { "sha1" => "10ae325f5ce124d2536a63805023c56a4e438ea1", "size" => 1024 },
          "VGAHEAD.WL1" => { "sha1" => "a9ba5551f54f88d810b9aa82a15caae623509a4c", "size" => 471 },
          "AUDIOT.WL1" => { "sha1" => "0254cc09b7a8ab0b884766b5dcd0e8555c424937", "size" => 132_613 },
          "AUDIOHED.WL1" => { "sha1" => "732460795d77cab19c8018d879f5c27a3cbd5f84", "size" => 1156 }
        } } }
    )

    # The extensions this game takes, for a message that has to name them.
    SETS = Ractor.make_shareable(RELEASES.keys.join(" or "))

    # What to get, for every message that has to say so.
    NEEDED = Ractor.make_shareable(
      "This game can use only two releases of Wolfenstein 3D, both version 1.4. " \
      "One is the registered six episodes (WL6), which GOG sells. " \
      "The other is the shareware episode (WL1), which is a free download."
    )
  end
end
