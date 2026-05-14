# lillist — CLI

The `lillist` CLI is the command-line client for Lillist. Per design Section 6 it
has feature parity with the macOS app and shares its implementation with App
Intents through `LillistCore.CLIBridge`.

## Building

```bash
cd Packages/LillistCore
swift build -c release
```

The executable is produced at `.build/release/lillist`. Symlink it onto your
`PATH` or install via the macOS app's "Install CLI…" menu (Plan 7).

## Verbs

Every verb in design Section 6:

- **Creation / edit:** `add`, `edit`, `note`, `attach`, `link`, `nudge`
- **Status & tags:** `status`, `tag`, `pin`, `unpin`
- **Hierarchy:** `move`, `ls`, `show`
- **Trash:** `delete`, `restore`, `purge`
- **Tags:** `tags ls|add|rename|move|delete|tint`
- **Filters:** `filters ls|show|run|save|delete`
- **Search:** `search`, `count`, `eval`
- **Scripting:** `watch`, `export`, `completion bash|zsh|fish`, `version`
- **Plan-9:** `report-crash` (stub)

## Output formats

`--json | --ndjson | --tsv` switch from the default human-readable pretty tree
to a machine-parseable format. Pretty tree uses ANSI color on a TTY; pipe
through `cat` (or pass `--no-color` / `NO_COLOR=1`) for plain output.

## Exit codes

Per design Section 6:

- `0` success
- `1` generic
- `2` usage error (argument-parser, or `validationFailed`)
- `3` not found
- `4` ambiguous match
- `5` store unavailable (app not installed / iCloud not signed in)

## Stdin batch mode

Verbs taking a task identifier accept `-` to read identifiers from stdin (one
per line). Destructive verbs (`delete`, `purge`, `restore`, `move`,
`status … closed`) reject non-UUID tokens unless `--allow-fuzzy-from-stdin`
is set; the verb fails fast on the first ambiguous title rather than
partial-applying.

## Configuration

`~/.config/lillist/config.toml`:

```toml
output_format = "pretty"      # pretty | json | ndjson | tsv
sort = "deadline"              # any SortField raw value
time_zone = "America/Los_Angeles"
```

CLI flags override the config; the config overrides built-in defaults.
