# frozen_string_literal: true

module Wolf3DTest
  # TURNING ON THE SPOT, walking and then with A held: the moment test_first_person.rb measures
  # and films/turning.rb shows. The original turns 1.75 degrees a tic walking and 3.5 running
  # (wl_play.cpp, PollKeyboardMove; wl_agent.cpp, ControlMovement).
  #
  # Counted in frames of input. On the interpreter a frame is a pass; on the console a pass takes
  # several frames, so the film turns less far in the same frames. Each stretch stays under a full
  # turn on the interpreter, so how far it went can be read back without counting laps.
  module TurningScene
    # Nothing at first, while the cartridge draws its first picture; then right alone; then right
    # with A. And the cartridge the film plays it on: the first floor, booted straight into play.
    STILL_FRAMES = 20
    WALK_FRAMES = 180
    RUN_FRAMES = 90
    CARTRIDGE_SETTINGS = { floors: 1, screen: "playing" }.freeze

    def self.walk_ends = STILL_FRAMES + WALK_FRAMES
    def self.run_ends = walk_ends + RUN_FRAMES

    # The buttons down on +frame+, counted from one.
    def self.keys(frame)
      return nil if frame <= STILL_FRAMES
      return [:right] if frame <= walk_ends
      return %i[right a] if frame <= run_ends

      nil
    end
  end
end
