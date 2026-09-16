# ruby-wolf3d

Wolfenstein 3D for the Game Boy Advance, written in Ruby against
[ruby-gba](https://github.com/jamescook/ruby-gba). Pure Ruby: this repository builds a
cartridge, it does not implement one. It requires `ruby_gba` as a gem, the way anyone else's
game would.

## What this is FOR — the north star

This is a real game, and it is also **the framework's gap-finder**. Porting a game people know
keeps meeting things the framework cannot yet do, and each of those is worth more than the
workaround. So when this game hits a wall:

- **The framework-side finding is the valuable output**, more than whatever this game ships to
  get past it. Record it against the framework, not here.
- **Do not work around a gap here if the framework could close it.** A clever hack in this
  repository hides the very thing the port exists to find.
- **Never reach past the framework's public surface** — not into `RubyGBA::IR`, not into a
  backend, not into its test directory. Feeling the constraint is the point; a game that can
  cheat its way past one stops reporting it.
- **A gap worth closing is worth recording even when you route around it today.** Say which
  you did, and why.

## The game's own data is never in this repository

None of Wolfenstein's data is freely licensed, so none of it is committed — not the files you
supply, not anything converted out of them. The readers are committed; what they read is not.
`wolf3d.yml` (gitignored) points the build at your copy; `wolf3d.example.yml` shows the shape.
Tests that need the data skip and say so, and the suite never depends on one being present.

That is also why the framework's suite does not run this one and knows nothing about it: it
would fail on every machine but yours. The dependency runs one way only — this game leans on
the framework for everything, and the framework must never learn this game's name.

## Reconstructing a rule of the original game

**Wolfenstein's own source is on disk**, at `~/open_source/wolf4sdl`. Read it before
reconstructing any rule from memory — how much a pickup heals, what a guard does when it hears
you, how the tally screen scores. Memory is confident and wrong about this game.

## Shell commands — one operation per call

Run **one logical command per Bash call.** Do not chain distinct operations with `&&`, `;`,
or newlines in a single invocation, and do not bundle a file-writing heredoc
(`cat > f <<EOF …`) with the command that consumes it.

Why this is non-negotiable here: the operator reads each command before allowing it, and the
permission allow/denylist matches on recognizable prefixes (`git commit`, `rake test:parallel`,
`rake build`). A blob like `cat > msg <<EOF … EOF; git add .; git commit -F msg; git show` is
unreadable, can't be allowlisted, and can't be denied granularly.

- `git add`, then `git commit`, then `git show` are **three separate Bash calls**, not one.
  Need several commands at once? Issue several Bash calls (they can run in parallel) — each
  stays individually matchable.
- Write files — commit messages, scripts, long bodies of text — with the **Write/Edit tools**,
  never `cat >`/heredocs. Then a single command reads the file (`git commit -F <file>`).
- No `python3 -c '…'` / `ruby -e '…'` logic one-liners. Put logic in a file so it's
  inspectable and re-runnable.
- Prefer one clear command over a clever pipeline, even for read-only inspection.


## The framework, and working on both at once

`ruby-gba` and `ruby-gba-emulator` both come from git (see the `Gemfile`). To edit the
framework and this game together, point bundler at a checkout beside this one:

```bash
bundle config set --local local.ruby-gba ../ruby-gba
```

**One override covers both gems**, because the Gemfile declares them as one git source — the
emulator resolves to `ruby-gba-emulator/` inside that same checkout. Undo it with
`bundle config --delete local.ruby-gba`. It is also the only way to test against framework work
that is not pushed yet.

One catch while the override is on: an overridden gem behaves like a `path:` source, and
bundler does not build extensions for those. If the emulator will not load, run
`rake compile_emulator` in the framework checkout — its error message says so too.

**A git gem does not move on its own.** `bundle install` keeps whatever revision the lock
names; to pick up new framework commits, **name both gems**:

```bash
bundle update ruby-gba ruby-gba-emulator
```

Naming only one of them does nothing, and says so in a way that reads like success —
`Bundler attempted to update ruby-gba but its version stayed the same`, then `Bundle updated!`,
with the revision in `Gemfile.lock` unchanged. The two gems share one git source, and bundler
will not move a shared source while a gem in it is still pinned. Name both and the source
moves, so they can never end up on different revisions.

**The verb reference lives in the framework**, at `.claude/rules/dsl-reference.md` in the
ruby-gba checkout. Read it there rather than copying it here: it is large, it changes with
every verb, and a copy would be wrong within a week.

## Emulator & integration tests

Integration tests run the built cartridge in an emulator, reached through the framework's one
seam, `RubyGBA::Diagnostics::Verifier`. Behind that is **ruby-gba-emulator** — a headless
libmgba probe, and a gem of its own rather than part of ruby-gba, because building a cartridge
is pure Ruby and running one is not.

**Nothing here builds it.** It is a Gemfile line, and bundler builds its C extension on
install, per Ruby ABI — so changing Ruby version gets a rebuild rather than a library compiled
for another Ruby. It needs a C compiler and a system libmgba (`brew install mgba` /
`apt install libmgba-dev`).

It is **required, not optional**: if it cannot load, the emulator-backed tests **fail loudly**
rather than skipping.

## Running Tests

**`rake test:parallel` is how the suite is run.** It runs across processes and is several times
faster; bare `rake test` runs everything in one process and is slow enough to be the wrong
command every time. Reach for `rake test` ONLY to run one file or one test:

```bash
rake test:parallel                                              # the suite (JOBS=8 to pick a count)
rake test TEST=test/test_maps.rb                                # one file
rake test TEST=test/test_maps.rb TESTOPTS="--name=/pattern/"    # one test
```

No `bundle exec`: the Rakefile and `lib/wolf3d.rb` each require `bundler/setup` first, which
also carries the bundle into the processes the parallel runner spawns. `bundle exec` is still
needed for an executable that comes out of the bundle rather than out of this repository —
`bundle exec ruby-gba profile wolf3d.rb`.

See `.claude/rules/testing.md`.

## Testing strategy — assert behavior, at the right altitude

Test each layer the way a player experiences it, not by restating the code. There are two
altitudes here, and neither is the framework's.

- **Reading Wolfenstein's own files — assert against the game, not against ourselves.**
  A decoder is right when it agrees with the world: a map is the size the format says, a
  Huffman stream decodes to the byte count its header claims, a wall code finds both of its
  pictures. Where a real copy is needed, `game_data_or_skip` skips with a message and the
  suite still passes without one. Where a made-up one will do, `Wolf3D::Fixture::Release`
  builds a tiny release in memory — one room, one wall, known bytes — so the test runs on
  every machine. Prefer the fixture; keep the copy for the few tests that check us against
  the world.

- **Game behaviour — assert what a player would see, never the IR the build makes.** Build a
  small program through the DSL, run it on the framework's reference interpreter, and read
  the result: where the marker landed, which pixel is lit, what a variable holds. A
  tree-equality assertion is a change-detector — it restates the mapping and stays green
  even when a wrong mental model is baked into both sides. Don't write those.
  - **Fast path: the reference interpreter is a headless oracle.**
    `i = Reference.new.run(program); i.screen.pixel(x, y)` — or `i[:name]` for a variable.
    In-process, deterministic, no emulator. `test/test_first_person.rb` is the worked
    example: it builds the view over a one-room fixture level and reads the picture.
  - **Hardware path: the real cartridge** through `RubyGBA::Diagnostics::Verifier`, reached
    the way any game outside the framework must reach it. `test/test_wolf3d_on_hardware.rb`
    is the whole of it — keep it to the few things only the console can answer.
  - Supply input through the interpreter's `hold(:btn)` / `input_each_frame { }`, not by
    poking internal state.

- **A rule of the original game is a fact to be checked**, not an intention to be restated.
  Read it out of `~/open_source/wolf4sdl` and say so in the test's name or a comment, so the
  next reader can see where the number came from.

## Architecture

### Core Files

The build has three layers, and they load in that order (see `lib/wolf3d.rb`, whose `require`s
are commented with what needs what).

**Reading the game's own files** — nothing here knows about the console:

- `lib/wolf3d/codec/` — `rlew`, `carmack`, `huffman`: the three compressions the game's data
  uses. A map is Carmack over RLEW; the art and text are Huffman.
- `lib/wolf3d/game_data.rb` — finds your copy and says which release it is (`wolf3d.yml`, or
  `WOLF3D_DATA`). `maps.rb` / `level.rb` — GAMEMAPS and MAPHEAD, a floor as a grid of cells.
  `vswap.rb` — the walls, the things and the digitised sounds. `vgagraph.rb` — the menu art,
  the status bar's plate, the numerals and both proportional alphabets. `palette.rb` — the
  game's own 256 colours.
- `lib/wolf3d/fixture/release.rb` — a made-up release built in memory, so most of the suite
  runs with no copy of the game present.

**Turning that into a floor** — still no console:

- `doors.rb`, `pushwalls.rb`, `elevator.rb`, `rooms.rb` — what joins one part of a floor to
  another. `enemy.rb`, `behaviour.rb`, `guards.rb`, `scenery.rb` — the five kinds of enemy,
  how their states are laid out, and what stands in the rooms. `floors.rb` — all of it, per
  floor.
- `wall_atlas.rb`, `thing_atlas.rb`, `weapon_atlas.rb`, `bar_art.rb`, `menu_art.rb` — the
  pictures each of those needs, gathered into the atlases the cartridge ships.

**Building the cartridge**, which is where the framework's DSL appears:

- `first_person.rb` — the view down the corridor: the ray, the wall columns, the floor and
  ceiling. Most of a frame. `billboards.rb` — the things and enemies drawn into that view.
  `guard_mind.rb` — what a guard does about you. `weapons.rb`, `pickups.rb`, `dying.rb`,
  `lives.rb`, `victory.rb`, `status_bar.rb`, `sounds.rb` — the rest of playing.
- `menus.rb`, `title.rb`, `map_view.rb`, `palette_view.rb`, `art_view.rb` — the screens
  around the game.
- `lib/wolf3d.rb` — the dials (`WOLF3D_EPISODES`, `WOLF3D_FLOORS`, `WOLF3D_FROM`,
  `WOLF3D_START`, `WOLF3D_ARMED`, `WOLF3D_SCREEN`) and `GAME`, the one `RubyGBA.game` block.

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

### Writing code comments

- Comments are for humans and should read as if a human wrote them.
- Be concise for ordinary code, but **explain generously where the reader could not know**:
  the shape of Wolfenstein's own file formats, and what a rule of the original game is and
  why. The reader knows Ruby. They do not know GAMEMAPS, Carmack compression, or what a
  pushwall is. That teaching is the point.
- Say what the code IS, not what it used to be. No migration narrative, no "for now".
- Do not name the issue tracker, or an issue id, in a code comment.
- **No measured decimals in a comment.** A timing figure is specific to one emulator build and
  one moment, so it is stale as soon as anybody re-measures. Write what survives instead:
  counts and relationships. A measured number belongs somewhere dated by construction — a
  commit message, or the issue it came from.

### Writing commit messages

- Commit messages are for humans and should read as if a human wrote them.
- Be concise.
- Do not name the issue tracker, or an issue id, in a commit message. The `commit-msg` hook in
  `.githooks/` rejects one as a backstop; don't lean on it instead of just not writing it.
- Do not add a `Co-Authored-By` trailer. Do not say how many tests were added.
- Avoid AI "fluff" that sounds pleased with itself - be direct and get to the point.

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

### DSL conventions, which belong to the framework

The verb surface is ruby-gba's and is documented there, in `.claude/rules/dsl-reference.md` in
the ruby-gba checkout. Read it there; do not copy it here. A few habits it establishes and this
game follows:

- `flip` (not `negate`) for reversing direction; `copy :dest, :src` for assignment.
- Underscore prefix (`_ray_x`) for scratch/temp variables.
- `func` for subroutines, `scene` for game states, `case_var` for dispatch.
- A helper written as a plain Ruby method is emitted at **every** call site; a `func` is
  emitted once. That is a size difference, not only a speed one, and it is the thing about
  the framework you cannot work out by reading your own program.

## Finishing a piece of work
- Commit it, and keep the message for humans — see "Writing commit messages" above.
