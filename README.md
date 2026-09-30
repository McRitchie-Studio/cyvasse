# Cyvasse

Cyvasse, the hex strategy game, revived at https://cyvasse.mcritchie.studio.
Alex's first app (2014–15, [`amcritchie/Cyvasse`](https://github.com/amcritchie/Cyvasse),
Rails 4.1.4) rebuilt as a managed McRitchie Studio satellite. The epic plan is
`/Users/alex/projects/.agents/epics/cyvasse-revival.md`.

So far the app holds auth, theme and error logging from
[studio-engine](https://github.com/McRitchie-Studio/studio-engine), a public
landing page, the original art, a public `/pieces` gallery of it, and the
original site's `/rules` (with the tutorial's special-rules cards, now drawn
from live stats) and `/about` pages, their copy lightly edited. Unit stats for
`/rules` live in `app/models/rulebook.rb`; its army counts come from the
engine's `CyvasseRules::Units::ARMY`. And the game itself: `/play`, a public game against
the computer, played entirely in the browser, in whichever piece skin the
player picked; `/matches`, online matches between signed-in players, a turn
at a time; and live chat between players who have played each other: one
conversation per pair, on each match and in the `/conversations` Chat hub,
with an unread badge on the navbar's Chat link, and admin Conversations and
Message Board pages.

## Stack

| | |
|---|---|
| Ruby / Rails | 3.3.11 / 8.1 (matches the mcritchie-studio hub) |
| Engine | `studio-engine` from RubyGems (`~> 0.76`) |
| Database | Postgres |
| CSS / JS | Tailwind v4 (`tailwindcss-rails`), importmap, Turbo, Stimulus; Alpine from the engine |
| Realtime | ActionCable carrying Turbo Streams (the live chat): Heroku Redis in production (`REDIS_URL`), the in-process adapter in development and tests |
| Tier | managed satellite: PRs target `accepted`, which walks `accepted` → `release` → `main` |

## Art

Imported from the legacy repo and served through Propshaft
(`image_tag "pieces/vector/king.svg"`). All of it lives under
`app/assets/images/`:

| Path | What | Legacy source |
|---|---|---|
| `pieces/pencil/*.png` | The pencil skin, 11 pieces | `app/assets/images/pieces/` |
| `pieces/vector/*.svg` | The coloured vector skin, 11 pieces (verbatim) | `public/images/svgs/` |
| `backgrounds/`, `title/`, `hex.svg` | Page backgrounds, title wordmarks, the hex outline | `app/assets/images/cyvasse_*.png`, `hex.svg` |
| `thanks/` | The gSchool thanks photos | `app/assets/images/thanks/` |
| `backgrounds/home/*.webp` | The home page's background gallery: one action shot per piece, a 2:1 wide crop and a `-mobile` portrait crop each, at 1x and `-2x` | New: captured from `/play` (below) |
| `backgrounds/rules/*.webp` | The `/rules` banner: the enemy King at the end of a Dragon's lane, a 3:1 wide crop and a 16:9 `-mobile` crop | New: captured from `/play` (below) |

The home page's background (`HomeGallery`, `pages/_home_gallery`,
`home_gallery_controller.js`) crossfades through the eleven shots every 7
seconds from a random first piece. The hero is full bleed: the page puts it in
the layout's `:hero` slot, edge to edge between the navbar and `<main>`'s
centred container (never a `100vw` breakout, which counts the scrollbar and
scrolls the page sideways). Each crop comes at 1x and 2x (wide 1800 and
3600px, portrait 720 and 1440px, at most 150 KB and 250 KB), offered as a
`srcset` with width descriptors and `sizes="100vw"`, so a 2x laptop gets the
sharp file and a 1x screen the light one. Only the first slide carries its
`srcset` and is preloaded, by the same set (`imagesrcset`/`imagesizes`, no
`href`), so the browser fetches one file for it; each later one loads a slide
ahead of its turn, and
`prefers-reduced-motion` holds the first still. The shots are real board
states staged in `test/capture/home_gallery_capture.rb`, one scene per piece,
in the vector skin. Re-capture them (Chrome and `cwebp` needed; a re-run is
byte-identical) with:

```bash
bin/rails cyvasse:capture_home_gallery                     # all eleven
PIECES=dragon PREVIEW=1 bin/rails cyvasse:capture_home_gallery  # one, plus its whole board in tmp/home_gallery
```

The `/rules` banner comes from the same script's `RULES` scene, and is
preloaded like the gallery's first slide (the legacy screenshot it replaced,
with its baked-in unit stats, is gone):

```bash
bin/rails cyvasse:capture_rules_hero                       # also byte-identical on a re-run
```

`Piece` (`app/models/piece.rb`) is the lineup and resolves each skin's path.
The rasters were compressed on import (256-colour PNG, JPEG q82, title art
halved); `test/lib/art_assets_test.rb` fails on any raster over 250 KB, so
compress a new one before adding it. `public/favicon.png`, `public/favicon.ico`
(for browsers that ask for it unprompted) and the PWA icons are drawn from the
vector elephant, the legacy site's share image; `public/icon-maskable.png` is
the same art padded onto parchment so a round mask never crops it. Left
behind: user uploads, the Game of Thrones actor photos, `dragonOld.svg`,
`human.svg`, `unFilteredSVGs/`, the tutorial `draft1/` drafts, and the tutorial
screenshots, whose baked-in stats had gone stale.

