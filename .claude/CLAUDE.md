# ruby-wolf3d

Wolfenstein 3D for the Game Boy Advance, written in Ruby against
[VBlank](https://github.com/vblank-rb/vblank). Pure Ruby: this repository builds a
cartridge, it does not implement one. It requires `vblank` as a gem, the way anyone else's
game would.

## What this is FOR

This is a real game, and it is also **the framework's gap-finder**: `.claude/rules/shared/games.md`
has the rules that follow from that, and `.claude/rules/shared/handoff.md` how a wall is filed.

## The game's own data is never in this repository

None of Wolfenstein's data is freely licensed, so none of it is committed (`.claude/rules/shared/games.md`).
`wolf3d.yml` (gitignored) points the build at your copy; `wolf3d.example.yml` shows the shape.
The suite requires that copy and stops without it; no test skips (`.claude/rules/shared/testing.md`).

## Reconstructing a rule of the original game

**Wolfenstein's own source is on disk**, at `~/open_source/wolf4sdl`. Read it before
reconstructing any rule from memory — how much a pickup heals, what a guard does when it hears
you, how the tally screen scores. Memory is confident and wrong about this game.

## The framework's pin

`vblank` and `ruby-gba-emulator` both come from git, as one git source (see the `Gemfile`), and
the game builds and tests against the revision `Gemfile.lock` names. Bundler takes that revision
from the VBlank checkout beside this one, not from GitHub: `bundle config --local local.vblank
../vblank`, set once on each machine and never committed. So a VBlank commit is ready to pin the
moment it is in that checkout, without waiting for it to be pushed. That checkout is never edited
from here.

**A git gem does not move on its own.** `bundle install` keeps whatever revision the lock
names; to pick up new framework commits, **name both gems**:

```bash
bundle update vblank ruby-gba-emulator
```

Naming only one of them does nothing, and says so in a way that reads like success —
`Bundler attempted to update vblank but its version stayed the same`, then `Bundle updated!`,
with the revision in `Gemfile.lock` unchanged. The two gems share one git source, and bundler
will not move a shared source while a gem in it is still pinned. Name both and the source
moves, so they can never end up on different revisions.

## Emulator & integration tests

Integration tests run the built cartridge in an emulator, reached through the framework's one
seam, `VBlank::Diagnostics::Verifier`. Behind that is **ruby-gba-emulator** — a headless
libmgba probe, and a gem of its own rather than part of VBlank, because building a cartridge
is pure Ruby and running one is not.

**Nothing here builds it.** It is a Gemfile line, and bundler builds its C extension on
install, per Ruby ABI — so changing Ruby version gets a rebuild rather than a library compiled
for another Ruby. It needs a C compiler and a system libmgba (`brew install mgba` /
`apt install libmgba-dev`).

It is **required, not optional**: if it cannot load, the emulator-backed tests **fail loudly**
rather than skipping.

## Running Tests

**`rake test` is the suite.** It runs every test in a pool of Ractors — Ruby's way of using
every core inside one process — through the minitest-ractor plugin, the way the framework's own
suite runs. A worker is refused the moment it touches state another one can see, so a green run
also says the code those tests reached shares none. The report at the end says so, or names
what was touched and what to change.

```bash
rake test:golden                                                # the check before a commit
rake test                                                       # the suite
rake test TEST=games/wolf3d/test/test_maps.rb                                # one file
rake test TEST=games/wolf3d/test/test_maps.rb TESTOPTS="--name=/pattern/"    # one test
rake test TESTOPTS=--no-ractor                                  # minitest's own threads, to chase one failure
bundle exec minitest-ractor -I lib -I test -I games/wolf3d/lib -I games/wolf3d/test test/ games/wolf3d/test/                # the audit alone: what to change, grouped by cause
```

**Nothing a test does may reach another test running at the same time.** That rules out
changing `ENV` (hand the build its settings — `Wolf3D.build_rom(settings: { floors: 1 })` — or
hand `GameData` an `env:` of its own), swapping a constant, or caching on a class or module (use
`Ractor.current[:key] ||=`).
A constant a test class declares is frozen all the way down for you as it is declared — see
`games/wolf3d/test/test_helper.rb`.

No `bundle exec`: the Rakefile and `games/wolf3d/lib/wolf3d.rb` each require `bundler/setup` first. `bundle
exec` is still needed for an executable that comes out of the bundle rather than out of this
repository — `bundle exec vblank profile games/wolf3d/wolf3d.rb`.

See `.claude/rules/testing.md`.

## Testing strategy — assert behavior, at the right altitude

Test each layer the way a player experiences it, not by restating the code. There are two
altitudes here, and neither is the framework's.

- **Reading Wolfenstein's own files — assert against the game, not against ourselves.**
  A decoder is right when it agrees with the world: a map is the size the format says, a
  Huffman stream decodes to the byte count its header claims, a wall code finds both of its
  pictures. Where a real copy is needed, the test reads the one the suite requires. Where a
  made-up one will do, `Wolf3D::Fixture::Release` builds a tiny release in memory — one room,
  one wall, known bytes — so the test says exactly which bytes it depends on. Prefer the
  fixture; keep the copy for the few tests that check us against the world.

- **Game behaviour — assert what a player would see, never the IR the build makes.** Build a
  small program through the DSL, run it on the framework's reference interpreter, and read
  the result: where the marker landed, which pixel is lit, what a variable holds. A
  tree-equality assertion is a change-detector — it restates the mapping and stays green
  even when a wrong mental model is baked into both sides. Don't write those.
  - **Fast path: the reference interpreter is a headless oracle.**
    `i = Reference.new.run(program); i.screen.pixel(x, y)` — or `i[:name]` for a variable.
    In-process, deterministic, no emulator. `games/wolf3d/test/test_first_person.rb` is the worked
    example: it builds the view over a one-room fixture level and reads the picture.
  - **Hardware path: the real cartridge** through `VBlank::Diagnostics::Verifier`, reached
    the way any game outside the framework must reach it. `games/wolf3d/test/test_wolf3d_on_hardware.rb`
    is the whole of it — keep it to the few things only the console can answer.
  - Supply input through the interpreter's `hold(:btn)` / `input_each_frame { }`, not by
    poking internal state.

- **A rule of the original game is a fact to be checked**, not an intention to be restated.
  Read it out of `~/open_source/wolf4sdl` and say so in the test's name or a comment, so the
  next reader can see where the number came from.

## Architecture

### Core Files

The game is in `games/wolf3d/` (its `lib`, `test`, `tools`, `films`, the build file `wolf3d.rb`
and `wolf3d.yml`), the way every VBlank game here is laid out. The repository's own `lib/` and
`test/` hold only what knows nothing about Wolfenstein: `lib/id_software/codec/` — `rlew`,
`carmack`, `huffman`, the three compressions id Software's games keep their data in. A map is
Carmack over RLEW; the art and text are Huffman.

The game has three layers, and they load in that order (see `games/wolf3d/lib/wolf3d.rb`, whose
`require`s are commented with what needs what). The paths below are under `games/wolf3d/lib/`.

**Reading the game's own files** — nothing here knows about the console:

- `games/wolf3d/lib/wolf3d/game_data.rb` — finds your copy and says which release it is (`wolf3d.yml`, or
  `WOLF3D_DATA`). `vanilla.rb` — refuses any copy but the six episodes or the shareware, both version 1.4. `maps.rb` /
  `level.rb` — GAMEMAPS and MAPHEAD, a floor as a grid of cells.
  `vswap.rb` — the walls, the things and the digitised sounds. `vgagraph.rb` — the menu art,
  the status bar's plate, the numerals and both proportional alphabets. `palette.rb` — the
  game's own 256 colours.
- `adlib_sounds.rb` — the effects in AUDIOT, which are recipes for the AdLib chip. `opl2.rb` — that
  chip, played while building, so the cartridge holds recordings. `adlib_music.rb` — the tracks in
  AUDIOT, which are logs of writes to it. `opl2_track.rb` — all nine channels, which turn a track
  into a recording, kept under `tmp/music` and never committed.
- `games/wolf3d/lib/wolf3d/fixture/release.rb` — a made-up release built in memory, so most of the suite
  runs with no copy of the game present.

**Turning that into a floor** — still no console:

- `doors.rb`, `pushwalls.rb`, `elevator.rb`, `rooms.rb` — what joins one part of a floor to
  another. `enemy.rb`, `behaviour.rb`, `guards.rb`, `scenery.rb` — the kinds of enemy,
  how their states are laid out, and what stands in the rooms. `floors.rb` — all of it, per
  floor.
- `wall_atlas.rb`, `thing_atlas.rb`, `weapon_atlas.rb`, `bar_art.rb`, `menu_art.rb` — the
  pictures each of those needs, gathered into the atlases the cartridge ships.

**Building the cartridge**, which is where the framework's DSL appears:

- `this_floor.rb` — the floor being played: where its slice of each table begins, and what a
  number in the map means.
- `player.rb` — the player as one record of named variables, handed whole to every part of the
  game that touches them.
- `first_person.rb` — the view down the corridor: the ray, the wall columns, the floor and
  ceiling. Most of a frame. `billboards.rb` — the things and enemies drawn into that view.
  `guard_mind.rb` — what a guard does about you. `thrown.rb` — what the bosses throw. `screen_flash.rb` — red and gold. `death_cam.rb` — how most episodes end. `big_lettering.rb` — the
  game's big letters. `fizzle.rb` — the view dotting over to one colour. `weapons.rb`, `pickups.rb`, `dying.rb`,
  `lives.rb`, `scoring.rb`, `victory.rb`, `tally.rb`, `status_bar.rb`, `sounds.rb`, `music.rb` — the rest of playing.
- `saved_games.rb`, `high_scores.rb` — what lasts on the cartridge, which the menus reach. `small_letters.rb` — words drawn a letter at a time. `victory_march.rb`, `episode_end.rb`, `end_article.rb`, `floor_records.rb` — how an episode ends. `menus.rb`, `title.rb`, `map_view.rb`, `palette_view.rb`, `art_view.rb` — the screens
  around the game.
- `pilot.rb` — a player made of Ruby, not on the cartridge, which `games/wolf3d/tools/play_shareware.rb` runs.
- `games/wolf3d/lib/wolf3d.rb` — the dials (`WOLF3D_EPISODES`, `WOLF3D_FLOORS`, `WOLF3D_FROM`,
  `WOLF3D_START`, `WOLF3D_ARMED`, `WOLF3D_SCREEN`, `WOLF3D_SEED`, `WOLF3D_MUSIC`) and `GAME`, the one `VBlank.game` block.

### Key patterns

- **The dials are for measuring, not for playing.** A cartridge boots on the first floor it
  holds, so the only way to read what a later floor costs is to build one that starts there.
  `WOLF3D_FLOORS=1` is the fastest build there is and is what you want while changing
  something else.
- **The screen is `screen :bitmap, tear_free: true`** and has to be: a first-person view
  repaints every pixel and costs more than a frame holds, so on a screen the display reads
  while the game is still drawing it the player watches the picture arrive.
- **A part of the game is a plain class constructed inside the build block**, taking `build:`
  and whatever it needs, with an `update` the game loop calls. That is the framework's
  multi-file pattern; it is why these files are ordinary Ruby objects and not DSL blocks.
- **A picture the game draws again only when it changes** goes through `keep_showing`, which
  the tear-free screen makes necessary: it keeps two pictures, so a single paint reaches one
  of them and the figure flickers between old and new.

### Naming methods — the name says what it does, not a story about it

**A method's name tells a reader what calling it does or returns, without opening the body.** The
rest of the naming rules are in `.claude/rules/shared/all-projects.md` and `games.md`.

```
BAD   the_world_takes_a_step   a clause of a story
GOOD  step_world
BAD   put_the_flash_away       an everyday phrase standing in for a term
GOOD  finish_flash
BAD   a_guard_fell             says what happened, not what calling it does
GOOD  drop_guard_item
BAD   how_far_away             a question with no verb; it stores a distance
GOOD  measure_distance
```

- **Suffixes are promises.** `?` returns true or false and does nothing else. `!` raises a friendly
  error or mutates in a way a caller must know about.
- **No prose.** No articles (`the_`, `a_`, `an_`), no filler, no metaphors a newcomer cannot decode,
  and no clauses that narrate. A long name is fine only when it is precise, never when it is a
  sentence. This holds for the names given to `func`, `table`, `var` and `pool` too.
- **The original's names come from `~/open_source/wolf4sdl`**, in Ruby's spelling:
  `select_dodge_dir`, `first_sighting`.
- **Siblings differ in their names.** Two names side by side must say in the name what differs.

The plain words used in replies to the operator are for replies, never for names in code.

### Writing code comments

The shared rules for comments are in `.claude/rules/shared/all-projects.md` and `games.md`. Here,
what the reader could not know is the shape of Wolfenstein's own file formats, and what a rule of
the original game is and why. The reader knows Ruby. They do not know GAMEMAPS, Carmack
compression, or what a pushwall is. That teaching is the point.

### Writing text the player reads — use the `simple-english` skill

When you write or change a message the player or the builder reads — what the cartridge says
when it cannot find your copy of the game, what an argument error says about `WOLF3D_EPISODES`
— run the text through the `simple-english` skill (ASD-STE100). Short sentences, one idea
each. Use one word for one meaning. Put the condition before the command. Say what happened,
then what to do about it, early. Prefer `can`, `will`, and `must`; do not use `should`,
`could`, or `may`. This rule applies to strings somebody reads. It does **not** apply to code
comments — those stay conversational and explain generously (see above).

### Claude Memory
- Don't use it, period. Material knowledge goes in code comments.
- Code style should be Rubocop or similar.

### DSL habits this game follows

What the verbs do is VBlank's to document (`.claude/rules/shared/games.md`). The habits:

- `flip` (not `negate`) for reversing direction.
- Underscore prefix (`_ray_x`) for scratch/temp variables.
- `func` for subroutines, `scene` for game states, `case_var` for dispatch.
