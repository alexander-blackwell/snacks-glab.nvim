# 🦊 snacks-glab.nvim

A GitLab CLI integration for [snacks.nvim](https://github.com/folke/snacks.nvim) that brings GitLab
issues and merge requests directly into your editor.

A GitLab port of the built-in [snacks gh plugin](https://github.com/folke/snacks.nvim/blob/main/docs/gh.md),
built on the [GitLab CLI (`glab`)](https://gitlab.com/gitlab-org/cli).

## ✨ Features

- 📋 Browse and search **GitLab issues** and **merge requests** with fuzzy finding
- 🔍 View full issue/MR details including **discussions**, **award emoji**, **approvals**, and **pipeline status**
- 📝 Perform GitLab actions directly from Neovim:
  - Comment on issues and MRs, reply to discussions
  - Close, reopen, edit, and merge MRs (merge, squash, rebase)
  - Add award emoji and labels
  - Approve / revoke approval of MRs
  - Checkout MR branches locally
  - Mark MRs as draft/ready
  - View MR diffs with syntax highlighting and inline discussion threads
  - Retry, cancel, and delete **pipelines**; run new ones
  - Retry, cancel, and trigger manual **jobs**; view job logs
- ⌨️ Customizable **keymaps** for common GitLab operations
- 🎨 **Syntax highlighting** using Treesitter
- 🔗 Open issues/MRs in your web browser
- 📎 Yank URLs to clipboard
- 🌲 Built on top of the [Snacks picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md)
- 🏢 Works with gitlab.com and self-managed instances, including nested subgroups

## ⚡️ Requirements

- [GitLab CLI (`glab`)](https://gitlab.com/gitlab-org/cli) — installed and authenticated (`glab auth login`)
- [snacks.nvim](https://github.com/folke/snacks.nvim) with the [picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md) enabled

## 📦 Setup

```lua
-- lazy.nvim
{
  "alexanderblackwell/snacks-glab.nvim",
  -- or for a local checkout:
  -- dir = "~/projects/snacks-glab.nvim",
  dependencies = { "folke/snacks.nvim" },
  event = "VeryLazy",
  keys = {
    { "<leader>gi", function() Snacks.picker.glab_issue() end, desc = "GitLab Issues (open)" },
    { "<leader>gI", function() Snacks.picker.glab_issue({ state = "all" }) end, desc = "GitLab Issues (all)" },
    { "<leader>gp", function() Snacks.picker.glab_mr() end, desc = "GitLab MRs (open)" },
    { "<leader>gP", function() Snacks.picker.glab_mr({ state = "all" }) end, desc = "GitLab MRs (all)" },
    { "<leader>gC", function() Snacks.picker.glab_pipeline() end, desc = "GitLab Pipelines (CI)" },
  },
}
```

Configuration lives under the `glab` key of your **snacks.nvim** opts,
exactly like the built-in gh plugin:

```lua
{
  "folke/snacks.nvim",
  opts = {
    glab = {
      -- your glab configuration comes here (see the config section below)
    },
    picker = {
      sources = {
        glab_issue = {}, -- glab_issue picker overrides
        glab_mr = {},    -- glab_mr picker overrides
      },
    },
  },
}
```

## 📚 Usage

```lua
-- Browse open issues
Snacks.picker.glab_issue()

-- Browse all issues (including closed)
Snacks.picker.glab_issue({ state = "all" })

-- Browse open merge requests
Snacks.picker.glab_mr()

-- Browse merged MRs of another project
Snacks.picker.glab_mr({ state = "merged", repo = "group/subgroup/project" })

-- View MR diff with inline discussions
Snacks.picker.glab_diff({ mr = 123 })

-- Browse CI/CD pipelines (and drill into their jobs)
Snacks.picker.glab_pipeline()

-- Pipelines of a specific MR, or filtered
Snacks.picker.glab_pipeline({ mr = 123 })
Snacks.picker.glab_pipeline({ status = "failed", ref = "main" })

-- Jobs of a pipeline
Snacks.picker.glab_job({ pipeline = 4567 })

-- Open issue/MR in a buffer
vim.cmd.edit("glab://group/subgroup/project/issue/42")
```

### Available Actions

When viewing an issue or MR in the picker, press `<cr>` to show available actions:

- **Open in buffer** — view full details with discussions
- **Open in browser** — open in the GitLab web UI
- **Add comment** — comment, or reply when the cursor is on a discussion
- **Add reaction** — award emoji
- **Add/Remove labels** — manage labels
- **Close/Reopen** — change issue/MR state
- **Edit** — edit title and description
- **Yank URL** — copy URL to clipboard

**Merge Request specific:**

- **View diff** — changed files with syntax highlighting and inline discussion threads
- **Checkout** — checkout the MR branch locally
- **Merge / Squash** — merge (auto-merge when a pipeline is running) or squash-merge
- **Rebase** — rebase the source branch onto the target branch
- **Approve / Revoke** — approve the MR or revoke your approval
- **Mark as draft/ready** — toggle draft status
- **Diff comments** — comment on specific lines, with GitLab
  [suggestions](https://docs.gitlab.com/ee/user/project/merge_requests/reviews/suggestions.html)
  pre-filled from visual selections

**Pipelines & Jobs:**

Browse pipelines with `Snacks.picker.glab_pipeline()` (or the **View pipelines** action
on any MR), press `<cr>` for actions:

- **View jobs** — drill into the pipeline's jobs
- **Retry / Cancel / Delete** — gated on the pipeline status
- **Run new pipeline** — start a fresh pipeline on the same ref
- **Open in browser / Yank URL**

Jobs get their own actions: **View log** (rendered in a split, ANSI-clean),
**Retry**, **Cancel**, and **Run manual job** for `when: manual` jobs.

### GitLab Buffers

Opening an issue or MR renders a `glab://` buffer with metadata (status, author, labels,
award emoji, pipeline, approvals), the description, and all discussions as foldable
threaded comments.

**Default Keymaps in GitLab Buffers:**

| Key    | Action        | Description                    |
| ------ | ------------- | ------------------------------ |
| `<cr>` | Select Action | Show available actions menu    |
| `i`    | Edit          | Edit issue/MR title and body   |
| `a`    | Add Comment   | Add a comment (or reply)       |
| `c`    | Close         | Close the issue/MR             |
| `o`    | Reopen        | Reopen a closed issue/MR       |

## ⚙️ Config

```lua
---@class snacks.glab.Config
{
  --- the GitLab CLI binary (or a wrapper script)
  cmd = "glab",
  --- Keymaps for GitLab buffers
  ---@type table<string, snacks.glab.Keymap|false>?
  keys = {
    select  = { "<cr>", "glab_actions", desc = "Select Action" },
    edit    = { "i"   , "glab_edit"   , desc = "Edit" },
    comment = { "a"   , "glab_comment", desc = "Add Comment" },
    close   = { "c"   , "glab_close"  , desc = "Close" },
    reopen  = { "o"   , "glab_reopen" , desc = "Reopen" },
  },
  ---@type vim.wo|{}
  wo = {}, -- window options for glab:// buffers
  ---@type vim.bo|{}
  bo = {}, -- buffer options for glab:// buffers
  scratch = {
    height = 15, -- height of the comment/edit scratch window
  },
  icons = {}, -- see lua/snacks/glab/init.lua for the full icon table
}
```

## 🩺 Self-managed GitLab

`glab` resolves the GitLab host from the current repository's remote, so everything works
on self-managed instances out of the box. If your instance needs a wrapper script around
`glab` (custom auth, proxies, ...), point the plugin at it:

```lua
opts = {
  glab = { cmd = vim.fn.expand("~/bin/glab-wrapper") },
}
```

## 🧪 Tests

```sh
nvim --headless --clean -c "luafile tests/smoke.lua"
```

Runs a full smoke test against a mock `glab` binary (no network needed).

## 🙏 Attribution

Ported from the gh plugin in [folke/snacks.nvim](https://github.com/folke/snacks.nvim)
(Apache-2.0). This plugin follows the same architecture and re-uses snacks.nvim internals.