## The game

`/play` (`GamesController`, public) is one game against the computer. Nothing is
saved and no account is needed; matches and turns between players are a later
piece of the epic. The rules are the legacy engine's, ported line for line from
`amcritchie/Cyvasse` `app/assets/javascripts` into plain ES modules:

| Module (`app/javascript/cyvasse/`) | Legacy source |
|---|---|
| `units.js` | the unit table and the 19-piece army (`LoadFactory/createUnits.js`) |
| `board.js` | the 91-hex board, neighbours, mirroring (`LoadFactory/map.js`, `goodCode/neighbors.js`) |
| `potential_range.js` | the reach before blocking (`hexRange/potentialRange.js`) |
| `rules.js` | moves, captures, projectiles, mountain shadows (`hexRange/`) |
| `setups.js` | the computer's 18 opening lineups (`app/models/user.rb#cpu_opponent`) |
| `game.js` | setup, who moves first, turns, the cavalry double jump, the win |
| `ai.js` | the computer opponent (`ai.js`) |

### Unit rules

The numbers every rule reads live in `cyvasse/units.js` (`UNIT_TYPES`), mirrored
for the server in `app/models/cyvasse_rules/units.rb` and printed on `/rules`
from `app/models/rulebook.rb`; `test/models/cyvasse_rules/units_parity_test.rb`
and `test/lib/engine_rulebook_agreement_test.rb` keep the three equal. Alex's
stats of September 29, 2026:

| Unit | Move | Strength | Range | Trumps |
|---|---|---|---|---|
| Rabble | 3 | 1 | | King |
| Trebuchet | 0 | 1 | 4 | Dragon |
| King | 2 | 2 | | Dragon |
| Light Horse | 4 + 1 | 2 | | |
| Crossbowman | 1 | 2 | 2 | |
| Spearman | 2 | 3 | | |
| Heavy Horse | 3 + 1 | 3 | | |
| Catapult | 1 | 3 | 3 | Dragon |
| Elephant | 2 | 4 | | |
| Dragon | any distance in a straight line | 5 | | |
| Mountain | immovable, impassable | | | |

Strength is a unit's attack, and it defends at the same number, except the
three range units, which defend at 1: any unit can take one. An attacker takes
a defender of equal or lower strength. A trump works on offense only: a unit
takes any unit it trumps when it attacks, whatever the strengths, and a trump
never protects the unit that holds it, so a Dragon still takes the Trebuchet
that trumps it. The Dragon's captures ignore strength and trumps: it takes a
foot soldier and flies on, and it takes an enemy shooter or dragon but stops
there. A horse's two jumps are its move and then its `secondJump`.
Live matches play by the table the server has, so a change here applies to
matches already under way the moment it deploys.

`app/javascript/controllers/cyvasse_game_controller.js` draws the board and turns
clicks into `Game` calls; it holds no rules. Highlight borders are drawn once
per edge, full width, by whichever highlight owns it (`cyvasse/edges.js`:
selection > move rings > danger > threat perimeter; the last move draws no
edge, only a soft orange glow that fades away ten seconds after the move,
`cyvasse/last_move.js`; in the pencil skin that glow, and the selection's,
also rings the piece's parchment disc, `game.css` `--rim-glow`);
the threat outline draws only the rim of the opponent's reach (one solid red
rim; `PERIMETER_STYLE = "dual"` in `cyvasse/edges.js` draws melee's solid and
ranged's dashed instead), and its two switches, "Ranged threats" (crossbowman, trebuchet, catapult: `RANGED_UNITS` in
`cyvasse/units.js`) and "Melee threats" (every other unit), each show or hide
their own units' share. The board plays from the keyboard
too (it is one tab stop: arrows move between hexes, Enter or Space selects),
and when a side has no legal move its turn passes and the page says who passed
(`cyvasse/banner.js`); if neither side can move the game is a draw. `/rules`
states that rule. The modules import each other as
`cyvasse/<module>`, pinned in `config/importmap.rb`.

## Player avatars

