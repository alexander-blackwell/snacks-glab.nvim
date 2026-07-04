---@class snacks.glab
---@field api snacks.glab.api
---@field item snacks.picker.glab.Item
local M = setmetatable({}, {
  ---@param M snacks.glab
  __index = function(M, k)
    if vim.tbl_contains({ "api" }, k) then
      M[k] = require("snacks.glab." .. k)
    end
    return rawget(M, k)
  end,
})

M.meta = {
  desc = "GitLab CLI integration",
  needs_setup = false,
}

---@alias snacks.glab.Keymap.fn fun(item:snacks.picker.glab.Item, buf:snacks.glab.Buf)
---@class snacks.glab.Keymap: vim.keymap.set.Opts
---@field [1] string lhs
---@field [2] string|snacks.glab.Keymap.fn rhs
---@field mode? string|string[] defaults to `n`

---@class snacks.glab.Config
local defaults = {
  --- the GitLab CLI binary (or a wrapper script)
  cmd = "glab",
  --- Keymaps for GitLab buffers
  ---@type table<string, snacks.glab.Keymap|false>?
  -- stylua: ignore
  keys = {
    select  = { "<cr>", "glab_actions", desc = "Select Action" },
    edit    = { "i"   , "glab_edit"   , desc = "Edit" },
    comment = { "a"   , "glab_comment", desc = "Add Comment" },
    close   = { "c"   , "glab_close"  , desc = "Close" },
    reopen  = { "o"   , "glab_reopen" , desc = "Reopen" },
  },
  ---@type vim.wo|{}
  wo = {
    breakindent = true,
    wrap = true,
    showbreak = "",
    linebreak = true,
    number = false,
    relativenumber = false,
    foldexpr = "v:lua.vim.treesitter.foldexpr()",
    foldmethod = "expr",
    concealcursor = "n",
    conceallevel = 2,
    list = false,
    winhighlight = Snacks.util.winhl({
      Normal = "SnacksGlabNormal",
      NormalFloat = "SnacksGlabNormalFloat",
      FloatBorder = "SnacksGlabBorder",
      FloatTitle = "SnacksGlabTitle",
      FloatFooter = "SnacksGlabFooter",
    }),
  },
  ---@type vim.bo|{}
  bo = {},
  scratch = {
    height = 15, -- height of scratch window
  },
  -- stylua: ignore
  icons = {
    logo = "󰮠 ",
    user = " ",
    checkmark = " ",
    crossmark = " ",
    block = "■",
    file = " ",
    pipeline = {
      created  = " ",
      waiting_for_resource = " ",
      preparing = " ",
      pending  = " ",
      running  = " ",
      success  = " ",
      failed   = " ",
      canceled = " ",
      skipped  = " ",
      manual   = " ",
      scheduled = " ",
    },
    issue = {
      open   = " ",
      closed = " ",
      other  = " ",
    },
    mr = {
      open   = " ",
      closed = " ",
      merged = " ",
      draft  = " ",
      other  = " ",
    },
    merge_status = {
      clean    = " ",
      dirty    = " ",
      checking = " ",
      blocked  = " ",
    },
    reactions = {
      thumbsup   = "👍",
      thumbsdown = "👎",
      laughing   = "😄",
      smile      = "😄",
      tada       = "🎉",
      confused   = "😕",
      heart      = "❤️",
      rocket     = "🚀",
      eyes       = "👀",
    },
  },
}

