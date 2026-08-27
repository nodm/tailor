## Status line contents

The script in [.claude/statusline.sh](.claude/statusline.sh) builds a single status line from JSON input and prints these pieces in order:

- Directory:
  - `dir <basename of workspace/current_dir>`
  - or `dir ~` when no directory is set

- Git:
  - `branch <branch-name>`
  - if the repo is dirty, it adds the count: `(<dirty_count>)`
  - shows green for clean branch, yellow for dirty branch

- Model:
  - `model <model_name>`
  - adds `:<effort_level>` if an effort value is present, e.g. `model Claude Sonnet:medium`

- Context window:
  - `ctx <used_tokens>/<window_size> (<pct>%)`
  - example: `ctx 42k/200k (21%)`
  - uses red/yellow/magenta depending on usage level

- Cache:
  - `cache w:<write_tokens> r:<read_tokens>`
  - only shows when cache tokens are present

- Session usage:
  - `session 5h:<pct>% 7d:<pct>%`
  - derived from rate limits, only if available

![Claude Code status line](./statusline.sh.png)

`chmod 711 statusline.sh`
