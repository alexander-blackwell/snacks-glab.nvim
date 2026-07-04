# snacks-glab.nvim — Project Memory

Context file for agents and future maintainers. Read this before changing anything.

## What this is

A GitLab port of the built-in `gh` plugin from
[folke/snacks.nvim](https://github.com/folke/snacks.nvim) (Apache-2.0, see LICENSE),
driven entirely by the [`glab` CLI](https://gitlab.com/gitlab-org/cli). It was written
by porting the upstream `lua/snacks/gh/*` sources file-by-file and adapting every
GitHub concept to its GitLab equivalent. Upstream gh is the reference architecture:
when adding features, check how gh does it first and keep parity.

- Canonical repo: `github.com/alexander-blackwell/snacks-glab.nvim`
- Dev checkout: `~/projects/snacks-glab.nvim` (lazy.nvim `dev.path` default, so
  `dev = true` on the spec switches to it)
- Consumed from the dotfiles via `nvim/lua/plugins/snacks-glab.lua`
  (keys: `<leader>gi/gI/gp/gP/gC`)

## Architecture

```
lua/snacks/glab/
  types.lua        LuaCATS shapes for GitLab REST objects (Item, Note, Pipeline, Job, ...)
  item.lua         Item wrapper: normalization, ts() parsing, uri <-> repo/type/iid
  api.lua          all network: spawns the glab binary; list/view/pipelines/jobs/trace
  actions.lua      action registry (lua actions + declarative cli_actions), palette, scratch editing
  buf.lua          glab:// buffers: attach, render, keymaps, autocmds
  render/init.lua  buffer rendering: props table, threaded discussions, diff annotations
lua/snacks/picker/source/glab.lua   finders, formats, previews, picker action adapter
plugin/snacks-glab.lua              registers picker sources + glab:// BufReadCmd bootstrap
tests/smoke.lua + tests/mock/glab   headless test suite against a mock glab binary
```

### How it hooks into snacks (no glue needed)

- snacks resolves finder/format/preview strings by module path: `finder = "glab_issue"`
  → `require("snacks.picker.source.glab").issue`. Shipping `lua/snacks/picker/source/glab.lua`
  on the runtimepath is the entire integration.
- Picker actions named `glab_*` resolve through the `M.actions` adapter table in the
  picker source module (metatable wraps `require("snacks.glab.actions").actions`).
  Any action name works as a picker keymap, e.g. `["r"] = "glab_ci_retry"`.
- Sources are registered by plain assignment into `require("snacks.picker.config.sources")`
  (snacks auto-wraps new keys so `Snacks.picker.glab_issue()` exists).
- User config lives under the **snacks.nvim** spec: `opts.glab` (read via
  `Snacks.config.get("glab", defaults)`) and `opts.picker.sources.glab_*`.
- `glab://{repo}/{type}/{iid}` buffers bootstrap via a `BufReadCmd glab://*` autocmd
  in `plugin/snacks-glab.lua` → `require("snacks.glab").setup(e)`.

### Data model

- Canonical id is GitLab's `iid`; `hash` renders `#42` (issue) / `!42` (MR).
- `repo` = full path with namespace; **subgroups are supported everywhere**. URIs are
  parsed from the END (`glab://group/sub/proj/issue/42`); repo extraction from web
  urls uses GitLab's `/-/` separator (`item.lua: get_repo/from_uri`). Never use
  `[^/]+/[^/]+` style matching for repos.
- glab has no `--json <fields>` selection like gh, so `api.view()` tracks
  **pseudo-fields** instead: `detail`, `discussions`, `awards`, `approvals` (MR only),
  fetched as 3–4 **parallel** `glab api` calls and merged into the Item. The item
  cache is weak-valued, keyed by uri.
- Item kinds: `"issue" | "mr" | "pipeline" | "job"`. Actions declare
  `type = kind | kind[]`; `nil` means issue+mr (historical default). Pipelines/jobs
  are plain finder items (shaped by `pipeline_item`/`job_item` in the picker source),
  not Item instances — `Api.refresh` no-ops for them (no `uri`).

### GitHub → GitLab decisions already made

| GitHub (gh) | Here |
|---|---|
| PR | MR (`mr` subcommands, `!` hash) |
| reactions API | award_emoji (aggregate counts client-side; one entry per user+emoji) |
| reviews / pending review | draft notes API (15.10+, Free tier): `glab_draft_note` / `glab_submit_review` (bulk_publish, optional approve) / `glab_discard_review`. "Request changes" is Premium-gated reviewer state — deliberately not ported |
| review comment hunks | positioned notes render hunks sliced client-side from `GET .../mr/:iid/diffs` (`diffs` pseudo-field); GitLab notes carry positions, never hunk text |
| status checks | `head_pipeline` + `checks` pseudo-field (chained fetch: latest MR pipeline -> jobs) rendered as a gh-style per-job breakdown; plus pipelines/jobs pickers |
| GraphQL for threaded comments | not needed — REST `/discussions` is natively threaded |
| draft toggle | `glab mr update --draft/--ready` |
| merge/squash/rebase-merge | merge (glab auto-merge default), `--squash`; rebase = rebase source branch |
| suggestion blocks | GitLab fence syntax ` ```suggestion:-N+0 ` |
| diff comments | REST discussions with `position` (needs `diff_refs` from detail fetch) |
| close as not-planned | dropped (no GitLab equivalent) |

CLI surface was verified against **glab 1.106.0**: `--output json` on list/view,
`glab api` (method/field/raw-field/input/paginate), `mr update --draft/--ready`,
`mr merge --squash`, `mr diff --raw --color never`, `ci list -F json`, `ci run -b`.

## Environment notes (the machine this was built for/on)

- The primary target is a **self-managed, OAuth-only GitLab instance** whose API in
  `glab` config is pinned to a local mitmproxy bearer-rewrite proxy. `glab` there is
  wrapped: interactive shells use a zsh function, and this plugin is pointed at an
  executable launcher via `opts.glab.cmd` (`~/.config/glab-cli/glab-gated`) because
  `uv.spawn` bypasses shell functions. The wrapper gates the proxy on a security
  agent (Zscaler) being active. None of that lives in this repo — only the `cmd`
  config knob does. Keep `cmd` configurable forever.
- **Concurrency contract**: `api.view()` and the pickers spawn several glab processes
  in parallel. Any wrapper/launcher used as `cmd` must tolerate concurrent
  invocations (the original per-call proxy start/stop caused mid-flight EOF /
  connection-refused; the fix was a shared lingering proxy with lock-serialized
  startup and token refresh — GitLab OAuth refresh tokens are single-use, and
  concurrent refresh-token reuse revokes the whole token family).

## Hard-won gotchas (do not relearn these)

1. **Nerd-font icons and automated editing.** Icon glyphs are PUA codepoints. Some
   tooling silently mangles BMP-PUA glyphs (U+Exxx/U+F0xx) into spaces when strings
   round-trip through it; plane-16 nf-md glyphs (U+F0000+) survive. After any tooling
   edit that touches icon strings, verify bytes (e.g.
   `python3 -c 'print(sorted({ord(c) for c in open("lua/snacks/glab/init.lua").read() if ord(c)>127}))'`).
   The smoke tests assert every action icon and every `config.icons` leaf is
   non-blank — keep those assertions.
2. **Lua gsub capture bug.** URL-encoded repos contain `%2F`; using them as a plain
   gsub *replacement* string throws `invalid capture index`. Endpoint placeholder
   expansion in `api.request` uses a function replacement for `{project}` for this
   reason. Same trap applies to any new placeholder carrying `%`.
3. **Weak cache in tests.** The api item cache is weak; tests must hold fetched items
   in locals across test blocks or GC nondeterministically drops them.
4. **Draft note body field is `note`, not `body`** (REST quirk). Scratch actions
   targeting draft endpoints must use `edit = "note"`.
5. **JSON nulls**: GitLab serializes absent positions as `"position": null` →
   `vim.NIL`, which is truthy userdata that errors on indexing. `item.lua`'s
   `denil()` sanitizes discussions and draft_notes; run new list-shaped responses
   through it too.
6. **Chained pseudo-fields** (`checks` in `api.view`): when one request depends on
   another's response, register the inner proc in `procs` BEFORE calling `done()`
   for the outer one, or the completion accounting finishes early.
7. **format_action alignment.** The actions palette renders a fixed-width icon column
   (`align(icon or "", 3)`); don't revert to conditional icon rendering or rows
   misalign when an action has no icon.
8. **`glab api` has no `--repo` flag** — repo goes into the endpoint path
   (`projects/<url-encoded>` or the `:id` placeholder resolved from cwd). Subcommands
   (`issue`, `mr`, `ci`) take `--repo`.
9. **Buffer marker contract.** `vim.b.snacks_glab = { repo, type, iid (number) }` is
   deep-equal-compared by `update_main`/`get_meta` in actions.lua; keep types exact.
   Per-line metadata (`discussion_id`, `note_id`, diff positions) flows through
   highlight entries (`{ "", meta = {...} }`) into `Snacks.picker.highlight.meta(buf)`.

## Testing

```sh
nvim --headless --clean -c "luafile tests/smoke.lua"
```

- No network: `tests/mock/glab` is a bash script emitting canned GitLab REST JSON,
  selected by arg pattern matching; `SNACKS_DIR` env overrides the snacks.nvim path
  (defaults to `~/.local/share/nvim/lazy/snacks.nvim`).
- Covered: module loading, source registration, timestamp/uri/subgroup parsing,
  list/view flows, end-to-end `glab://` buffer render (title, threaded replies,
  system-note filtering, line meta), action gating per state/status for all four
  kinds, kind isolation (no CI actions on issues and vice versa), diff annotations,
  trace ANSI cleaning, icon non-blank assertions.
- When adding a feature: extend the mock with new endpoint cases (order matters —
  more specific globs before catch-alls like `*"/merge_requests/7"*`), add a `try()`
  block, keep the suite green before committing.

## History (condensed)

1. Started as an in-config prototype under the dotfiles; judged bad and rewritten
   from scratch as this standalone repo, porting upstream snacks.gh 1:1.
2. Wired into dotfiles first via `dir = ~/projects/...`, later switched to sourcing
   from GitHub (`alexander-blackwell/snacks-glab.nvim`, public, Apache-2.0).
3. Icon-loss incident (gotcha #1) fixed by extracting exact codepoints from the
   installed upstream gh sources and patching bytes via python; alignment +
   test assertions added.
4. CI support added: `glab_pipeline` / `glab_job` pickers, status-gated actions
   (retry/cancel/delete/run, job log/retry/play/cancel), MR "View pipelines",
   multi-kind action types; fixed the `%2F` gsub bug it exposed (gotcha #2).
5. Proxy-wrapper concurrency issues diagnosed and fixed on the consumer side
   (shared lingering proxy + locks); recorded here as the concurrency contract.
6. gh.md parity audit closed the remaining gaps: `Snacks.glab.open()`, the
   draft-note review flow (draft/submit/discard + pending section in buffers),
   inline hunks under positioned comments (client-side slicing from `/diffs`),
   per-job pipeline breakdown in MR buffers, resolve/unresolve threads, and
   `Snacks.glab.create_issue()`.
7. glab-capability extras: job artifact downloads (`glab ci artifact <ref> <name>`,
   gated on `artifacts_file`), cancel auto-merge (+ badge in Merge Status prop),
   assignee/reviewer management (`glab_users` picker over `/members/all`,
   `assignee_ids`/`reviewer_ids` PUT with `{0}` to clear, `glab_assign_me` toggle),
   `Snacks.glab.create_mr()` (`mr create -y`, current branch -> default branch),
   and `Snacks.glab.ci_lint()`.
