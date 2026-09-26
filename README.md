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
player picked.

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
compress a new one before adding it. `public/favicon.png` and the PWA icons
are drawn from the vector elephant, the legacy site's share image. Left
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
clicks into `Game` calls; it holds no rules. The modules import each other as
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
| `bin/rails test` | unit, component and integration tests (single-process) |
| `bin/rails test:system` | browser tests in headless Chrome: a whole game against the computer |
| `bin/test-js` | the game engine's unit tests, on `node:test` (Node 20+, no npm install) |

The seeds create three identities: `alex@mcritchie.studio` (admin),
`mack@mcritchie.studio` (the ordinary member) and `alex@cyvasse.mcritchie.studio`
(admin). Sign in with a magic link; on a desk the mail lands in the local inbox at
`/_studio/local_emails`, and `/_studio/local_review?return_to=/` signs the seeded
admin in directly.

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

`Procfile` runs `bin/rails db:migrate` in the Heroku release phase. The release
conductor's post-deploy command is `bin/rails users:seed_identities`, which
idempotently seeds only the three identities above. The Heroku
app, Postgres and the `cyvasse.mcritchie.studio` domain are epic piece 8 and do
not exist yet. Object storage: none provisioned; Active Storage uses local disk
until an upload feature needs a bucket.

## Engine upkeep

After every `studio-engine` bump run
`bin/rails studio_engine:install:migrations && bin/rails db:migrate`;
`test/lib/engine_migrations_installed_test.rb` fails when one is missing.
