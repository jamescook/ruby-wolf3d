# frozen_string_literal: true

module Wolf3D
  # WHERE THE ARTICLES AN EPISODE ENDS ON COME FROM (EpisodeEnd): every episode's article laid out in
  # pages of EpisodeEnd::LINES rows, EpisodeEnd::COLUMNS bytes to a row, blanks to the end of each.
  #
  # A TRIMMED BUILD LAYS THEM OUT FROM VGAGRAPH (Baked) while it is built, in the small alphabet's
  # widths. A WHOLE BUILD TAKES THEM FROM ITS DATA PACK (Packed), where EndArticleUnpacking laid them
  # out the same way into article_pages and article_first_page. EpisodeEnd asks for them here and
  # never which kind of build it is in.
  #
  # WHAT IT ANSWERS: declare, the two tables as an ArticleTables: where each episode's first page is
  # (one more than there are episodes, so the last is where the pages stop), and the text.
  module ArticlePages
    ArticleTables = Data.define(:first_page, :text)

    # THE PAGES LAID OUT IN RUBY, for the episodes the build's +floors+ reach.
    class Baked
      def initialize(build, art, letters, floors)
        @b = build
        @art = art
        @letters = letters
        @floors = floors
      end

      def declare
        pages = (0...Floors.episodes_in(@floors)).map { |n| lay_out_pages(n) }
        starts = pages.map(&:length).inject([0]) { |all, count| all + [all.last + count] }
        ArticleTables.new(first_page: @b.table(:article_first_page, starts, width: :byte),
                          text: @b.table(:article_text, Floors.at_least_one(pages.flatten(1).flat_map { |page| flatten_page(page) }),
                                         width: :byte))
      end

      private

      def lay_out_pages(episode)
        EndArticle.pages(@art.end_article(episode), width: EpisodeEnd::TEXT_WIDTH, lines: EpisodeEnd::LINES) do |char|
          @letters.width_of(char)
        end
      end

      def flatten_page(page)
        Array.new(EpisodeEnd::LINES) { |n| (page[n] || "").ljust(EpisodeEnd::COLUMNS, "\0").bytes.first(EpisodeEnd::COLUMNS) }.flatten
      end
    end

    # THE PAGES AS THE PACK HOLDS THEM.
    class Packed
      def initialize(build, pack)
        @b = build
        @pack = pack
      end

      def declare
        ArticleTables.new(first_page: @b.table(:article_first_page, @pack[:article_first_page]),
                          text: @b.table(:article_text, @pack[:article_pages]))
      end
    end
  end
end