The match header reads `[avatar] you vs them [avatar]` (`matches/_versus`).
`players/_avatar` draws one avatar anywhere, in Tailwind utilities alone: a
person's uploaded picture, else their own piece of the vector art on a
parchment disc ringed in `User#avatar_color` (`AvatarsHelper#user_piece`: a
stable hash of the user id over every piece but the mountain, so a player keeps
one piece on every page and in every game). A
computer player shows the portrait its seed set: `users.portrait`, a path under
`app/assets/images/bots/` (`qavo`, `tyrion`, `haldon`, `doran`, `ben`, `aegon`,
each a square WebP of the old Cyvasse app's picture; `User::COMPUTER_PORTRAITS`).
`bin/rails db:seed`, and the narrower `bin/rails users:seed_computer_players`
(the post-deploy command), create any missing named computer player and set its
portrait in place, so a re-run is safe. A computer player with no portrait
(legacy ids 8-10), or whose file is missing, shows its own piece of the vector
art on a parchment disc ringed in the computer accent (`AvatarsHelper::BOT_PIECES`).
The Play Now splash wears the same faces: your avatar is `players/_avatar`
rendered into the page, and the opponent's arrives rendered by that partial as
`opponent_avatar` in the seek's JSON. "You" and "Computer" under the names are
the versus card's quiet small-caps caption (`.player-caption`), not pills. The artists the old files credit are thanked on `/about`.

## Piece skins

Every piece is drawn in two skins, pencil and vector. A **Piece art** toggle on
`/play`, `/pieces` and `/rules` (`app/views/skins/_toggle.html.erb`) switches
between them with `PATCH /skin` (`SkinsController`, public). The choice is kept
in the permanent `cyvasse_skin` cookie and, for a signed-in player, in
`users.piece_skin`, so it follows them to another browser. On `/play` the
switch redraws a game in progress without a reload.

`PieceSkinPreference#current_skin` answers which skin a page draws, first match
wins: `?skin=pencil|vector` on the URL (a one-off look, never saved), then the
account's column, then the cookie, then vector. `/pieces` shows both skins with
the one in use first.
`test/lib/engine_rulebook_agreement_test.rb` keeps the `/rules` card's numbers
and the engine's in step.

## Online matches

`/matches` (My games) is where a signed-in player challenges another by
username, sets up, and plays, one turn at a time with seven days to make each
move. It needs an account and a public username (`/username`, 3-20 letters,
digits or underscores, unique in any case); matches are visible to their two
players only.

| Step | Where |
|---|---|
| Challenge by username; the challenged player is emailed | `POST /matches` → `Match.challenge!` |
| Accept or decline; the challenger may set up at once. A challenge declined or withdrawn in time is deleted, as in the legacy app; one whose seven days ran out is kept as `expired` | `POST /matches/:id/accept`, `DELETE /matches/:id` |
| Each player submits their army from their own seat; the second one starts the game and the first mover is emailed | `POST /matches/:id/setup` (JSON) → `Match#set_up!` |
| Whole turns, checked on the server; the next player is emailed | `POST /matches/:id/moves` (JSON) → `Match#play!` |
| Resign | `POST /matches/:id/resign` |

**The server checks every move by the browser's rules.** The engine in
`app/javascript/cyvasse` stays the source of truth; `app/models/cyvasse_rules`
is a line-for-line Ruby mirror of its board, reach, rules and turn flow, and
`Match#play!` refuses any turn it does not allow. The two are held together
by a recorded fixture: `bin/rules-agreement` asks the JS engine for its moves
and captures on 60 seeded positions (both jumps for cavalry), for six whole
seeded games, and for four set positions that reach a pass and a stalemate
draw (random games never do), and writes `test/fixtures/files/rules_agreement.json`.
`test/javascript/agreement_fixture_test.js` fails if the engine no longer
gives those answers, and `test/models/cyvasse_rules/js_agreement_test.rb`
fails if the Ruby port does not. `test/models/cyvasse_rules/units_parity_test.rb`
reads `units.js` itself and holds `CyvasseRules::Units` to it row for row, so a
unit's number changed in one language only goes red even where no recorded
position exercises it. **Change a rule in `app/javascript/cyvasse`,
run `bin/rules-agreement`, and port the change until both lanes are green.**
A regenerated record replays different games, so the match tests' recorded
game (`test/support/match_play.rb`) can change its length and its winner; the
match tests name who wins it.

**Seats.** Matches are stored exactly as the legacy app stored them, from the
home seat: home is team 1 on hexes 52-91, away is team 0 on hexes 1-40, and
`whos_turn` is 1 for home. The away player's board is the same board turned
round (hex 92 - n); `Match#state_for` does that turn for the browser, and
withholds the opponent's army until both are in.

**The clock.** `time_of_last_move` starts a seven-day clock (the legacy rule).
When it runs out, the player to move forfeits (a win and a loss on the
players' records); an unplayed challenge simply expires. The rule is enforced
whenever either player opens My games or the match, and on any late move,
resignation, acceptance or army (a stale page cannot overturn the forfeit), so
it needs no scheduler; `bin/rails matches:expire` sweeps every match and may
be run daily by one.

**The live setup clock.** A live match gives both players 60 s to set up
(`LiveMatch::SETUP_CLOCK`). A match made by Play Now starts that clock after
the "You vs them" splash (`LiveSeek.splash_time`, 5 s), not when the match is
made: `Match.start_live!(..., setup_grace:)` sets `clock_started_at` that far
ahead, so the deadline is one server time and both players get the same 60 s
once their boards open. During setup the board and the whole army card stay
on the screen together on every touch screen (`game.css`, "setup layouts"):
under 1024px the card docks as a sheet, under the board held upright and
beside a height-sized board on its side; a tablet on its side keeps the
desktop's two columns with the board capped to the screen.

**The computer's pace.** The computer plays in steps a player can follow:
it selects a unit after 2-5 s, moves it 3-5 s later, and makes a cavalry
unit's second jump 2-3 s after that. On `/play` the browser times it
(`cyvasse/pacing.js`); in a live match the server does (`LiveMatch::BOT_PACING`):
the turn is chosen up front into `matches.bot_plan`, each step is written
when due so the polling board shows the selection, and the turn is played
only when its last step lands, which is when the other player's clock starts.
The test suite sets `LiveMatch.bot_pace = 0` (and `/play`'s `pace` value to 0)
so a computer turn is instant.

**Legacy columns.** The `matches` table and `users.username`, `wins` and
`losses` keep the legacy names, types and nullability (see the
`CreateMatches` migration for the column encoding), so the legacy rows import
as they are. The users unique index is on the exact username, as the legacy
uniqueness was; the model refuses a new name that collides in any case.

## Remote computer players (bot API)

A computer player can be played by a program running off the server: Tyrion's
runner first (the design is `mcritchie-studio/docs/agents/agents/tyrion/runtime.md`).
It speaks JSON to `/api/bot` with `Authorization: Bearer <token>`, never a
session, and may do only what a signed-in player could do from a browser, in
its own matches (anyone else's is a 404). It polls outward; nothing on the
runner's machine needs to be reachable.

| Call | What |
|---|---|
| `GET /api/bot/inbox?after=<message id>` | Its unfinished matches, each with the `action` waiting on it (`setup`, `move` or none), and the chat messages sent to it after the cursor (answer's `cursor`). Settles live clocks, and is the runner's heartbeat |
| `GET /api/bot/matches/:id` | `Match#state_for` from its seat |
| `POST /api/bot/matches/:id/setup` | `{ lineup }`, through `Match#set_up!` |
| `POST /api/bot/matches/:id/moves` | `{ steps }`, through `Match#play!`, checked by the rules like any turn |
| `POST /api/bot/matches/:id/messages` | `{ message }`, under the chat's rules |

`BotToken` keeps only the SHA-256 digest; only a computer player
(`User#computer?`) may hold one, and a revoked token or one whose account is no
longer a computer player answers 401. Calls are rate-limited per token (300 a
minute). Tokens are an operator act:

```bash
bin/rails "bot_tokens:issue[tyrion]"   # prints the token once, alone on stdout
bin/rails bot_tokens:list              # ids, owners, last heard; never tokens
bin/rails "bot_tokens:revoke[<id>]"
```

Nothing seats a remote player yet: Play Now still gives its computer seat to
the in-app bot (`away_bot`), whose seat the API cannot play. Switching Play Now
to a runner that has been heard from (`BotToken.heard_from?`) is the next piece.

## Tyrion's runner

`bin/tyrion` plays the `tyrion` computer player's matches from any machine
that can reach the site, over the bot API (`/api/bot`, a bearer token from
`bin/rails "bot_tokens:issue[tyrion]"`). It only calls out; nothing on its
machine listens. The character, his setups and the threat model are in the hub
(`mcritchie-studio/docs/agents/agents/tyrion/`).

| File (`script/tyrion/`) | What |
|---|---|
| `brain.mjs` | His five setups and his turn search: every legal turn (both cavalry jumps) scored by material and temperament, charged for the opponent's best capture in reply. It imports the engine unchanged, so its turns are the server's legal turns |
| `voice.mjs` | His chat prompt, stock lines, the filter every line passes (280 characters, no links, no emails, none of the runner's secrets) and the budget (one reply per message, 20 a match, 40 to one player a day) |
| `chat.mjs` | Optional replies through the Claude API (`@anthropic-ai/sdk`, installed in `script/tyrion` on the runner machine only); the model has no tools, and a message asking for keys, cards or his instructions gets his stock answer instead of a model call |
| `runner.mjs` | The loop: poll the inbox (every 2 s while a live match is on, 30 s otherwise), set up, move, talk |

```bash
CYVASSE_BOT_TOKEN=... bin/tyrion                     # stock lines only
cd script/tyrion && npm install @anthropic-ai/sdk && cd -
CYVASSE_BOT_TOKEN=... ANTHROPIC_API_KEY=... bin/tyrion   # with chat (TYRION_CHAT_MODEL, default claude-opus-5-5)
```

Give the model key its own workspace and a hard monthly spend limit: the
budget above caps what one player can make him say, not what the key can
spend. `test/javascript/tyrion_*_test.js` hold his setups to the rules (no
first-turn king capture by a dragon, horse, elephant or rabble), his search to
beating the legacy computer, and the runner to the API contract.

## Legacy import

`bin/rails legacy:import` (`LegacyImport`, `lib/tasks/legacy.rake`) loads the
old Cyvasse's players, matches, messages and saved lineups from the CSV export
of the personal `cyvasse-game` database (`users.csv`, `matches.csv`, and, when
the folder holds them, `messages.csv` and `setups.csv`, from `heroku pg:psql`
`\copy ... TO ... CSV HEADER`). The export holds emails, password hashes and
private messages: keep it out of the repo, and never paste a row anywhere. The
task prints counts only, and the run logs no SQL (`insert_all` writes its
values into the statement).

```bash
LEGACY_CSV_DIR=~/Backups/heroku-personal-2026-09-25/csv bin/rails legacy:import
```

- **Idempotent.** Each row keeps its old id in `users.legacy_id` /
  `matches.legacy_id`; a rerun inserts only the ids it lacks and never updates
  a row, so running it twice changes nothing. One transaction: a failure
  imports nothing. Later pieces (messages, setups) map legacy rows through
  these ids.
- **A failure prints no row.** The database quotes the failing row in its
  error, so the task replaces it: it exits 1 with one line naming the table,
  the batch and its legacy id range (or the step), and the error's class,
  such as `Legacy import failed: messages batch 3 of 47 (legacy ids
  2001-3000), ActiveRecord::NotNullViolation.` Find the row by those ids in
  the CSV on your own machine; never paste it.
- **Players.** Username, wins, losses and joined date come over as they were;
  the email is trimmed and downcased (the engine's sign-in looks it up that
  way). The password hash and every other profile column are never read:
  players sign in by magic link. Nobody is made an admin; no email is sent.
- **Duplicate names.** Once trimmed and compared in any case, some legacy names
  collide. The earliest account (lowest legacy id) keeps the name; every later
  one, and any legacy name a player of the new app already holds, becomes
  `<name>_<legacy id>`. A shared email goes to the earliest account; the later
  one imports without an email.
- **Messages.** Every column comes over one to one, the text as it was (blank
  ones included, and hidden when shown), sender and receiver mapped through
  `users.legacy_id`. A message addressed to nobody or to a missing player is
  skipped and counted. A message whose match was not imported (deleted on the
  old site) keeps its conversation without a match.
- **Board posts.** The old public message board (`/message_board`) was the
  messages rows with receiver 0 and match 0 (638 in the 2026-09-25 export).
  They import to `board_posts`, each to its author through `users.legacy_id`,
  and are counted apart from the messages; one whose author is missing is
  skipped and counted. See [Messages](#messages).
- **Lineups.** Every saved lineup comes to its owner under its legacy columns
  (`setups`, see [Saved lineups](#saved-lineups)); one whose owner is missing
  is skipped.
- **Computer opponents.** Legacy ids 2-10 were the computer players (the away
  seat of every computer match). They import with no email, so nothing is ever
  mailed to them, and `User#computer?` refuses a challenge to them: the
  computer lives on `/play`.
- **Matches.** Every legacy column comes over verbatim. The winner, which the
  old app never stored, is derived as its code decided it: a king in the
  graveyard (`king`); a finished human match with a player on the move lost on
  the clock (`forfeit`); a finished human match never started (`expired`, no
  winner). Every unfinished match, and a finished computer match with no king
  taken, closes as `finished` / `abandoned` with no winner, so the seven-day
  clock never forfeits a years-old game. Win/loss counters are not touched:
  `wins`/`losses` are the legacy records. A match whose player is missing from
  `users.csv` is skipped and counted.

A full run of the 2026-09-25 export into a desk database imported 18,789
players, 107,940 matches, 46,338 messages (638 addressed to nobody skipped)
and 5,004 lineups (9 saved from the away seat, 1 not a whole army); a rerun
imported nothing.

To run it against production, point a local run at the app's database
(`DATABASE_URL="$(heroku config:get DATABASE_URL -a cyvasse)"`) rather than
copying the CSVs onto a dyno. That run is an operator act with Alex.

## Saved lineups

The setup panel on `/play` and on an online match lists the signed-in
player's three saved lineups. **Load** places the whole army on the player's
rows at once (it can still be rearranged by hand before starting or
submitting); **Save** stores the army on the board, under the name typed, in
that slot, replacing what it held. A visitor is offered sign-in instead.

| Where | What |
|---|---|
| `setups` table, `Setup` | legacy columns kept: `name`, `units_position` (the army from the owner's seat, the legacy `unitIndex:hex` string), `button_position` (the slot, 1-3), `legacy_id` |
| `POST /lineups` (JSON `{ slot, name, lineup }`) | save a slot; answers every slot, or 422 with the reason |
| `setups/_panel`, `cyvasse_setups_controller.js` | the panel; it asks the board to place a lineup (`Game#loadLineup`) or to hand over the army to save |

The legacy save sometimes left two lineups in one slot; both import, and the
newest is the one shown. A handful of legacy lineups were saved from the away
seat (hexes 1-40) and are turned round when loaded; one that is not a whole
army is kept but never offered.

## Openings

Every player, signed in or not, also gets **Openings** in the setup panel:
twenty-five named lineups, each built round one idea, with a line saying what it
is for. **Load opening** places it exactly as a saved lineup is placed. They
are drawn row by row in `app/javascript/cyvasse/openings.js` (a letter per
hex), and `test/javascript/openings_test.js` holds each to the rules: a whole
army on the player's rows, and, all but the King's Gambit and Crown Forward, a
king that survives the enemy's first turn. `cyvasse/king_safety.js` decides
that: it stands every enemy unit type on every hex of their five rows and plays
every first turn it has, a light horse's double jump through a capture, a
dragon's flight and a shot included. **✨ Smart Setup** deals only openings
that pass it (with both elephants in front), and **Place All** chooses, and if
need be rearranges, the units it places so the king passes it wherever the
player's own placements allow. The picker names the opening on the board after
a Smart Setup or a load, and says **Custom** for any other whole army.

On the board every unit's hex carries a faint rim of its team's colour from
the edge in (blue yours, red theirs), the same for every piece. How much a
piece matters shows in the size of its art instead, in three tiers
(`sizeTier` in `cyvasse/units.js`, scaled in `app/assets/stylesheets/game.css`):
rabble, spearman and crossbowman are small; the king and both horses a bit
bigger; the trebuchet, catapult, elephant, dragon and mountains biggest. In the
pencil skin the parchment disc and its drawing scale together. A piece stands
on its tile (`cyvasse/art_clip.js`): its art is cut along its hex's right,
lower-right and lower-left sides, and may rise past the upper-right,
upper-left and left ones over the hexes behind it. The hexes draw back to
front, rows top to bottom and each row left to right, so rising art covers
the hexes behind it; the highlight borders, the threat outline among them,
draw over all the art. The art never takes a click: the hex under it is the
whole hit target, even where a neighbour's art reaches over it.

## Leaderboard

The landing page shows the live leaderboard's top ten under Play Now;
`/leaderboard` has the whole live board and an **All-time** tab. The rule is
written out in `app/models/leaderboard.rb`:

- **Live** counts wins in live matches (`Match.live`, the Play Now games from
  the 2026-09-29 relaunch on). A win counts only from a human seat that no
  computer took over: a computer player's win never counts, and a stand-in's
  (a seat taken over after two missed clocks) counts for nobody. Wins over
  computer players count. Computer players, guests and accounts with no
  username never appear. Ranked by wins, then fewest losses, then the most
  recent win (`matches.finished_at`).
- **All-time** is the won/lost record on the account (`users.wins`,
  `users.losses`): the legacy totals plus every result since. `Match#finish!`
  puts a result on a record only when a person played the seat, so computer
  players and stand-ins gain neither wins nor losses.

**Guests sign in to claim.** When a match ends on the board, a modal on the
engine's modal host (`modals/_game_over`, registered in
`modals/_host_extras`) gives the result. A Play Now guest is asked to "Sign in
to keep your record" (a win that counts adds that it goes on the live
leaderboard) or to play another game; a signed-in player may play again or
close it and look over the final board. It opens when the game ends while the
page watches, however it ends (a move, a resignation, a clock, a computer
holding a seat), or when a live match that ended in the last five minutes is
opened (`just_ended` in the live state); an older finished match keeps its
result on the board. A page out of sight (another tab, window or app) waits
until the player is back before opening it, so the click that brings them
back cannot close it unseen. Sign in opens the sign-in modal
(`modals/_auth`, the hub's card): Google, where the app has it, then the
engine's magic link, both bringing the player back to the match. On sign-in,
`GuestClaim` moves the guest's match seats, wins, searches and chat to the
account, its saved lineups into the slots the account has free, and its piece
art if the account chose none; adds the guest's record to the account's and
deletes the guest, or keeps it marked merged (`users.merged_into_id`) when it
played the account itself, so it is never claimed again. It runs from
`ApplicationController#set_app_session`, so every sign-in path claims; the
session keeps the guest's id under `:guest_user_id` so a guest who signed out
first is still claimed, and a failed claim is logged without blocking the
sign-in. When the email link is opened in another browser, the return address
carries a signed `claim` token (one day) that does the same. Only this
browser's guest is ever claimed: no guest id is read from a request. An
account with no username is asked to choose one before the board.
`/leaderboard/join` is the sign-in page for a browser without script.

## Email results

A player who arrives from a McRitchie Studio email carries `?ref=<delivery
token>` from the hub's click redirect. `EmailReferral`
(`app/controllers/concerns/email_referral.rb`) keeps it for thirty days and
reports results to the hub's email analytics as beacons: `signed_in` on the
first full page a signed-in player sees, `played_match` when a game starts or
an online army is accepted. `EMAIL_ANALYTICS_URL` names the hub; production
defaults to `https://mcritchie.studio`, anywhere else to `http://localhost:3000`,
so a desk or a test never reports to production.

## Messages

Players chat live with the people they have played (task cyvasse-live-chat).
A conversation is every message between two people, in any match or none, so
talk carries on from match to match rather than starting afresh; it is not a
table, but the unordered pair of a message's sender and receiver
(`Conversation`, `app/models/conversation.rb`). A message sent in a match's
chat still records the match.

**Who may message whom** is one rule, `User#can_message?`, checked on every
new message whichever way it is sent (a validation on `Message`):

- never yourself;
- between two people, only once they have shared a match: any match, in any
  status, a pending challenge and a legacy imported match included;
- a computer player only inside a match the two of them share, where its
  remote runner reads the chat (the bot API); never from the Chat hub.

A legacy conversation with someone you never played stays readable in the
hub; its thread has no composer and says to challenge them to talk again.

| Where | What | Who |
|---|---|---|
| The match page's chat card | The pair's whole conversation (the latest 50, "Load earlier messages" for more), live; the form posts to `POST /matches/:id/messages`. Shown against a person, or a computer player whose remote runner holds a live bot token (not Play Now's in-app computer). Enter sends on a keyboard; on a touch screen Enter is a new line and Send sends | the match's two players (anyone else: 404) |
| `/conversations` (the Chat hub; `/inbox` redirects here) | The player's conversations with people, newest first, each with avatar, name, last message, time and unread count; then "Say hi": people played and not yet messaged. Someone who has played no person is told to "Play a human to start a conversation", with Play Now. Computer players are never listed | the signed-in player, guests included |
| `/conversations/:user_id` | One whole thread, live, each message labelled with its match, and a composer (a message sent here is outside any match). Opens when there are messages between you or you may start one | the conversation's two people (anyone else: 404) |
| `GET /conversations/:user_id/messages` | `?before=<id>`: the "Load earlier messages" frame; `?after=<id>`: the messages since, as a Turbo Stream, for a page whose socket came back | the two people |
| `POST /conversations/:user_id/read` | Marks the conversation read (the chat calls it as messages arrive on screen) | the two people |
| `/admin/conversations` | Every conversation that ever happened, newest first, searchable by player (username, name or email), 25 a page, each linking its matches | admins only (anyone else: 404) |
| `/admin/conversations/:low-:high` | One conversation's every message, grouped by game (match number, status, winner, dates; messages outside any game in their own group), groups newest first and messages oldest first inside each; the first-named player's bubbles on the left, the second's on the right. Ten games a page, each showing its latest 200 messages with a link to the whole game (`?game=<match id>` or `?game=none`, 200 a page) (`ConversationThread`) | admins only |
| `/admin/matches/:id` | One match's facts and chat | admins only |
| `/admin/message_board` | The old public message board: every legacy post with text, newest first, 50 a page, each with its author and the date posted (`BoardPost`) | admins only (anyone else: 404) |

**Live updates** are Turbo Streams over ActionCable (`ChatBroadcasts`), on two
kinds of stream (`ChatStreams`):

| Stream | Carries | Subscribed by |
|---|---|---|
| `chat:user:<id>` | the navbar Chat badge, and the player's hub rows (a conversation moves to the top, its unread count changes) | every page a signed-in player opens (the layout) |
| `chat:pair:<low>-<high>` | each new message, appended to the thread | the hub thread and the match chat of those two |

A page subscribes with `turbo_stream_from ..., channel: ChatStreamsChannel`:
the stream name is signed by the server, and the channel also checks that the
socket's player (`ApplicationCable::Connection`, from the session cookie) is
the one the stream belongs to, so a signed name copied from someone else's
page streams nothing. There is no polling: Turbo's cable source reconnects by
itself, and on reconnecting (or on coming back to the tab) the chat asks for
the messages since its last one, since a broadcast sent while a socket was
down is not replayed. A broadcast, rendering included, never fails the write
that caused it (`Studio::Cable.safe_broadcast`).

**Unread.** The navbar Chat link's badge counts messages from people still
unread (never a computer player's): hidden at none, "9+" past nine; one
count through `index_messages_on_receiver_id_and_read`. A message is marked
read when its thread opens, or when it arrives in a hub thread or match chat
that is on screen in a visible tab, and the badge clears live.

**Sending** is limited to 20 messages a minute per player in each of the match
chat and the hub (Rails `rate_limit`), and to `Message::MAX_LENGTH` (1,000)
characters; text is escaped wherever it is shown.

**Blank messages** (empty or whitespace-only text: 10,778 legacy messages and
246 board posts) are kept in the tables and hidden everywhere they would be
shown or counted: the chat, the Chat hub and its unread counts, and every admin
page (`Message.with_text`, `BoardPost.with_text`). A conversation of blank
messages alone is not listed.

**The message board** is history, admins' alone (Alex, 2026-09-25): no
player-facing page shows a board post and nobody can post one. It has its
own table, `board_posts` (`message`, `user_id`, the timestamps, `legacy_id`),
not messages with a nullable receiver, so no private-message rule or query
can return a post.
The About page tells players that admins can read messages. No mail is sent
for a message.

**Legacy import.** The `messages` table keeps every legacy column (see the
`CreateMessages` migration): `message`, `read` and the timestamps as they
were, and `sender`, `receiver` and `match` as `sender_id`, `receiver_id` and
`match_id` foreign keys, which the importer maps through `users.legacy_id`.
`legacy_id` holds the legacy row's id, unique, so a re-run skips what it
already brought over. New-message rules (text present, at most 1,000
characters, sent between the match's players) apply to new messages only.

**Demo data.** `bin/rails db:seed` in development, or `bin/rails
messages:demo`, adds made-up players (`@example.com`), one to three finished
games per pair (with a few messages outside any game), about 220 messages
across 44 conversations, enough to page through
(`lib/demo_conversations.rb`; it refuses to run in production). It also gives
`alex@mcritchie.studio` the username `alex_mcritchie` if he has none, so his
seeded account has conversations of its own.

## Local development

```bash
bundle install
bin/rails db:prepare db:seed
bin/dev                      # web on :3600 plus the Tailwind watcher
```

Port **3600** is the app's own; desks take the rest of the 3600 range from
`bin/agent-worktree`, which exports `APP_PORT`. Three test lanes, all run by CI on
every PR and on `accepted`, `release` and `main`, alongside brakeman,
bundler-audit, importmap audit and rubocop:

| Command | What |
|---|---|
| `bin/rails test` | unit, component and integration tests (single-process), and a guard that fails on a committed merge-conflict marker (`lib/conflict_markers.rb`) |
| `bin/rails test:system` | browser tests in headless Chrome: a whole game against the computer (a win, a loss or a draw), keyboard play, the live chat between two browsers, and two players starting an online match |
| `bin/test-js` | the game engine's unit tests, on `node:test` (Node 20+, no npm install) |
| `bin/rules-agreement` | regenerate the JS engine's recorded answers the Ruby rules port is tested against |

The seeds create three identities: `alex@mcritchie.studio` (admin),
`mack@mcritchie.studio` (the ordinary member) and `alex@cyvasse.mcritchie.studio`
(admin). Sign in with a magic link; on a desk the mail lands in the local inbox at
`/_studio/local_emails`, and `/_studio/local_review?return_to=/` signs the seeded
admin in directly. Online-match mail (a challenge, "your move") rides the same
outbox, so it lands in that inbox too. To play yourself on a desk, sign in as
two of the seeded identities in two browsers (or one private window).

## Auth and hub SSO

Sign-in is passwordless: the engine's magic link, and Google through the engine's
`OmniauthCallbacksController` (`User.from_omniauth` links a Google identity to an
existing email only once Google has verified it). Google is on only where its OAuth
client is configured (`config/initializers/omniauth.rb`): `GOOGLE_CLIENT_ID` and
`GOOGLE_CLIENT_SECRET` set, with `https://cyvasse.mcritchie.studio/auth/google_oauth2/callback`
registered on the client. Unset, the app is magic link only and draws no Google
button. Google always lands on the home page; the sign-in modal passes
`?return_to=`, and the home page sends the player on to it once. Wallet sign-in is
off by design.

Hub SSO rides the session cookie: a player signed in on mcritchie.studio can
"Continue as ..." here only when this app reads the hub's cookie. That takes the
hub's cookie key and domain **and** the hub's `SECRET_KEY_BASE`, so it is one
opt-in switch (`config/initializers/session_store.rb`):

- `STUDIO_SSO_SHARED_COOKIE=true` (production only) uses `_studio_session` on
  `.mcritchie.studio`. Set it in the same change that sets the hub's
  `SECRET_KEY_BASE`; either one alone signs players out of the hub.
- Unset, the cookie is `_cyvasse_session` on the request host. Sign-in still
  works; the "Continue as" button just never appears.

## Email sign-in handoff and onboarding

The hub's "Cyvasse is back" emails sign a player in with one click. The hub
checks the click (a CTA works for 180 days after the send, and is reusable),
then redirects here with a short-lived assertion it signed; Cyvasse is only the
consumer (`EmailHandoffsController`, contract in `app/models/email_handoff.rb`):

```text
GET /auth/email_handoff?assertion=<JWT>&return_to=<local path>

alg  ES256 only            iss  "mcritchie.studio"     aud  "cyvasse"
sub  the email, lowercase  jti  16-128 chars, spent once (email_handoff_nonces)
iat  unix seconds          exp  exp - iat <= 300; 30 s clock skew either way
ref  the hub delivery token (kept for the email beacons)
```

A good assertion for an account signs it in (Play Now guests are claimed, as on
any sign-in) and marks the session `email_handoff`; an address with no account
lands on Play Now signed out; an admin account is refused and sent to sign in
with a magic link, since a reusable email CTA is too weak a proof for the admin
pages. Anything else lands on Play Now with no session.
The endpoint allows 10 requests a minute per IP, and `assertion` is a filtered
parameter. Without `MS_HANDOFF_PUBLIC_KEY` it fails closed and writes a
`EmailHandoff::NotConfigured` ErrorLog. A handoff session may play, chat and
onboard; changing the email or a sign-in method first emails a normal magic link
whose click confirms the session (`ConfirmedSession`).

After any sign-in, an incomplete account (`User#onboarding_due?`: a legacy player
not yet welcomed, no usable username, or no name) gets the onboarding once: welcome
back with the legacy record, username, name and piece skin, and how to sign in
plus "Keep me posted about Cyvasse" (stored with a timestamp in
`users.email_updates_at`). Every step but an unusable username can be skipped;
"Skip for now" resumes at the next sign-in. `/admin/sign_ins` shows handoff
outcomes and where the onboarding loses people.

## Environment

| Variable | Where | Purpose |
|---|---|---|
| `DATABASE_URL` | production, desks | Postgres connection |
| `REDIS_URL` | production | ActionCable's Redis for the live chat (Heroku Redis `heroku-redis:mini`, a `rediss://` URL; `Studio::Redis` turns off peer verification for its self-signed certificate). Unset, broadcasts fail quietly into ErrorLog and the chat still works on reload. Development and tests use the in-process adapter and need no Redis |
| `TEST_DATABASE_URL` | desks | the desk's isolated test database |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | production (optional) | Google sign-in; both unset, the app is magic link only |
| `MS_HANDOFF_PUBLIC_KEY` | production | the hub's ES256 (P-256) public key, PEM, for the email sign-in handoff; unset, the handoff fails closed. The private half lives only on the hub (1Password, credential-filing SOP) |
| `SECRET_KEY_BASE` | production | session and cookie encryption; the hub's value when SSO is on. The app keeps no `credentials.yml.enc` |
| `APP_HOST` | production | public host for links, default `cyvasse.mcritchie.studio` |
| `APP_PORT` | desks | the desk's port, default 3600 |
| `STUDIO_SSO_SHARED_COOKIE` | production | `true` joins the hub's SSO cookie (above) |
| `CYVASSE_SESSION_KEY` | desks | renames the dev cookie so two stacks on localhost do not collide |
| `MAIL_TRANSPORT`, `SES_SMTP_USERNAME`, `SES_SMTP_PASSWORD`, `RESEND_API_KEY`, `RESEND_MAILER_FROM` | production | mail transport (studio-engine `docs/EMAIL_TRANSPORT.md`) |

## Deploy

`Procfile` runs `bin/rails db:migrate` in the Heroku release phase (which
creates `matches`, `messages` and the users username/record columns). The release
conductor's post-deploy command is `bin/rails users:seed_identities`, which
idempotently seeds only the three identities above. The Heroku
app, Postgres and the `cyvasse.mcritchie.studio` domain are epic piece 8 and do
not exist yet. Object storage: none provisioned; Active Storage uses local disk
until an upload feature needs a bucket.

## Engine upkeep

After every `studio-engine` bump run
`bin/rails studio_engine:install:migrations && bin/rails db:migrate`;
`test/lib/engine_migrations_installed_test.rb` fails when one is missing.
