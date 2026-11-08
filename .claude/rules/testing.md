---
paths:
  - "games/wolf3d/test/**/*.rb"
  - "test/**/*.rb"
  - "lib/**/*.rb"
  - "games/wolf3d/lib/**/*.rb"
  - "Rakefile"
---

# Testing rules — `games/wolf3d/test/`

Helpers and patterns already established in this suite. Reach for these before
inventing new scaffolding. The *philosophy* (what to assert at which altitude)
lives in `.claude/CLAUDE.md`; this file is the practical how — the APIs and
worked examples. The rules every game shares are in `.claude/rules/shared/testing.md`, and which
skill a piece of work wants is in `.claude/rules/shared/all-projects.md`.

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

- `Reference` (the framework's oracle backend), `SaveImage` (an empty save memory for
  `Reference.new(save:)`; hand the same one to a second run to power the cartridge on again),
  `GBA` (the ROM lowering), `Builder`, `ROM`,
  `Verifier` (the real cartridge in the emulator), `Constants` (`KEY_UP` and the rest of the
  hardware's names), `Fraction`. Each lives a module or two down in VBlank; the helper names
  them once so the next reshuffle there moves one line, not a hundred.
- `real_copy`, `real_shareware` — the real copies of Wolfenstein the suite requires, through
  VBlank's `original_copy`: nothing set stops the test with what to set.
- `a_small_cartridge` — the whole game built with the setting `floors: 1`, for the tests that
  build the whole game, kept in VBlank's `CartridgeCache` under `.cache/builds` and built again
  only when the game, the copy or the framework changes.

Unlike the framework's suite, this one does **not** reopen `Minitest::Test` — each file says
`include Wolf3DTest`, so the names appear only where they are used. Including it also hands the
class to the pool (`parallelize_me!`) and freezes every constant the class declares after that
line, all the way down, because a worker may only read a constant nothing can change.

Running them. **The suite is `rake test`**, every test in a pool of Ractors (the minitest-ractor
plugin). It ends with a report: either no findings, or each piece of shared state a test
reached, grouped by cause, with what to change.

```bash
rake test                                                       # the suite
rake test TEST=games/wolf3d/test/test_maps.rb                                # one file
rake test TEST=games/wolf3d/test/test_maps.rb TESTOPTS="--name=/pattern/"    # one test; -n /pat/ trips shell quoting
rake test TESTOPTS=--no-ractor                                  # minitest's own threads instead
bundle exec minitest-ractor -I lib -I test -I games/wolf3d/lib -I games/wolf3d/test test/ games/wolf3d/test/                # the audit on its own
```

## Tests run at the same time as each other

Every test shares the process with others running on other cores, so nothing a test does may
reach past itself:

- **Never change `ENV`.** It is the whole process's. Hand a build its settings instead —
  `Wolf3D.build_rom(settings: { episodes: "2" })`, or `GAME.program(settings: …)` — which reach
  that one build and nothing else; the names are the keys of `Wolf3D::DIALS`. Hand
  `GameData.locate` an `env:` hash of its own.
- **Never swap a constant** to build something a different way. Pass the setting in —
  `FirstPerson.new(pacing: :by_the_frame)` is the worked example.
- **Never cache on a class or module** (`def self.x = @x ||= …`). A worker may not write one.
  Cache per Ractor instead: `Ractor.current[:status_bar_release] ||= …`. Each worker then builds
  it once. Not `Ractor.store_if_absent`, which holds a lock while it works the value out, so one
  cached value asking for another waits on itself.

No `bundle exec`: `games/wolf3d/lib/wolf3d.rb` and the Rakefile each require `bundler/setup` first.

## Which copy of the game a test needs — the first question

Most of this suite reads Wolfenstein's own file formats, so almost every test has to answer
"read whose files?". There are two answers.

**`Wolf3D::Fixture::Release` — a made-up release built in memory.** One room, one wall, known
bytes, written in the real formats. Reach for this **by default**: it is fast, and a test
written against it says exactly which bytes it depends on. It is what
`test_first_person.rb`, `test_doors.rb` and most of the rest use.

```ruby
def fixture = @fixture ||= Wolf3D::Fixture::Release.new

level = Wolf3D::Maps.new(maphead: fixture.files["MAPHEAD"],
                         gamemaps: fixture.files["GAMEMAPS"])[0]
vswap = Wolf3D::Vswap.new(fixture.files["VSWAP"])
```

**`real_copy` — the real copy.** Only for the few tests that check us against the world
rather than against ourselves: that a real GAMEMAPS has the episode count it should, that a
real VGAGRAPH's Huffman tree decodes. The suite requires the copy and stops without it; no test
skips (`.claude/rules/shared/testing.md`).

Never commit a byte of real game data, not even a small one, and not as a test fixture. That
is what `Fixture::Release` exists to make unnecessary.

## Asserting what something COSTS

The two instruments, what the build emitted and what the console did, are in VBlank's
`.claude/testing/costs.md`. Here, "drawing the bar's figures costs less than redrawing the plate"
is a size claim; anything about time is a profile.

**This game is on the tear-free screen**, so the reading that applies to it is not tearing but
**flicker**: that screen keeps two pictures and shows them in turn, so anything the game ADDS
to what is already there lands in one of the two and alternates. The profile names how many
pixels are stuck and where the first one is. The game's death fizzle is the worked example of
handling it — it draws every dot on two frames running, which is why it does not flicker.

## The two backends you assert against

- **Reference interpreter** `VBlank::IR::Backends::Reference` — headless oracle, no
  emulator, in-process, deterministic. This is where nearly every behavioural test here lives.
- **Hardware** via `VBlank::Diagnostics::Verifier` — runs the real cartridge, reads real pixels.
  `games/wolf3d/test/test_wolf3d_on_hardware.rb` is the whole of it.

Reached through the framework's public seam, never through its test directory: a game outside
the framework cannot get at `GembaSupport`, and this one is here to feel that.

Keep the hardware tests few. They are slow, they answer only the questions the oracle cannot
(does a real cartridge boot, does it draw anything), and a frame count in one of them goes
stale quietly — `FIRST_DRAWN_FRAME` has already moved once as the first pass grew.

## Reference interpreter API

The interpreter's API is in VBlank's `.claude/testing/interpreter.md`. What matters here:
`frames_each_pass` says a pass ran late, and a pass of this game's view takes several frames on
the console, so anything that has to keep real time — a fizzle, a flash, a door's dwell — is what
`test_keeping_time.rb` pins with it. A test that draws a whole view says `frames: 400` and gets
400.

## Hardware API

The `Verifier`'s API is in VBlank's `.claude/testing/emulator.md`. Here the cartridge is
`a_small_cartridge`.

`frames:` is how far it runs before you read. **This game needs more of them than a small
program does**: the tear-free screen shows nothing until the first pass finishes, and a pass
of this view takes several frames, so the screen is genuinely black for the first few.
`FIRST_DRAWN_FRAME` in `test_wolf3d_on_hardware.rb` records where that line currently is,
with a comment saying it has moved before and to re-measure it rather than suspect the build.

## Building the program under test

- **The view over a floor of its own**, for nearly every test of how the game plays: the helpers
  in `games/wolf3d/test/support/field.rb`, which `Wolf3DTest` includes. `arena(guards: [[11, 8, :west]])` is a
  walled field with what you name standing in it, `two_rooms` is two rooms joined only by a door,
  and `view_of(level)` is the whole view over one floor, ready for `Reference`. `drawing: false`
  skips the picture, `standing: false` leaves out guards and scenery, any other keyword goes to
  `FirstPerson`, and a block writes the game loop itself. `cartridge_of(floors)` is the same over
  several floors. A file says what is particular to it by defining its own `arena`, `view_of` or
  `fixture` and calling `super`. See `test_hearing.rb`. Memoize a program; building is the slow
  part of these tests, not running them.

- **A cartridge of its own**, for a test about one part that needs no view:
  `VBlank.game("LIVES", consoles: %i[gba]) { … }.program`, constructing that part inside the
  block. See `test_lives.rb`.

- **The real game**, for the two tests that check the whole wiring:
  `a_small_cartridge`. The cache builds it with no report, so nothing prints into the test output.

Note `VBlank.game(...)` hands back a game whose `.program` is the IR; `VBlank.build(...)`
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
- `rake test` runs everything; a single file is `rake test TEST=games/wolf3d/test/the_file.rb`.
- Building is the slow part. Memoize a cartridge built in a test class, and reach for
  `a_small_cartridge` rather than shipping every floor to prove one thing.
