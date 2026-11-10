# frozen_string_literal: true

module Wolf3D
  # WHERE A BUILD'S DATA COMES FROM, chosen once where the build is set up and handed to every part of
  # the game that draws or reads it.
  #
  # A TRIMMED BUILD BAKES IT (Baked): the Ruby readers work everything out from the copy while the
  # cartridge is built, and the cartridge holds just what it needs. A WHOLE BUILD TAKES IT FROM ITS
  # DATA PACK (Packed): the unpacking routine fills the pack from the copy, as an all-in-one build is
  # made or in a shell at LOAD ROM, and the parts read the pack's slots.
  #
  # Each answer is one part's adapter, the same interface either way, so a part never asks which
  # kind of build it is in:
  # - floor_tables(build, floors:, wall_picture:): FloorTables. +wall_picture+ answers where a wall
  #   code's lit picture sits in the row of pictures, counting from one (FirstPerson#wall_picture); a
  #   baked world is made with it.
  # - view_pictures(build): ViewPictures, the walls, the things and the gun.
  # - bar_pictures(build, art:): BarPictures, the status bar's.
  # - menu_pictures(build, art:, palette:): MenuPictures, the menus' and the big lettering's.
  # - small_letter_pictures(build, art:, palette:): SmallLetterPictures.
  # - alphabets(build, art:): Alphabets, the menus' two proportional fonts.
  # - article_pages(build, art:, letters:, floors:): ArticlePages, the articles an episode ends on.
  module Source
    # EVERYTHING WORKED OUT IN RUBY, while building.
    class Baked
      def floor_tables(build, floors:, wall_picture:) = FloorTables::Baked.new(build, floors, wall_picture)
      def view_pictures(build) = ViewPictures::Baked.new(build)
      def bar_pictures(build, art:) = BarPictures::Baked.new(build, art)
      def menu_pictures(build, art:, palette:) = MenuPictures::Baked.new(build, art, palette)
      def small_letter_pictures(build, art:, palette:) = SmallLetterPictures::Baked.new(build, art, palette)
      def alphabets(build, art:) = Alphabets::Baked.new(build, art)

      def article_pages(build, art:, letters:, floors:)
        ArticlePages::Baked.new(build, art, letters, floors)
      end
    end

    # Holds nothing, so every part that is handed no source can share this one.
    BAKED = Ractor.make_shareable(Baked.new)

    # EVERYTHING READ FROM THE DATA PACK, whose handle is +pack+ (DataPack.declare).
    class Packed
      def initialize(pack)
        @pack = pack
      end

      def floor_tables(build, floors:, wall_picture:) = FloorTables::Packed.new(build, floors, @pack)
      def view_pictures(build) = ViewPictures::Packed.new(build, @pack)
      def bar_pictures(build, art:) = BarPictures::Packed.new(build, @pack)
      def menu_pictures(build, art:, palette:) = MenuPictures::Packed.new(build, art, @pack)
      def small_letter_pictures(build, art:, palette:) = SmallLetterPictures::Packed.new(build, palette, @pack)
      def alphabets(build, art:) = Alphabets::Packed.new(build, @pack)
      def article_pages(build, art:, letters:, floors:) = ArticlePages::Packed.new(build, @pack)
    end
  end
end
