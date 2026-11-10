# frozen_string_literal: true

module Wolf3DTest
  # THE FIRST EPISODE'S END ARTICLE, reached from the screen that says you won: booted there, A goes
  # on to the article's first page, and A again to its second. test_holding.rb reads the first page
  # of a whole build at FRAMES; films/whole_article.rb shows both.
  module ArticleScene
    # A build that can end the first episode holds its last floor, the tenth.
    SETTINGS = { screen: "won", floors: 10 }.freeze
    PRESS_FRAME = 60     # The summary has faded in
    FRAMES = 140         # ...and the first page after it
    TURN_FRAME = 200     # ...then the page turns
    FILM_FRAMES = 280    # ...and the second page is up

    def self.keys(frame) = [PRESS_FRAME, TURN_FRAME].include?(frame) ? [:a] : []
  end
end
