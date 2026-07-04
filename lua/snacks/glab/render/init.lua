local Markdown = require("snacks.picker.util.markdown")

local M = {}
local H = Snacks.picker.highlight
local U = Snacks.picker.util

---@class snacks.glab.render.ctx
---@field item snacks.picker.glab.Item
---@field opts snacks.glab.Config
---@field markdown? boolean render in a markdown buffer (defaults to true)
---@field diff? boolean render code hunks under positioned comments (defaults to true)
---@field annotations? snacks.diff.Annotation[]

---@param field string
local function time_prop(field)
  return {
    name = U.title(field),
    ---@param item snacks.picker.glab.Item
    hl = function(item)
      if not item[field] then
        return
      end
      return { { U.reltime(item[field]), "SnacksPickerGitDate" } }
    end,
  }
end

--- Map GitLab detailed_merge_status values to icon/hl buckets
---@param status string
local function merge_status(status)
  if status == "mergeable" then
    return "clean"
  elseif status == "conflict" or status == "broken_status" then
    return "dirty"
  elseif status == "unchecked" or status == "checking" or status == "preparing" or status == "approvals_syncing" then
    return "checking"
  end
  return "blocked"
end
M.merge_status = merge_status

---@type {name: string, hl:fun(item:snacks.picker.glab.Item, opts:snacks.glab.Config):snacks.picker.Highlight[]? }[]
M.props = {
  {
    name = "Status",
    hl = function(item, opts)
      local icons = opts.icons[item.type]
      local status = icons[item.status] and item.status or "other"
      local ret = {} ---@type snacks.picker.Highlight[]
      if status then
        local icon = icons[status]
        local hl = "SnacksGlab" .. U.title(item.type) .. U.title(status)
        local text = icon .. U.title(item.status or "other")
        H.extend(ret, H.badge(text, Snacks.util.color(hl), { fg = "#ffffff" }))
      end
      if item.item.target_branch and item.item.source_branch then
        ret[#ret + 1] = { " " }
        vim.list_extend(ret, {
          { item.item.target_branch, "SnacksGlabBranch" },
          { " ← ", "SnacksGlabDelim" },
          { item.item.source_branch, "SnacksGlabBranch" },
        })
      end
      return ret
    end,
  },
  {
    name = "Repo",
    hl = function(item, opts)
      return { { opts.icons.logo, "Special" }, { item.repo, "@markup.link" } }
    end,
  },
  {
    name = "Author",
    hl = function(item, opts)
      if not item.author then
        return
      end
      return H.badge(opts.icons.user .. " " .. item.author, "SnacksGlabUserBadge")
    end,
  },
  time_prop("created"),
  time_prop("updated"),
  time_prop("closed"),
  time_prop("merged"),
  {
    name = "Reactions",
    hl = function(item, opts)
      if item.reactions and #item.reactions > 0 then
        local ret = {} ---@type snacks.picker.Highlight[]
        table.sort(item.reactions, function(a, b)
          return a.count > b.count
        end)
        for _, r in pairs(item.reactions) do
          local icon = opts.icons.reactions[r.content] or (":" .. r.content .. ":")
          local badge = H.badge(icon .. " " .. tostring(r.count), "SnacksGlabReactionBadge")
          vim.list_extend(ret, badge)
          ret[#ret + 1] = { " " }
        end
        return ret
      end
    end,
  },
  {
    name = "Labels",
    hl = function(item)
      local ret = {} ---@type snacks.picker.Highlight[]
      for _, label in ipairs(item.item.labels or {}) do
        local badge = label.color and H.badge(label.name, label.color) or H.badge(label.name, "SnacksGlabLabel")
        H.extend(ret, badge)
        ret[#ret + 1] = { " " }
      end
      return ret
    end,
  },
  {
    name = "Assignees",
    hl = function(item)
      local ret = {} ---@type snacks.picker.Highlight[]
      for _, u in ipairs(item.item.assignees or {}) do
        local badge = H.badge(u.username, "Identifier")
        vim.list_extend(ret, badge)
        ret[#ret + 1] = { " " }
      end
      return ret
    end,
  },
  {
    name = "Milestone",
    hl = function(item)
      if item.item.milestone then
        return H.badge(item.item.milestone.title, "Title")
      end
    end,
  },
  {
    name = "Merge Status",
    hl = function(item, opts)
      local detailed = item.item.detailed_merge_status
      if not detailed or item.state ~= "open" then
        return
      end
      local status = merge_status(detailed)
      local icon = opts.icons.merge_status[status]
      local hl = "SnacksGlabMr" .. U.title(status)
      local ret = { { icon .. " " .. detailed:gsub("_", " "), hl } } ---@type snacks.picker.Highlight[]
      if item.item.merge_when_pipeline_succeeds then
        ret[#ret + 1] = { " " }
        H.extend(ret, H.badge("auto-merge", "SnacksGlabPendingBadge"))
      end
      return ret
    end,
  },
  {
    name = "Pipeline",
    hl = function(item, opts)
      if item.type ~= "mr" then
        return
      end
      local pipeline = item.item.head_pipeline or item.item.pipeline
      if not pipeline or not pipeline.status then
        return
      end
      local status = pipeline.status
      local icon = opts.icons.pipeline[status] or opts.icons.pipeline.pending
      local hl = "SnacksGlabCheck" .. U.title(status):gsub("_(%l)", string.upper)
      local ret = {} ---@type snacks.picker.Highlight[]
      H.extend(ret, H.badge(icon .. " " .. status:gsub("_", " "), hl))

      -- per-job breakdown of the latest MR pipeline (gh-style checks)
      local jobs = item.item.checks_jobs or {}
      if #jobs > 0 then
        local stats = {} ---@type table<string, number>
        for _, job in ipairs(jobs) do
          stats[job.status] = (stats[job.status] or 0) + 1
        end
        local order = { "success", "failed", "running", "pending", "manual", "canceled", "skipped" }
        for _, s in ipairs(order) do
          local count = stats[s]
          if count then
            ret[#ret + 1] = { " " }
            local job_icon = opts.icons.pipeline[s] or opts.icons.pipeline.pending
            local job_hl = "SnacksGlabCheck" .. U.title(s)
            H.extend(ret, H.badge(job_icon .. " " .. tostring(count), job_hl))
          end
        end
        ret[#ret + 1] = { " " }
        for _, s in ipairs(order) do
          local count = stats[s]
          if count then
            ret[#ret + 1] = { string.rep(opts.icons.block, count), "SnacksGlabCheck" .. U.title(s) }
          end
        end
      end
      return ret
    end,
  },
  {
    name = "Approvals",
    hl = function(item, opts)
      if item.type ~= "mr" or #(item.item.approved_by or {}) == 0 then
        return
      end
      local ret = {} ---@type snacks.picker.Highlight[]
      H.extend(ret, H.badge(opts.icons.checkmark .. "approved", "SnacksGlabApprovedBadge"))
      ret[#ret + 1] = { " " }
      for _, u in ipairs(item.item.approved_by) do
        local badge = H.badge(opts.icons.user .. " " .. u.username, "SnacksGlabUserBadge")
        vim.list_extend(ret, badge)
        ret[#ret + 1] = { " " }
      end
      return ret
    end,
  },
  {
    name = "Changes",
    hl = function(item, opts)
      if item.type ~= "mr" or not item.item.changes_count then
        return
      end
      local ret = H.badge(opts.icons.file .. tostring(item.item.changes_count), "SnacksGlabStatBadge")
      if item.item.has_conflicts then
        ret[#ret + 1] = { " " }
        ret[#ret + 1] = { opts.icons.crossmark .. "conflicts", "SnacksGlabDeletions" }
      end
      return ret
    end,
  },
}

local ns = vim.api.nvim_create_namespace("snacks.glab.render")

---@param buf number
---@param item snacks.picker.glab.Item
---@param opts snacks.glab.Config|{partial?:boolean}
function M.render(buf, item, opts)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  ---@type snacks.glab.render.ctx
  local ctx = {
    item = item,
    opts = opts,
  }

  local lines = {} ---@type snacks.picker.Highlight[][]

  item.msg = item.title
  ---@diagnostic disable-next-line: missing-fields
  lines[#lines + 1] = Snacks.picker.format.commit_message(item, {})
  vim.list_extend(lines[#lines], { { " " }, { item.hash, "SnacksPickerDimmed" } })
  lines[#lines + 1] = {} -- empty line

  for _, prop in ipairs(M.props) do
    local value = prop.hl(item, opts)
    if value and #value > 0 then
      local line = {} ---@type snacks.picker.Highlight[]
      line[#line + 1] = { prop.name, "SnacksGlabLabel" }
      line[#line + 1] = { ":", "SnacksGlabDelim" }
      line[#line + 1] = { " " }
      H.extend(line, value)
      lines[#lines + 1] = line
    end
  end

  lines[#lines + 1] = {} -- empty line
  lines[#lines + 1] = { { "---", "@punctuation.special.markdown" } }
  lines[#lines + 1] = {} -- empty line

  do
    local text = item.body or ""
    text = text:gsub("<%!%-%-.-%-%->%s*", "") -- remove html comments
    local body = vim.split(text or "", "\n")
    while #body > 0 and body[1]:match("^%s*$") do
      table.remove(body, 1)
    end
    for _, l in ipairs(body) do
      lines[#lines + 1] = { { l } }
    end
  end

  local threads = M.get_threads(item)
  if #threads > 0 then
    lines[#lines + 1] = { { "" } } -- empty line
    lines[#lines + 1] = { { "---", "@punctuation.special.markdown" } }
    lines[#lines + 1] = {} -- empty line

    for _, thread in ipairs(threads) do
      local c = #lines
      vim.list_extend(lines, M.thread(thread, ctx))
      if #lines > c then
        lines[#lines + 1] = {} -- empty line
      end
    end
  end

  -- the current user's pending review comments (draft notes)
  local drafts = item.item.draft_notes or {}
  if #drafts > 0 then
    lines[#lines + 1] = { { "" } } -- empty line
    lines[#lines + 1] = { { "---", "@punctuation.special.markdown" } }
    lines[#lines + 1] = {} -- empty line
    local header = {} ---@type snacks.picker.Highlight[]
    H.extend(header, H.badge(("Pending review · %d draft%s"):format(#drafts, #drafts == 1 and "" or "s"), "SnacksGlabPendingBadge"))
    header[#header + 1] = { " " }
    header[#header + 1] = { "not visible to others until submitted", "SnacksPickerDimmed" }
    lines[#lines + 1] = header
    lines[#lines + 1] = {} -- empty line
    for _, draft in ipairs(drafts) do
      vim.list_extend(lines, M.draft(draft, ctx))
      lines[#lines + 1] = {} -- empty line
    end
  end

  local changed = H.render(buf, ns, lines)

  if changed then
    Markdown.render(buf, { bullets = false })
  end

  vim.schedule(function()
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      vim.api.nvim_win_call(win, function()
        if vim.wo.foldmethod == "expr" then
          vim.wo.foldmethod = "expr"
        end
      end)
    end
  end)
end

--- Discussions sorted by creation time of their first note
---@param item snacks.picker.glab.Item
function M.get_threads(item)
  local ret = {} ---@type snacks.glab.Discussion[]
  vim.list_extend(ret, item.item.discussions or {})
  table.sort(ret, function(a, b)
    return (a.notes[1].created or 0) < (b.notes[1].created or 0)
  end)
  return ret
end

---@param note snacks.glab.Note
---@param opts? {text?:string}
---@param ctx snacks.glab.render.ctx
function M.comment_header(note, opts, ctx)
  opts = opts or {}
  local ret = {} ---@type snacks.picker.Highlight[]
  local login = note.author and note.author.username or "?"
  local is_bot = login:find("[-_]bot$") ~= nil or login == "ghost"
  H.extend(
    ret,
    H.badge(
      ("%s %s"):format(is_bot and ctx.opts.icons.logo or ctx.opts.icons.user, login),
      is_bot and "SnacksGlabBotBadge" or "SnacksGlabUserBadge"
    )
  )

  if opts.text then
    ret[#ret + 1] = { opts.text, "SnacksGlabCommentAction" }
    ret[#ret + 1] = { " " }
  end
  ret[#ret + 1] = { U.reltime(note.created), "SnacksPickerGitDate" }
  if login == (ctx.item.author or nil) then
    ret[#ret + 1] = { " " }
    H.extend(ret, H.badge("Author", "SnacksGlabAuthorBadge"))
  end
  if note.resolved then
    ret[#ret + 1] = { " " }
    H.extend(ret, H.badge(ctx.opts.icons.checkmark .. "resolved", "SnacksGlabResolvedBadge"))
  end
  if note.position and (note.position.new_path or note.position.old_path) then
    local file = note.position.new_path or note.position.old_path
    local line = note.position.new_line or note.position.old_line
    ret[#ret + 1] = { " " }
    H.extend(ret, H.badge(ctx.opts.icons.file .. file .. (line and (":" .. line) or ""), "SnacksGlabPositionBadge"))
  end
  return ret
end

---@param note snacks.glab.Note
---@param ctx snacks.glab.render.ctx
function M.comment_body(note, ctx)
  local body = note.body or ""
  if body:match("^%s*$") then
    return {}
  end
  local ret = {} ---@type snacks.picker.Highlight[][]
  local md = {} ---@type string[]
  for _, line in ipairs(vim.split(body, "\n", { plain = true })) do
    local suggestion = line:match("^```suggestion:?[%-+%d]*%s*$")
    if suggestion then
      local ft = note.position
          and note.position.new_path
          and vim.filetype.match({ filename = note.position.new_path })
        or ""
      line = "```" .. ft
      ret[#ret + 1] = H.badge("Suggested change", "SnacksGlabStatBadge")
      md[#md + 1] = ""
    end
    md[#md + 1] = line
    ret[#ret + 1] = { { line } }
  end

  if ctx.markdown == false then
    -- if the filetype of the buffer is not markdown,
    -- we need to add proper highlights for the markdown content
    local extmarks = H.get_highlights({ code = table.concat(md, "\n"), ft = "markdown" })
    for l, line in pairs(extmarks) do
      vim.list_extend(ret[l] or {}, line)
    end
  end
  return ret
end

---@param lines snacks.picker.Highlight[][]
---@param ctx snacks.glab.render.ctx
function M.indent(lines, ctx)
  local indent = {} ---@type snacks.picker.Highlight[]
  indent[#indent + 1] = { "   ", "Normal" }
  indent[#indent + 1] = {
    col = 0,
    virt_text = {
      { " ", "Normal" },
      { "┃", { "Normal", "@punctuation.definition.blockquote.markdown" } },
      { " ", "Normal" },
    },
    virt_text_pos = "overlay",
    hl_mode = "combine",
    virt_text_repeat_linebreak = true,
  }

  --- first indent. In a markdown buffer, we need proper structure,
  --- so we conceal the list marker
  ---@type snacks.picker.Highlight[]
  local first = ctx.markdown == false and {}
    or {
      {
        col = 0,
        end_col = 3,
        conceal = "",
        priority = 1000,
      },
      { " * ", "Normal" },
    }

  local ret = {} ---@type snacks.picker.Highlight[][]
  for l, line in ipairs(lines) do
    local new = vim.deepcopy(l == 1 and first or indent)
    H.extend(new, line)
    ret[l] = new
  end
  return ret
end

--- Register a diff annotation for a positioned note
---@param note snacks.glab.Note
---@param ctx snacks.glab.render.ctx
function M.annotate(note, ctx)
  local pos = note.position
  if not pos or not (pos.new_path or pos.old_path) then
    return
  end
  local side = pos.new_line and "right" or "left"
  ---@type snacks.diff.Annotation
  local ret = {
    side = side,
    file = pos.new_path or pos.old_path,
    line = pos.new_line or pos.old_line or 1,
    text = {},
  }
  ctx.annotations = ctx.annotations or {}
  table.insert(ctx.annotations, ret)
  return ret
end

---@param note snacks.glab.Note
---@param ctx snacks.glab.render.ctx
---@param replies? snacks.glab.Note[]
function M.comment(note, ctx, replies)
  local ret = {} ---@type snacks.picker.Highlight[][]

  local header = {} ---@type snacks.picker.Highlight[]
  H.extend(header, M.comment_header(note, {}, ctx))
  ret[#ret + 1] = header

  local annotation = M.annotate(note, ctx)
  if ctx.diff ~= false then
    -- render the code hunk this comment is anchored to
    local diff = M.comment_diff(note, ctx)
    if #diff > 0 then
      vim.list_extend(ret, diff)
      ret[#ret + 1] = {} -- empty line between diff and body
    end
  end

  vim.list_extend(ret, M.comment_body(note, ctx))
  for _, reply in ipairs(replies or {}) do
    ret[#ret + 1] = {} -- empty line between comment and reply
    vim.list_extend(ret, M.comment(reply, ctx))
  end

  -- attach reply metadata to every line of the thread
  for _, line in ipairs(ret) do
    line[#line + 1] = { "", meta = { discussion_id = note.discussion_id, note_id = note.id } }
  end

  ret = M.indent(ret, ctx)
  if annotation then
    annotation.text = vim.deepcopy(ret)
  end
  return ret
end

--- Render a pending draft note (body field is `note`)
---@param draft snacks.glab.DraftNote
---@param ctx snacks.glab.render.ctx
function M.draft(draft, ctx)
  local ret = {} ---@type snacks.picker.Highlight[][]
  local header = {} ---@type snacks.picker.Highlight[]
  H.extend(header, H.badge("PENDING", "SnacksGlabPendingBadge"))
  local pos = draft.position
  if pos and (pos.new_path or pos.old_path) then
    local file = pos.new_path or pos.old_path
    local line = pos.new_line or pos.old_line
    header[#header + 1] = { " " }
    H.extend(header, H.badge(ctx.opts.icons.file .. file .. (line and (":" .. line) or ""), "SnacksGlabPositionBadge"))
  end
  if draft.discussion_id then
    header[#header + 1] = { " " }
    header[#header + 1] = { "reply", "SnacksGlabCommentAction" }
  end
  ret[#ret + 1] = header

  local annotation = M.annotate(draft, ctx)
  if ctx.diff ~= false then
    local diff = M.comment_diff(draft, ctx)
    if #diff > 0 then
      vim.list_extend(ret, diff)
      ret[#ret + 1] = {}
    end
  end

  vim.list_extend(ret, M.comment_body({ body = draft.note }, ctx))
  for _, line in ipairs(ret) do
    line[#line + 1] = { "", meta = { draft_id = draft.id } }
  end
  ret = M.indent(ret, ctx)
  if annotation then
    annotation.text = vim.deepcopy(ret)
  end
  return ret
end

--- Slice the diff hunk a positioned note refers to, gh-style:
--- the hunk from its start through the commented line, trimmed to
--- `opts.diff.min` lines and rendered as a fenced diff.
---@param note snacks.glab.Note|snacks.glab.DraftNote
---@param ctx snacks.glab.render.ctx
function M.comment_diff(note, ctx)
  local pos = note.position
  if not pos or pos.position_type ~= "text" or not (pos.new_path or pos.old_path) then
    return {}
  end
  local target_new, target_old = pos.new_line, pos.old_line
  local fd ---@type snacks.glab.FileDiff?
  for _, d in ipairs(ctx.item.item and ctx.item.item.diffs or {}) do
    if (pos.new_path and d.new_path == pos.new_path) or (pos.old_path and d.old_path == pos.old_path) then
      fd = d
      break
    end
  end
  if not fd or not fd.diff or fd.diff == "" then
    return {}
  end

  -- walk the unified diff, collecting the current hunk until the target line
  local hunk_header ---@type string?
  local collected = {} ---@type string[]
  local old_ln, new_ln = 0, 0
  local found = false
  for _, line in ipairs(vim.split(fd.diff, "\n", { plain = true })) do
    local oh, nh = line:match("^@@ %-(%d+),?%d* %+(%d+),?%d* @@")
    if oh then
      hunk_header, collected = line, {}
      old_ln, new_ln = tonumber(oh) - 1, tonumber(nh) - 1
    elseif hunk_header then
      local kind = line:sub(1, 1)
      if kind == "+" then
        new_ln = new_ln + 1
      elseif kind == "-" then
        old_ln = old_ln + 1
      elseif kind == " " or line == "" then
        old_ln, new_ln = old_ln + 1, new_ln + 1
      end
      collected[#collected + 1] = line
      if (target_new and kind ~= "-" and new_ln == target_new) or (target_old and kind == "-" and old_ln == target_old) then
        found = true
        break
      end
    end
  end
  if not found or not hunk_header then
    return {}
  end

  local count = math.max(ctx.opts.diff and ctx.opts.diff.min or 4, 1)
  local Diff = require("snacks.picker.util.diff")
  local path = pos.new_path or pos.old_path
  local diff = ("diff --git a/%s b/%s\n%s\n%s"):format(path, path, hunk_header, table.concat(collected, "\n"))
  local ret = Diff.format(diff, {
    max_hunk_lines = count,
    hunk_header = false,
  })
  table.insert(ret, 1, { { "```" } })
  table.insert(ret, { { "```" } })
  return ret
end

--- Render a discussion: first note is the comment, the rest are replies
---@param thread snacks.glab.Discussion
---@param ctx snacks.glab.render.ctx
function M.thread(thread, ctx)
  local notes = thread.notes or {}
  if #notes == 0 then
    return {}
  end
  local replies = {} ---@type snacks.glab.Note[]
  for i = 2, #notes do
    replies[#replies + 1] = notes[i]
  end
  return M.comment(notes[1], ctx, replies)
end

--- Annotations for the MR diff view (inline discussion threads)
---@param mr snacks.picker.glab.Item?
function M.annotations(mr)
  if not mr then
    return {}
  end
  ---@type snacks.glab.render.ctx
  local ctx = {
    item = mr,
    opts = require("snacks.glab").config(),
    markdown = false,
    diff = false, -- annotations are shown on the diff itself; no embedded hunks
  }
  for _, thread in ipairs(mr.item and mr.item.discussions or {}) do
    M.thread(thread, ctx)
  end
  for _, draft in ipairs(mr.item and mr.item.draft_notes or {}) do
    M.draft(draft, ctx)
  end
  return ctx.annotations or {}
end

return M
