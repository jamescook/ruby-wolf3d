# frozen_string_literal: true

module Wolf3DTest
  # A WHOLE BUILD'S TITLE AND MENU, the pictures MenuPictures draws: booted on the title, which has
  # faded in by FRAMES, then A takes it to the main menu. test_holding.rb boots each screen and reads
  # it at FRAMES; films/whole_menus.rb plays the title into the menu.
  module MenuScene
    SCREENS = %w[title menu].freeze
    FRAMES = 60          # A screen booted on has faded all the way in
    PRESS_FRAME = 90     # ...then A leaves the title
    FILM_FRAMES = 200    # ...and the menu has faded in

    def self.keys(frame) = frame == PRESS_FRAME ? [:a] : []
  end
end
