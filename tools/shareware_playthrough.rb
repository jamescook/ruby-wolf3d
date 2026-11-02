# frozen_string_literal: true

# THE SHAREWARE PLAYED BY Wolf3D::Pilot, as a script for `vblank play`. tools/play_shareware.rb is
# the way to run it, and says which copy to read. WOLF3D_PILOT_FLOORS stops it after that many floors,
# and WOLF3D_PILOT_DIFFICULTY picks the row of the difficulty screen, counted from nought.

#
# It does not require the game. `vblank play` loads this file first and the game file after, and a
# game already loaded would not declare itself to it. So the Pilot is made at the first frame, when
# the game is there.

frames_for_a_floor = 120_000
frames_on_the_scores = 300
frames_for_a_screen_to_show = 120
floors_before_the_last = 8
stop_after = ENV.fetch("WOLF3D_PILOT_FLOORS", nil)&.to_i
floors_played = (1..floors_before_the_last).select { |floor| stop_after.nil? || floor <= stop_after }
pilot = nil
pilot_buttons = lambda do |game|
  pilot ||= Wolf3D::Pilot.new(Wolf3D.maps, difficulty: ENV.fetch("WOLF3D_PILOT_DIFFICULTY", "0").to_i)
  pilot.buttons_for(game)
end

VBlank.playthrough "the shareware" do
  floors_played.each do |floor|
    steer("finish floor #{floor}", within: frames_for_a_floor) do |game|
      next :done if game.var(:floor) >= floor

      pilot_buttons.call(game)
    end
    moment :"floor_#{floor}_done"
  end
  if stop_after.nil?
    steer("reach the winning screen", within: frames_for_a_floor, &pilot_buttons)
    moment :won
    wait frames: frames_for_a_screen_to_show
    moment :summary
    steer("read the summary", within: frames_for_a_floor) do |game|
      next :done if game.var(:screen) == Wolf3D::Menus::ARTICLE

      pilot.ending_buttons(game)
    end
    wait frames: frames_for_a_screen_to_show
    moment :article
    steer("read the article", within: frames_for_a_floor) { |game| pilot.ending_buttons(game) }
    wait frames: frames_on_the_scores
    moment :scores
  end
end
