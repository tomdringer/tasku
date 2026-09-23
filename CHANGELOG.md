# Changelog

All notable changes to Tasku are documented here.

## [0.4.0] - 2026-09-23

### Added
- **Tasku Cloud sync** — two-way sync with `tasku cloud sync`; authenticate with `tasku cloud login <token>`, check status with `tasku cloud status`, and revoke with `tasku cloud logout`
- **`tasku config open`** — opens the config file in `$EDITOR` pre-seeded with all available keys and their defaults
- **Numeric range preferences** — config keys that accept a numeric range (e.g. column minimum widths) now show their valid range in `tasku config list`
- **`--code` flag** on `add` and `edit` — attach a short code to a task (e.g. `MDO-42`)
- **`tasku sql`** — run a raw SQL `SELECT` query against the local database
- **Category filtering** — `tasku list --category` and category column in list output
- **Column visibility preferences** — `col_project`, `col_category`, `col_priority`, `col_status`, `col_due` can each be toggled `on`/`off` via `tasku config set`
- **Column minimum width preferences** — `col_name_min`, `col_priority_min`, `col_status_min`, `col_due_min` for fine-tuning layout
- **`tasku config open`** — open the config JSON in `$EDITOR` (pre-seeded with defaults)
- **UUID field** on tasks for stable cross-device identity during cloud sync

### Fixed
- **Mado: status filter preserved after add/edit/delete** — `MadoList` now receives the full `list_cmd` (including `--status`, `--today`, `--overdue`, etc.) and passes it to `exec` on return, so the active view is restored correctly after an interactive command
- **Mado: project filter preserved after add/edit/delete** — the inline-exec protocol (`\x02`) now replaces the MadoList process via `exec` instead of nesting it in a `system()` call, so the new MadoList inherits the correct `@list_cmd` and filter is preserved when navigating back from an interactive command
- **Mado: project filter lost on workspace switch** — the open-panel flag is now tracked correctly for sidebar-positioned Tasku (not just the top-bar overlay), so switching workspace reliably refreshes the task list with the new project filter
- **Mado: terminal left in raw mode after inline exec** — `$stdin.cooked!` is now called before `exec` when handling a `\x02tasku list` command, preventing the shell from inheriting raw-mode terminal attributes
- **Due date column truncation** — `DUE_COL_MIN_WIDTH` raised to 17 to accommodate the longest possible due cell (`"Mmm DD (NNNd ago)"`)
- **MadoList row overflow** — row prefix accounting corrected to 6 characters (`"  [>] "`), matching the actual rendered prefix; was previously 4, causing rows to exceed terminal width and wrap
- **Name truncation** — task names that exceed available space are now truncated with `…`; names that fit are never truncated, fixing cases where the due-date column wrapped to the next line
- **Column auto-drop on narrow terminals** — optional columns (project → category → priority → status) are dropped one at a time until at least 15 characters are available for task names, rather than wrapping or clipping

### Changed
- `tasku list` output uses a consistent `│`-separated column layout with a header row
- `tasku config set` validates values via `ArgumentError` rather than a plain string comparison, supporting range constraints
- `tasku stats` includes a "By Project" section sorted by task count
- Sort defaults to `id` (ascending) when no `--sort` flag is given
- `id` added as an explicit `--sort` option

---

## [0.3.9] - 2026-09-04

### Added
- **Mado TUI list mode** — `tasku list` launches an interactive cursor-driven list when `MADO=1` is set in the environment, designed for embedding in the Mado terminal multiplexer sidebar
- Arrow-key navigation, selected task ID written to `TASKU_SEL_FILE` for Mado button integration
- Inline-exec protocol (`\x02`) for receiving filter and display commands from Mado without shell round-trips
- `build_mado_rows` and `ansi_ljust` helpers exposed on `Output::Terminal` for Mado's renderer

---

## [0.3.1] - 2026-08-29

### Fixed
- Terminal width was capped at 80 columns regardless of actual PTY size, severely truncating the name column in wider terminals — now uses the real terminal width

### Changed
- `tasku list` sorts by `id` by default
- `exit_on_failure?` enabled on the CLI so bad subcommands exit with a non-zero status

---

## [0.3.0] - 2026-07-24

### Added
- **Project colours** — `tasku colour PROJECT #HEX` stores a hex colour per project; project names are tinted throughout `list`, `show`, and `stats`
- **Colour bar** — three-segment bar in `tasku list` showing project, priority, and status at a glance (toggle each segment with `tasku config set bar_project on/off` etc.)
- **User preferences** — `tasku config list` / `tasku config set KEY VALUE` / `tasku config get KEY`, backed by `~/.tasku/config.json`
- `list_spacing` preference (`compact` / `spacious`)
- **"By Project" section** in `tasku stats` sorted by task count
- Logo restored on `tasku help` and bare `tasku` invocation

---

## [0.2.0] - 2026-07-01

### Added
- `tasku projects` — list all projects with task counts and colour swatches
- `tasku categories` — list all categories
- `tasku done ID` — shorthand to mark a task done
- `--overdue`, `--today`, `--tomorrow` filter flags on `tasku list`
- `--sort` and `--order` flags on `tasku list`
- `--priority`, `--status`, `--tags` filter flags on `tasku list`
- `--force` / `-f` flag on `tasku delete` to skip confirmation

---

## [0.1.0] - 2026-06-29

Initial release.

- `tasku add`, `tasku list`, `tasku show`, `tasku edit`, `tasku delete`
- SQLite-backed storage at `~/.tasku/tasks.db`
- Task fields: name, description, project, category, priority, status, start date, due date, tags, estimated hours
- `tasku stats` — task breakdown by priority and status
- Interactive add/edit with `-i` flag (TTY::Prompt)