Snacks.util.set_hl({
  Normal = "NormalFloat",
  NormalFloat = "NormalFloat",
  Border = "FloatBorder",
  Title = "FloatTitle",
  ScratchTitle = "Number",
  ScratchBorder = "Number",
  Footer = "FloatFooter",
  Number = "Number",
  Green = { fg = "#108548" },
  Orange = { fg = "#fc6d26" },
  Blue = { fg = "#1f75cb" },
  Purple = { fg = "#6f42c1" },
  Gray = { fg = "#6a737d" },
  Red = { fg = "#dd2b0e" },
  Branch = "@markup.link",
  IssueOpen = "SnacksGlabGreen",
  IssueClosed = "SnacksGlabBlue",
  IssueOther = "SnacksGlabGray",
  MrOpen = "SnacksGlabGreen",
  MrClosed = "SnacksGlabRed",
  MrMerged = "SnacksGlabPurple",
  MrDraft = "SnacksGlabGray",
  Label = "@property",
  Delim = "@punctuation.delimiter",
  UserBadge = "DiagnosticInfo",
  AuthorBadge = "DiagnosticWarn",
  OwnerBadge = "DiagnosticError",
  BotBadge = { fg = Snacks.util.color({ "NonText", "SignColumn", "FoldColumn" }) },
  ReactionBadge = "Special",
  AssocBadge = {},
  StatBadge = "Special",
  ResolvedBadge = "DiagnosticOk",
  PositionBadge = "@property",
  MrClean = "DiagnosticInfo",
  MrChecking = "DiagnosticWarn",
  MrDirty = "DiagnosticError",
  MrBlocked = "DiagnosticError",
  Additions = "SnacksGlabGreen",
  Deletions = "SnacksGlabRed",
  CheckPending = "DiagnosticWarn",
  CheckCreated = "DiagnosticWarn",
  CheckWaitingForResource = "DiagnosticWarn",
  CheckPreparing = "DiagnosticWarn",
  CheckScheduled = "DiagnosticWarn",
  CheckRunning = "DiagnosticWarn",
  CheckSuccess = "SnacksGlabGreen",
  CheckFailed = "SnacksGlabRed",
  CheckSkipped = "SnacksGlabStat",
  CheckManual = "DiagnosticInfo",
  CheckCanceled = "SnacksGlabGray",
  ApprovedBadge = "SnacksGlabGreen",
  CommentAction = "@property",
  Stat = { fg = Snacks.util.color("SignColumn") },
}, { default = true, prefix = "SnacksGlab" })

M._config = nil ---@type snacks.glab.Config?
local did_setup = false

---@param opts? snacks.picker.glab.issue.Config
function M.issue(opts)
  return Snacks.picker.glab_issue(opts)
end

---@param opts? snacks.picker.glab.mr.Config
function M.mr(opts)
  return Snacks.picker.glab_mr(opts)
end

---@param opts? snacks.picker.glab.pipeline.Config
function M.pipeline(opts)
  return Snacks.picker.glab_pipeline(opts)
end

--- Open an issue or MR in a glab:// buffer.
--- `repo` defaults to the origin remote of the cwd (subgroups supported).
---@param opts {type: "issue"|"mr", iid: number, repo?: string}
function M.open(opts)
  opts = opts or {}
  if not (opts.type and opts.iid) then
    Snacks.notify.error("Snacks.glab.open: `type` and `iid` are required")
    return
  end
  local repo = opts.repo
  if not repo then
    local url = vim.trim(vim.fn.system({ "git", "remote", "get-url", "origin" }))
    if vim.v.shell_error ~= 0 or url == "" then
      Snacks.notify.error("Snacks.glab.open: not in a git repo; pass `repo` explicitly")
      return
    end
    -- https://host/group/sub/proj.git or git@host:group/sub/proj.git -> group/sub/proj
    repo = url:gsub("%.git$", ""):gsub("^%w+://[^/]+/", ""):gsub("^[^@/]+@[^:]+:", "")
  end
  vim.cmd.edit(require("snacks.glab.item").to_uri({ repo = repo, type = opts.type, iid = opts.iid }))
end

---@private
function M.config()
  M._config = M._config or Snacks.config.get("glab", defaults)
  return M._config
end

---@private
---@param ev? vim.api.keyset.create_autocmd.callback_args
function M.setup(ev)
  if did_setup then
    return
  end
  did_setup = true

  require("snacks.glab.buf").setup()
  if ev then
    vim.schedule(function()
      require("snacks.glab.buf").attach(ev.buf)
    end)
  end
end

return M
