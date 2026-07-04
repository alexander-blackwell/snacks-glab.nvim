-- snacks-glab.nvim: GitLab CLI integration for snacks.nvim
-- Registers the glab picker sources and the glab:// buffer handler.
if vim.g.loaded_snacks_glab then
  return
end
vim.g.loaded_snacks_glab = true

local function register()
  local ok, sources = pcall(require, "snacks.picker.config.sources")
  if not ok then
    vim.notify("snacks-glab.nvim requires folke/snacks.nvim", vim.log.levels.ERROR)
    return
  end

  local win = {
    input = {
      keys = {
        ["<a-b>"] = { "glab_browse", mode = { "n", "i" } },
        ["<c-y>"] = { "glab_yank", mode = { "n", "i" } },
      },
    },
    list = {
      keys = {
        ["y"] = { "glab_yank", mode = { "n", "x" } },
      },
    },
  }

  ---@class snacks.picker.glab.Config: snacks.picker.Config
  ---@field repo? string GitLab project (group/project, subgroups supported). Defaults to the current repo
  ---@field limit? number maximum number of items to fetch (default: 50)
  ---@field author? string filter by author username
  ---@field assignee? string filter by assignee username
  ---@field label? string filter by label(s), comma-separated
  ---@field milestone? string filter by milestone
  ---@field search? string filter by search string
  ---@field group? string list at the group level

  ---@class snacks.picker.glab.issue.Config: snacks.picker.glab.Config
  ---@field state? "open" | "closed" | "all"
  sources.glab_issue = {
    title = "󰮠  Issues",
    finder = "glab_issue",
    format = "glab_format",
    preview = "glab_preview",
    sort = { fields = { "score:desc", "idx" } },
    supports_live = true,
    live = true,
    confirm = "glab_actions",
    win = win,
  }

  ---@class snacks.picker.glab.mr.Config: snacks.picker.glab.Config
  ---@field state? "open" | "closed" | "merged" | "all"
  ---@field draft? boolean filter draft MRs
  ---@field reviewer? string filter by reviewer
  sources.glab_mr = {
    title = "󰮠  Merge Requests",
    finder = "glab_mr",
    format = "glab_format",
    preview = "glab_preview",
    sort = { fields = { "score:desc", "idx" } },
    supports_live = true,
    live = true,
    confirm = "glab_actions",
    win = win,
  }

  ---@class snacks.picker.glab.diff.Config: snacks.picker.Config
  ---@field group? boolean group changes by file (when false, show individual hunks)
  ---@field mr number MR iid to diff
  ---@field repo? string GitLab project. Defaults to the current repo
  sources.glab_diff = {
    title = "󰮠  MR Diff",
    group = true,
    finder = "glab_diff",
    format = "git_status",
    preview = "glab_preview_diff",
    win = {
      preview = {
        keys = {
          ["a"] = { "glab_comment", mode = { "n", "x" } },
          ["<cr>"] = { "glab_actions", mode = { "n", "x" } },
        },
      },
    },
  }

  ---@class snacks.picker.glab.reactions.Config: snacks.picker.Config
  ---@field iid number issue or MR iid
  ---@field repo string GitLab project
  ---@field type "issue" | "mr"
  sources.glab_reactions = {
    layout = { preset = "select", layout = { max_width = 50 } },
    title = "󰮠  Reactions",
    main = { current = true },
    group = true,
    finder = "glab_reactions",
    format = "glab_format_reaction",
  }

  ---@class snacks.picker.glab.labels.Config: snacks.picker.Config
  ---@field iid number issue or MR iid
  ---@field repo string GitLab project
  ---@field type "issue" | "mr"
  sources.glab_labels = {
    layout = { preset = "select", layout = { max_width = 50 } },
    title = "󰮠  Labels",
    main = { current = true },
    group = true,
    finder = "glab_labels",
    format = "glab_format_label",
  }

  ---@class snacks.picker.glab.actions.Config: snacks.picker.Config
  ---@field iid? number issue or MR iid
  ---@field repo? string GitLab project
  ---@field type? "issue" | "mr"
  ---@field item? snacks.picker.glab.Item
  sources.glab_actions = {
    layout = { preset = "select", layout = { max_width = 50 } },
    title = "󰮠  Actions",
    main = { current = true },
    finder = "glab_get_actions",
    format = "glab_format_action",
    confirm = "glab_perform_action",
  }

  ---@class snacks.picker.glab.pipeline.Config: snacks.picker.Config
  ---@field repo? string GitLab project. Defaults to the current repo
  ---@field mr? number list pipelines of this MR iid instead of the project
  ---@field limit? number maximum number of pipelines to fetch (default: 30)
  ---@field status? string filter by status (running, pending, success, failed, ...)
  ---@field ref? string filter by ref
  ---@field source? string filter by trigger source (push, merge_request_event, ...)
  ---@field username? string filter by the user that triggered the pipeline
  sources.glab_pipeline = {
    layout = { preset = "select", layout = { max_width = 110, min_width = 90 } },
    title = "󰮠  Pipelines",
    finder = "glab_pipeline",
    format = "glab_format_pipeline",
    confirm = "glab_actions",
    win = {
      input = {
        keys = {
          ["<a-b>"] = { "glab_browse", mode = { "n", "i" } },
          ["<c-y>"] = { "glab_yank", mode = { "n", "i" } },
        },
      },
      list = {
        keys = {
          ["y"] = { "glab_yank", mode = { "n", "x" } },
        },
      },
    },
  }

  ---@class snacks.picker.glab.job.Config: snacks.picker.Config
  ---@field repo? string GitLab project. Defaults to the current repo
  ---@field pipeline number pipeline id to list jobs for
  sources.glab_job = {
    layout = { preset = "select", layout = { max_width = 100, min_width = 80 } },
    title = "󰮠  Jobs",
    finder = "glab_job",
    format = "glab_format_job",
    confirm = "glab_actions",
    win = {
      input = {
        keys = {
          ["<a-b>"] = { "glab_browse", mode = { "n", "i" } },
          ["<c-y>"] = { "glab_yank", mode = { "n", "i" } },
        },
      },
      list = {
        keys = {
          ["y"] = { "glab_yank", mode = { "n", "x" } },
        },
      },
    },
  }
end

register()

-- lazily set up glab:// buffers
vim.api.nvim_create_autocmd("BufReadCmd", {
  once = true,
  pattern = "glab://*",
  group = vim.api.nvim_create_augroup("snacks_glab_bootstrap", { clear = true }),
  callback = function(e)
    require("snacks.glab").setup(e)
  end,
})
