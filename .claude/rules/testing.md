---
paths:
  - "test/**/*.rb"
---

# Testing rules — `test/`

Helpers and patterns already established in this suite. Reach for these before
inventing new scaffolding. The *philosophy* (what to assert at which altitude)
lives in `.claude/CLAUDE.md`; this file is the practical how — the APIs and
worked examples.

## How a test file starts

**One require, then include the module:**

```ruby
# frozen_string_literal: true

require_relative "test_helper"

class TestThing < Minitest::Test
  include Wolf3DTest

  def test_it_does_the_thing
    ...
  end
end
```

`test_helper` pulls in minitest and the game (which pulls in the framework), and
`Wolf3DTest` hands the test these names and helpers:

- `Reference` (the framework's oracle backend), `GBA` (the ROM lowering), `Builder`, `ROM`
- `game_data_or_skip` — a real copy of Wolfenstein, or a skip saying how to point at one
- `a_small_cartridge { }` — builds under `WOLF3D_FLOORS=1`, for the tests that build the whole
  game. Shipping sixty floors to prove the wiring works takes a minute; one floor is a few
  seconds and proves the same thing.

Unlike the framework's suite, this one does **not** reopen `Minitest::Test` — each file says
`include Wolf3DTest`, so the names appear only where they are used.

Running them. **The suite is `rake test:parallel`** — it spreads the files over processes and
finishes in a fraction of the time. Bare `rake test` runs the lot in one process, so use it
only to name ONE file or one test:

```bash
rake test:parallel                                              # the suite (JOBS=8 to pick a count)
rake test TEST=test/test_maps.rb                                # one file
rake test TEST=test/test_maps.rb TESTOPTS="--name=/pattern/"    # one test; -n /pat/ trips shell quoting
ruby -Itest -Ilib test/test_maps.rb                             # one file, no rake
```

No `bundle exec`: `lib/wolf3d.rb` and the Rakefile each require `bundler/setup` first.

The framework's suite does not run this one and knows nothing about it.

## Which copy of the game a test needs — the first question

Most of this suite reads Wolfenstein's own file formats, so almost every test has to answer
"read whose files?". There are two answers and the wrong one costs the suite its portability.

**`Wolf3D::Fixture::Release` — a made-up release built in memory.** One room, one wall, known
bytes, written in the real formats. Reach for this **by default**: it runs on every machine,
it is fast, and a test written against it says exactly which bytes it depends on. It is what
`test_first_person.rb`, `test_doors.rb` and most of the rest use.

```ruby
def fixture = @fixture ||= Wolf3D::Fixture::Release.new

level = Wolf3D::Maps.new(maphead: fixture.files["MAPHEAD"],
                         gamemaps: fixture.files["GAMEMAPS"])[0]
vswap = Wolf3D::Vswap.new(fixture.files["VSWAP"])
```

**`game_data_or_skip` — a real copy.** Only for the few tests that check us against the world
rather than against ourselves: that a real GAMEMAPS has the episode count it should, that a
real VGAGRAPH's Huffman tree decodes. It **skips** with a message when no copy is present, so
the suite still passes on a machine that has none. A green run with skips is not proof those
paths work — check the skip count when it matters.

Never commit a byte of real game data, not even a small one, and not as a test fixture. That
is what `Fixture::Release` exists to make unnecessary.

## Asserting what something COSTS

The framework has no cost estimator — there was one and it is deleted, in favour of measuring
the game. So a test that wants to say "this is more work than that" has two honest
instruments, and picking the wrong one is the mistake to avoid.

**What the build EMITTED**, for a claim about code that is a straight run of instructions:

```ruby
RubyGBA::IR::Backends::GBA.new.lower(program).bytesize
```

Right for "drawing the bar's figures costs less than redrawing the plate". Wrong wherever
machinery is SHARED — a palette, a glyph routine, the column drawer — because it lands
wherever it is first needed, so the same code reads as one size in a small program and
another in the real cartridge.

**What the console really DID**, for anything about time:

```ruby
result = RubyGBA::Profiler.run(rom, frames: 30, picture: false)
result.idle_share        # how much of each frame was left over — the usual one
result.fps               # 60.0, or less when a pass does not fit in a frame
result.samples_per_frame # instructions a frame
```

It needs a ROM built through the DSL (or `rom_of`, which hands the build record over), because
a profile has to know where each routine ended up and that cannot be read back out of bytes.
`picture: false` skips the readings that look at the SCREEN rather than at where the time went
— whether the game tore, and whether it is losing half its drawing (`Flicker`). Both cost a bus
read per pixel; exactly one of them applies to any given game.

**Pick `idle_share` over `samples_per_frame`** for "is this faster". A pass too slow for one
frame spills into the next, so a slow build runs FEWER instructions per frame — counting those
reads backwards. And a program heavy enough to never sleep idles at 0.0 either way, so for one
of those compare `fps` instead.

**This game is on the tear-free screen**, so the reading that applies to it is not tearing but
**flicker**: that screen keeps two pictures and shows them in turn, so anything the game ADDS
to what is already there lands in one of the two and alternates. The profile names how many
pixels are stuck and where the first one is. The game's death fizzle is the worked example of
handling it — it draws every dot on two frames running, which is why it does not flicker.

## The two backends you assert against

- **Reference interpreter** `RubyGBA::IR::Backends::Reference` — headless oracle, no
  emulator, in-process, deterministic. This is where nearly every behavioural test here lives.
- **Hardware** via `RubyGBA::Verifier` — runs the real cartridge, reads real pixels.
  `test/test_wolf3d_on_hardware.rb` is the whole of it.

Reached through the framework's public seam, never through its test directory: a game outside
the framework cannot get at `GembaSupport`, and this one is here to feel that.

Keep the hardware tests few. They are slow, they answer only the questions the oracle cannot
(does a real cartridge boot, does it draw anything), and a frame count in one of them goes
stale quietly — `FIRST_DRAWN_FRAME` has already moved once as the first pass grew.

## Reference interpreter API

```ruby
i = Reference.new.run(program)          # returns self; 20 frames of a game loop by default
i = Reference.new.run(program, frames: 400)  # play this far in — every frame, however heavy
i.screen.pixel(x, y)               # colour at (x, y); nil if off-screen; 0 = unwritten (black)
i[:varname]                        # a variable's final value (0 if never written)
i.screen_mode                      # e.g. :bitmap
i.audio                            # the audio/register log
i.stopped_at_budget?               # true if it was still looping when cut off

Reference.new.hold(:left, :a).run(prog)              # buttons held for the whole run
Reference.new.input_each_frame { |f| [:left] }.run(prog)  # per-frame input; needed to observe `pressed` edges
Reference.new.frames_each_pass { |pass| 3 }.run(prog)     # say a pass ran late: 3 frames of catch-up
```

`frames_each_pass` is the one thing the interpreter cannot find out for itself — it has no
clock and is never late by construction — so a test says it. The block gives how many frames
each pass answered for, held between 1 and `IR::Frames::MOST` exactly as the console holds it.
That drives `once_a_frame` (the body runs that many times), a beat in frames, and a one-shot's
counter. It does **not** make the interpreter slow: timers still accrue a pass's worth, the
input script is still called once a pass, and `frames:` still counts passes. It matters here:
a pass of this game's view takes several frames on the console, so anything that has to keep
real time — a fizzle, a flash, a door's dwell — is what `test_keeping_time.rb` pins with it.

`frames:` is the stop condition, and every frame asked for is played however much work each
takes — so a test of a game that draws a whole view says `frames: 400` and gets 400. The step
budget behind it (`max_steps:`, a million by default) guards ONE frame, so a heavy frame can't
eat the frames after it; a frame that spends the whole budget never reached a vblank at all, and
raises rather than handing back a part-played run. **Do not pass `max_steps:` alongside
`frames:`** — the per-frame default has room to spare, and a hand-sized budget beside a frame
count is the old workaround for this bug. Reach for it only to run a program with no frames in it (an unpaced `frame_sync: :manual` loop),
where it becomes the whole-run budget and `stopped_at_budget?` reports it.

Screen default fill is `0` (black). For clip/overwrite tests, `clear_screen` to a
**distinct** background first so "clipped/absent" reads as that colour, and the
two backends agree on it.

## Hardware API

The framework's public seam. Build a cartridge, hand it to a `Verifier`, read pixels:

```ruby
rom = a_small_cartridge { Wolf3D.build_rom(out: StringIO.new, err: StringIO.new) }
v = RubyGBA::Verifier.new(rom, frames: 8)

v.all_black?                               # "did it boot to nothing"
v.pixel_is?(x, y, :red)                    # colour by name or 15-bit value
v.pixel_gba(x, y)                          # the raw 15-bit BGR555 (good in failure messages)
v.region_color?(x, y, w, h, :blue)
```

`frames:` is how far it runs before you read. **This game needs more of them than a small
program does**: the tear-free screen shows nothing until the first pass finishes, and a pass
of this view takes several frames, so the screen is genuinely black for the first few.
`FIRST_DRAWN_FRAME` in `test_wolf3d_on_hardware.rb` records where that line currently is,
with a comment saying it has moved before and to re-measure it rather than suspect the build.

## Building the program under test

- **A cartridge of its own**, for a test about one part: `RubyGBA.game("VIEW", code:, maker:)
  { … }.program`, constructing that part inside the block over a fixture level. This is the
  common shape — see `test_first_person.rb#build_the_view`. Memoize it; building is the slow
  part of these tests, not running them.

- **The real game**, for the two tests that check the whole wiring:
  `a_small_cartridge { Wolf3D.build_rom(out: StringIO.new, err: StringIO.new) }`. Pass
  `StringIO` for both streams so the build's report does not print into the test output — and
  so a test can assert on what it said.

Note `RubyGBA.game(...)` hands back a game whose `.program` is the IR; `RubyGBA.build(...)`
hands back a finished ROM. Tests that read pixels off the oracle want the first.

## Choosing test values

Make colours and positions *diagnostic*. A wall drawn in one flat colour proves only that
something drew; a wall whose two forms differ — lit and dark, which is how this game shades a
face — catches picking the wrong one of the pair. Read a pixel at a column whose answer you
can work out by hand from the fixture level, not one in the middle of a picture.

`Fixture::Release` is built so its bytes are recognisable: one wall code, one room, known
sizes. When a test needs a number, take it from the fixture's own constants
(`Fixture::Release::WALL`) rather than writing the literal, so a change to the fixture moves
the tests with it.

## Errors the builder reads

Assert the *friendly error* a misuse raises — its class and a key phrase, not the exact
wording, which is free to improve. `WOLF3D_EPISODES` asking for an episode this copy does not
have is the worked example.

## Gotchas

- Don't name a test helper `run` — it shadows `Minitest::Test#run`.
- `rake test:parallel` runs everything; a single file is `ruby -Itest -Ilib test/the_file.rb`.
- Tests needing a real copy of the game **skip** (not fail) without one — a green run with
  skips is not proof those paths work. Check the skip count when it matters; a full run with
  a copy present reports **0 skips**.
- Building is the slow part. Memoize a cartridge built in a test class, and reach for
  `a_small_cartridge` rather than shipping every floor to prove one thing.
