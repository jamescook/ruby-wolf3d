# frozen_string_literal: true

module Wolf3D
  # THE VIEW DOTTING OVER TO ONE COLOUR, a pixel at a time and in no order you can see. It is how the
  # original gets from one picture to the next, and here it is the red of a death and the blank
  # before "Let's see that again!".
  #
  # WHY IT IS NOT A SHIFT REGISTER. The original scatters with a maximum-length linear feedback
  # shift register, which visits every pixel exactly once with nothing to remember — a shift, a
  # test and an exclusive-or per pixel. This framework has no bitwise operators at all (the IR
  # knows + - * / % and the comparisons, and nothing else), so that is not expressible, and
  # adding one is a new IR operator with a conformance fixture, a cost weight and two backends
  # behind it — far more than this needs.
  #
  # What replaces it does the same job with the arithmetic that IS here. Step a number by
  # multiplying it, modulo a prime just above the number of pixels: `n = n * STEP % MODULUS`.
  # With STEP a primitive root, that visits every value from 1 to MODULUS-1 exactly once before
  # it comes back round, which is the same guarantee the shift register gives — every pixel
  # once, nothing remembered but the current number. It is two instructions rather than three,
  # and the six values that overshoot the last pixel fall off the bottom of the view and are
  # clipped, so nothing has to test for them.
  #
  # AND WHY EVERY DOT IS DRAWN TWICE. This game draws on a tear-free screen, which keeps two
  # pictures and shows them in turn — so a frame's drawing lands on one of them and the next
  # frame's on the other. A program that repaints everything every frame never notices. This one
  # ADDS to what is already there, so drawn once, each page would get half the dots and the
  # screen would flicker between two half-finished pictures.
  #
  # `keep_showing` IS THE FRAMEWORK'S ANSWER TO THAT and does not fit here. It paints the same
  # picture again on the next frame, which suits a figure that changed and is then left alone —
  # the status bar, the GAME OVER words. A fizzle draws DIFFERENT dots every frame, so painting
  # it again a frame later draws the next batch rather than this one twice.
  #
  # So there are two walkers stepping the same sequence, one a frame behind the other. Every dot
  # is drawn on two consecutive frames, which is one of each page, and neither walker has to
  # know anything about the other or about which page it is on.
  #
  # WHAT THIS CANNOT DO is dot over to a PICTURE. The dots are one flat colour, and nothing the
  # framework offers reads a pixel of one picture to put it on another.
  class Fizzle
    game_variables :walkers, :lead_done, :lag_done, :spot, saved: false

    ACROSS = FirstPerson::ACROSS
    DOWN = FirstPerson::VIEW_H
    PIXELS = ACROSS * DOWN

    # THE STEP AND THE PRIME, worked out once and written down rather than computed at build
    # time, because finding a primitive root needs the factors of MODULUS-1 and that is a lot of
    # machinery to carry for two numbers that will never change. What they promise — that
    # stepping from 1 reaches every value below MODULUS exactly once — is checked by a test, by
    # walking the whole sequence, which needs no number theory to read.
    #
    # MODULUS is the first prime above the number of pixels, so six of its values name a spot
    # past the last one. See #scatter for where those six go.
    MODULUS = 30_727
    STEP = 15_363

    # How long a fizzle takes: one second, which is what the original spends on it (70 frames
    # of its 70 a second, so sixty of this console's).
    #
    # COUNTED IN PASSES OF THE GAME LOOP rather than in frames, unlike everything else the game
    # moves by, and on purpose. Drawing belongs to the pass — which page it lands on is decided
    # by the pass, and the whole two-walker arrangement above rests on that. Putting it on the
    # clock would mean a late pass drew two or three batches at once, which is more drawing,
    # which makes the pass later still. So a game that cannot keep up takes a little longer over
    # it instead, which is the safe way round.
    FRAMES = 60
    PER_FRAME = ((MODULUS - 1) / FRAMES) + 1

    # +colour+ goes in here because a drawing verb has to be told its colour while the cartridge is
    # built, so a second colour is a second one of these. Each keeps variables of its own.
    def initialize(build:, colour:)
      @b = build
      @colour = colour
      @walkers = { lead: 1, lag: 1 } # a Hash, so that #scatter can change either
      @lead_done = 0
      @lag_done = 0
      @spot = 0
    end

    # BACK TO THE BEGINNING. They start at 1 because nought is the one number a step like theirs can
    # never leave.
    def start_again
      @walkers[:lead] = 1
      @walkers[:lag] = 1
      @lead_done = 0
      @lag_done = 0
    end

    # Has every dot gone on to both pictures?
    def finished = @lag_done >= MODULUS - 1

    # One pass of it.
    def scatter_dots
      if @lead_done < MODULUS - 1
        scatter(:lead)
        @lead_done += PER_FRAME
      end
      # ...and last frame's dots again, onto the page that missed them.
      if @lead_done > PER_FRAME
        scatter(:lag)
        @lag_done += PER_FRAME
      end
    end

    private

    # HOW THE SIX OVERSHOOTS ARE KEPT OUT OF THE STATUS BAR. The prime is a few above the number
    # of pixels, so six of its values name a spot one row below the view — and `inside` clips
    # them for nothing, on both backends: `draw_rect_at` is a run-time position, the one kind
    # `inside` could not clip until the framework learned to hold it to the area (it used to
    # wrap onto the next row on the console instead of stopping, a framework bug that lived here
    # as a worked-around comment for a while).
    def scatter(which)
      @b.inside(0, 0, ACROSS, DOWN) do
        @b.repeat(PER_FRAME) do
          @walkers[which] = (@walkers[which] * STEP) % MODULUS
          @spot = @walkers[which] - 1
          @b.draw_rect_at @spot % ACROSS, @spot / ACROSS, 1, 1, @colour
        end
      end
    end
  end
end
