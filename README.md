# Cyvasse

Cyvasse, the hex strategy game, revived at https://cyvasse.mcritchie.studio.
Alex's first app (2014–15, [`amcritchie/Cyvasse`](https://github.com/amcritchie/Cyvasse),
Rails 4.1.4) rebuilt as a managed McRitchie Studio satellite. The epic plan is
`/Users/alex/projects/.agents/epics/cyvasse-revival.md`.

So far the app holds auth, theme and error logging from
[studio-engine](https://github.com/McRitchie-Studio/studio-engine), a public
landing page, the original art, a public `/pieces` gallery of it, and the
original site's `/rules` (with the tutorial's special-rules cards) and `/about`
pages, their copy lightly edited. Unit stats for `/rules` live in
`app/models/rulebook.rb`. And the game itself: `/play`, a public game against
the computer, played entirely in the browser, in whichever piece skin the
player picked; `/matches`, online matches between signed-in players, a turn
at a time; and messages between players: a chat on each match, an `/inbox`,
and an admin Conversations page.

## Stack

| | |
|---|---|
| Ruby / Rails | 3.3.11 / 8.1 (matches the mcritchie-studio hub) |
| Engine | `studio-engine` from RubyGems (`~> 0.76`) |
| Database | Postgres |
| CSS / JS | Tailwind v4 (`tailwindcss-rails`), importmap, Turbo, Stimulus; Alpine from the engine |
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
| `tutorial/`, `thanks/` | Tutorial figures and the gSchool thanks photos | `public/images/tutorial/`, `public/images/thanks/` |

`Piece` (`app/models/piece.rb`) is the lineup and resolves each skin's path.
The rasters were compressed on import (256-colour PNG, JPEG q82, title art
halved); `test/lib/art_assets_test.rb` fails on any raster over 250 KB, so
compress a new one before adding it. `public/favicon.png`, `public/favicon.ico`
(for browsers that ask for it unprompted) and the PWA icons are drawn from the
vector elephant, the legacy site's share image; `public/icon-maskable.png` is
the same art padded onto parchment so a round mask never crops it. Left
behind: user uploads, the Game of Thrones actor photos, `dragonOld.svg`,
`human.svg`, `unFilteredSVGs/`, and the tutorial `draft1/` drafts.

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

`app/javascript/controllers/cyvasse_game_controller.js` draws the board and turns
clicks into `Game` calls; it holds no rules. The board plays from the keyboard
too (it is one tab stop: arrows move between hexes, Enter or Space selects),
and when a side has no legal move its turn passes and the page says who passed
(`cyvasse/banner.js`); if neither side can move the game is a draw. `/rules`
states that rule. The modules import each other as
`cyvasse/<module>`, pinned in `config/importmap.rb`.

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
fails if the Ruby port does not. **Change a rule in `app/javascript/cyvasse`,
run `bin/rules-agreement`, and port the change until both lanes are green.**

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

**Legacy columns.** The `matches` table and `users.username`, `wins` and
`losses` keep the legacy names, types and nullability (see the
`CreateMatches` migration for the column encoding), so the legacy rows import
as they are. The users unique index is on the exact username, as the legacy
uniqueness was; the model refuses a new name that collides in any case.

## Legacy import

`bin/rails legacy:import` (`LegacyImport`, `lib/tasks/legacy.rake`) loads the
old Cyvasse's players and matches from the CSV export of the personal
`cyvasse-game` database (`users.csv`, `matches.csv`, from `heroku pg:psql`
`\copy ... TO ... CSV HEADER`). The export holds emails and password hashes:
keep it out of the repo, and never paste a row anywhere. The task prints counts
only.

```bash
LEGACY_CSV_DIR=~/Backups/heroku-personal-2026-09-25/csv bin/rails legacy:import
```

- **Idempotent.** Each row keeps its old id in `users.legacy_id` /
  `matches.legacy_id`; a rerun inserts only the ids it lacks and never updates
  a row, so running it twice changes nothing. One transaction: a failure
  imports nothing. Later pieces (messages, setups) map legacy rows through
  these ids.
- **Players.** Username, wins, losses and joined date come over as they were;
  the email is trimmed and downcased (the engine's sign-in looks it up that
  way). The password hash and every other profile column are never read:
  players sign in by magic link. Nobody is made an admin; no email is sent.
- **Duplicate names.** Once trimmed and compared in any case, some legacy names
  collide. The earliest account (lowest legacy id) keeps the name; every later
  one, and any legacy name a player of the new app already holds, becomes
  `<name>_<legacy id>`. A shared email goes to the earliest account; the later
  one imports without an email.
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

To run it against production, point a local run at the app's database
(`DATABASE_URL="$(heroku config:get DATABASE_URL -a cyvasse)"`) rather than
copying the CSVs onto a dyno. That run is an operator act with Alex.

## Messages

Players talk in a chat on each match, and read every conversation in their
`/inbox`. A conversation is every message between two people, in any match
or none; it is not a table, but the unordered pair of a message's sender and
receiver (`Conversation`, `app/models/conversation.rb`).

| Where | What | Who |
|---|---|---|
| The match page's chat card | A Turbo frame loaded from `GET /matches/:id/messages` and reloaded every 8 s while the tab is visible (a reader scrolled up keeps their place, and a refused message's error stays up); the form posts to `POST /matches/:id/messages`. Enter sends on a keyboard; on a touch screen Enter is a new line and Send sends. New messages are announced to screen readers | the match's two players (anyone else: 404) |
| `/inbox` | The player's conversations, newest first, with unread counts; 25 a page | the signed-in player |
| `/conversations/:user_id` | One whole thread, each message labelled with its match, and a reply box (a reply is sent outside any match) | the conversation's two people (anyone else: 404) |
| `/admin/conversations` | Every conversation that ever happened, newest first, searchable by player (username, name or email), 25 a page, each linking its matches | admins only (anyone else: 404) |
| `/admin/conversations/:low-:high` | One conversation's every message, grouped by game (match number, status, winner, dates; messages outside any game in their own group), groups newest first and messages oldest first inside each; the first-named player's bubbles on the left, the second's on the right. Ten games a page, each showing its latest 200 messages with a link to the whole game (`?game=<match id>` or `?game=none`, 200 a page) (`ConversationThread`) | admins only |
| `/admin/matches/:id` | One match's facts and chat | admins only |

Opening a thread or a match chat marks the messages addressed to you as read.
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
| `bin/rails test:system` | browser tests in headless Chrome: a whole game against the computer (a win, a loss or a draw), keyboard play, the match chat, and two players starting an online match |
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

Sign-in is passwordless magic link only (`config/initializers/studio.rb`). Google
and wallet sign-in are off by design; adding Google is a config change because the
`users` table already carries `provider` and `uid`.

Hub SSO rides the session cookie: a player signed in on mcritchie.studio can
"Continue as ..." here only when this app reads the hub's cookie. That takes the
hub's cookie key and domain **and** the hub's `SECRET_KEY_BASE`, so it is one
opt-in switch (`config/initializers/session_store.rb`):

- `STUDIO_SSO_SHARED_COOKIE=true` (production only) uses `_studio_session` on
  `.mcritchie.studio`. Set it in the same change that sets the hub's
  `SECRET_KEY_BASE`; either one alone signs players out of the hub.
- Unset, the cookie is `_cyvasse_session` on the request host. Sign-in still
  works; the "Continue as" button just never appears.

## Environment

| Variable | Where | Purpose |
|---|---|---|
| `DATABASE_URL` | production, desks | Postgres connection |
| `TEST_DATABASE_URL` | desks | the desk's isolated test database |
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
