local Api = require("snacks.glab.api")
local config = require("snacks.glab").config()

local M = {}

---@class snacks.glab.action.ctx
---@field items snacks.picker.glab.Item[]
---@field picker? snacks.Picker
---@field main? number
---@field action? snacks.picker.Action

---@class snacks.glab.cli.Action.ctx
---@field item snacks.picker.glab.Item
---@field args string[]
---@field opts snacks.glab.cli.Action
---@field picker? snacks.Picker
---@field scratch? snacks.win
---@field main? number
---@field input? string

---@alias snacks.glab.action.fn fun(item?: snacks.picker.glab.Item, ctx: snacks.glab.action.ctx)

---@class snacks.glab.Action
---@field action snacks.glab.action.fn
---@field desc? string
---@field name? string
---@field priority? number
---@field title? string
---@field type? "mr" | "issue"
---@field enabled? fun(item: snacks.picker.glab.Item, ctx: snacks.glab.action.ctx): boolean

---@param item snacks.picker.glab.Item
---@param ctx snacks.glab.action.ctx
local function update_main(item, ctx)
  local glab = { repo = item.repo, iid = tonumber(item.iid) or item.iid, type = item.type }
  if ctx.main and vim.api.nvim_win_is_valid(ctx.main) then
    local buf = vim.api.nvim_win_get_buf(ctx.main)
    if vim.deep_equal(vim.b[buf].snacks_glab or {}, glab) then
      return ctx.main, buf
    end
  end
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.deep_equal(vim.b[buf].snacks_glab or {}, glab) then
    ctx.main = win
    return ctx.main, buf
  end
end

---@param item snacks.picker.glab.Item
---@param ctx snacks.glab.action.ctx
local function get_meta(item, ctx)
  local win, buf = update_main(item, ctx)
  if not win or not buf then
    return
  end
  local meta = Snacks.picker.highlight.meta(buf)
  ---@type {discussion_id?: string, note_id?: number, diff?: snacks.diff.Meta}?
  local m = meta and meta[vim.api.nvim_win_get_cursor(win)[1]] or nil
  return m, meta, buf, win
end

---@class snacks.glab.actions: {[string]:snacks.glab.Action}
M.actions = setmetatable({}, {
  __index = function(_, key)
    if type(key) ~= "string" then
      return nil
    end
    local action = M.cli_actions[key]
    if action then
      local ret = M.cli_action(action)
      rawset(M.actions, key, ret)
      return ret
    end
  end,
})

M.actions.glab_diff = {
  desc = "View MR diff",
  icon = " ",
  priority = 100,
  type = "mr",
  title = "View diff for MR !{iid}",
  action = function(item, ctx)
    if not item then
      return
    end
    Snacks.picker.glab_diff({
      show_delay = 0,
      repo = item.repo,
      mr = item.iid,
    })
  end,
}

M.actions.glab_open = {
  desc = "Open in buffer",
  icon = " ",
  priority = 100,
  title = "Open {type} {hash} in buffer",
  action = function(item, ctx)
    if ctx.picker then
      return Snacks.picker.actions.jump(ctx.picker, item, ctx.action)
    end
  end,
}

M.actions.glab_actions = {
  desc = "Show available actions",
  action = function(item, ctx)
    -- NOTE: this forwards split/vsplit/tab/drop actions to jump
    if ctx.action and ctx.action.cmd then
      return Snacks.picker.actions.jump(ctx.picker, item, ctx.action)
    end
    update_main(item, ctx)
    local actions = M.get_actions(item, ctx)
    actions.glab_actions = nil -- remove this action
    actions.glab_perform_action = nil -- remove this action
    Snacks.picker.glab_actions({
      item = item,
      layout = {
        config = function(layout)
          -- Fit list height to number of items, up to 10
          for _, box in ipairs(layout.layout) do
            if box.win == "list" and not box.height then
              box.height = math.max(math.min(vim.tbl_count(actions), vim.o.lines * 0.8 - 10), 3)
            end
          end
        end,
      },
      ---@param it snacks.picker.glab.Action
      confirm = function(picker, it, action)
        if not it then
          return
        end
        ctx.action = action
        if ctx.picker then
          ctx.picker.visual = ctx.picker.visual or picker.visual or nil
          ctx.picker:focus()
        end
        update_main(item, ctx)
        it.action.action(item, ctx)
        picker:close()
      end,
    })
  end,
}

M.actions.glab_perform_action = {
  action = function(item, ctx)
    if not item then
      return
    end
    -- pass a new context, since we're doing the action on a single item
    item.action.action(item.item, { items = { item.item } })
    ctx.picker:close()
  end,
}

M.actions.glab_browse = {
  desc = "Open in web browser",
  title = "Open {type} {hash} in web browser",
  icon = "󰖟 ",
  type = { "issue", "mr", "pipeline", "job" },
  action = function(_, ctx)
    for _, item in ipairs(ctx.items) do
      if item.type == "pipeline" or item.type == "job" then
        vim.ui.open(item.web_url)
      else
        Api.cmd(function()
          Snacks.notify.info(("Opened %s in web browser"):format(item.hash))
        end, {
          args = { item.type, "view", tostring(item.iid), "--web" },
          repo = item.repo,
        })
      end
    end
    if ctx.picker then
      ctx.picker.list:set_selected() -- clear selection
    end
  end,
}

M.actions.glab_react = {
  desc = "Add reaction",
  icon = " ",
  action = function(item, ctx)
    local reactions = { "thumbsup", "thumbsdown", "laughing", "tada", "confused", "heart", "rocket", "eyes" }
    Snacks.picker.pick("glab_reactions", {
      iid = item.iid,
      repo = item.repo,
      type = item.type,
      layout = {
        config = function(layout)
          for _, box in ipairs(layout.layout) do
            if box.win == "list" and not box.height then
              box.height = math.max(math.min(#reactions, vim.o.lines * 0.8 - 10), 3)
            end
          end
        end,
      },
      confirm = function(picker)
        local items = picker:selected({ fallback = true })
        for i, it in ipairs(items) do
          if it.added then
            M.cli(item, {
              api = {
                endpoint = "projects/{project}/" .. M.rest(item.type) .. "/{iid}/award_emoji/" .. tostring(it.id),
                method = "DELETE",
                silent = true,
              },
              refresh = i == #items,
            }, ctx)
          else
            M.cli(item, {
              api = {
                endpoint = "projects/{project}/" .. M.rest(item.type) .. "/{iid}/award_emoji",
                method = "POST",
                params = { name = it.reaction },
              },
              refresh = i == #items,
            }, ctx)
          end
        end
        picker:close()
      end,
    })
  end,
}

M.actions.glab_label = {
  desc = "Add/Remove labels",
  icon = "󰌕 ",
  action = function(item, ctx)
    Snacks.picker.pick("glab_labels", {
      iid = item.iid,
      repo = item.repo,
      type = item.type,
      confirm = function(picker)
        local labels = {} ---@type table<string, boolean>
        for _, label in ipairs(item.item.labels or {}) do
          labels[label.name] = true
        end
        for _, it in ipairs(picker:selected({ fallback = true })) do
          labels[it.label] = not it.added or nil
        end
        M.cli(item, {
          api = {
            endpoint = "projects/{project}/" .. M.rest(item.type) .. "/{iid}",
            method = "PUT",
            input = { labels = table.concat(vim.tbl_keys(labels), ",") },
          },
        }, ctx)
        picker:close()
      end,
    })
  end,
}

M.actions.glab_yank = {
  desc = "Yank URL(s) to clipboard",
  icon = " ",
  type = { "issue", "mr", "pipeline", "job" },
  action = function(_, ctx)
    if vim.fn.mode():find("^[vV]") and ctx.picker then
      ctx.picker.list:select()
    end
    ---@param it snacks.picker.glab.Item
    local urls = vim.tbl_map(function(it)
      return it.web_url
    end, ctx.items)
    if ctx.picker then
      ctx.picker.list:set_selected() -- clear selection
    end
    local value = table.concat(urls, "\n")
    vim.fn.setreg(vim.v.register or "+", value, "l")
    Snacks.notify.info("Yanked " .. #urls .. " URL(s)")
  end,
}

M.actions.glab_mr_pipelines = {
  desc = "View pipelines",
  title = "View pipelines for {type} {hash}",
  icon = " ",
  priority = 90,
  type = "mr",
  action = function(item, ctx)
    Snacks.picker.glab_pipeline({
      repo = item.repo,
      mr = item.iid,
    })
  end,
}

M.actions.glab_ci_jobs = {
  desc = "View jobs",
  title = "View jobs of pipeline {hash}",
  icon = " ",
  priority = 100,
  type = "pipeline",
  action = function(item, ctx)
    Snacks.picker.glab_job({
      repo = item.repo,
      pipeline = item.id,
    })
  end,
}

M.actions.glab_ci_run = {
  desc = "Run new pipeline",
  title = "Run a new pipeline on {ref}",
  icon = "󰀊 ",
  type = "pipeline",
  action = function(item, ctx)
    Snacks.picker.util.confirm(("Run a new pipeline on %s?"):format(item.ref), function()
      Api.cmd(function()
        vim.schedule(function()
          Snacks.notify.info(("Started a new pipeline on %s"):format(item.ref))
          if ctx.picker and not ctx.picker.closed then
            ctx.picker:refresh()
          end
        end)
      end, {
        args = { "ci", "run", "--branch", item.ref },
        repo = item.repo,
      })
    end)
  end,
}

M.actions.glab_job_log = {
  desc = "View log",
  title = "View log of job {name}",
  icon = " ",
  priority = 100,
  type = "job",
  action = function(item, ctx)
    Api.trace(function(trace)
      vim.schedule(function()
        if not trace or trace == "" then
          Snacks.notify.warn(("No log available for job %s"):format(item.name))
          return
        end
        local lines = M.clean_trace(trace)
        vim.cmd("botright split")
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(buf, ("glab-job-log://%s/%s"):format(item.id, item.name))
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.bo[buf].modifiable = false
        vim.bo[buf].bufhidden = "wipe"
        vim.bo[buf].filetype = "glablog"
        vim.api.nvim_win_set_buf(0, buf)
        vim.api.nvim_win_set_cursor(0, { #lines, 0 })
      end)
    end, { repo = item.repo, job = item.id })
  end,
}

M.actions.glab_reply_to_comment = {
  desc = "Reply to comment",
  title = "Reply to comment on {type} {hash}",
  priority = 150,
  icon = " ",
  enabled = function(item, ctx)
    local m = get_meta(item, ctx)
    return m and m.discussion_id ~= nil or false
  end,
  action = function(item, ctx)
    local m = get_meta(item, ctx)
    if not (m and m.discussion_id) then
      Snacks.notify.error("No comment found to reply to")
      return
    end
    local action = vim.deepcopy(M.cli_actions.glab_comment)
    action.title = "Reply to comment on {type} {hash}"
    action.api = {
      endpoint = "projects/{project}/"
        .. M.rest(item.type)
        .. "/{iid}/discussions/"
        .. tostring(m.discussion_id)
        .. "/notes",
      method = "POST",
    }
    M.cli(item, action, ctx)
  end,
}

M.actions.glab_diff_comment = {
  desc = "Add diff comment",
  title = "Comment on diff in {type} {hash}",
  priority = 150,
  icon = " ",
  type = "mr",
  enabled = function(item, ctx)
    local m = get_meta(item, ctx)
    return m and m.diff ~= nil or false
  end,
  action = function(item, ctx)
    local m, meta, buf = get_meta(item, ctx)
    if not (meta and buf and m and m.diff) then
      Snacks.notify.error("No diff hunk found to comment on")
      return
    end
    local diff_refs = item.item.diff_refs
    if not diff_refs then
      Snacks.notify.error("MR has no diff refs (try refreshing the MR)")
      return
    end

    local action = vim.deepcopy(M.cli_actions.glab_comment)
    local visual = ctx.picker and ctx.picker.visual or Snacks.picker.util.visual()
    visual = visual and visual.buf == buf and visual or nil
    local line = m.diff.line ---@type number
    local start_line ---@type number?
    if visual then
      local from, to = math.min(visual.pos[1], visual.end_pos[1]), math.max(visual.pos[1], visual.end_pos[1])
      local line_diff = vim.tbl_get(meta, to, "diff") or m.diff --[[@as snacks.diff.Meta]]
      local start_diff = vim.tbl_get(meta, from, "diff") or m.diff --[[@as snacks.diff.Meta]]
      if line_diff.file ~= start_diff.file then
        Snacks.notify.error("Cannot add comment: visual selection spans multiple files")
        return
      end
      local code = {} ---@type string[]
      for i = from, to do
        code[#code + 1] = vim.tbl_get(meta, i, "diff", "code") or ""
      end
      line, start_line = line_diff.line, start_diff.line
      local above = math.max((line or 1) - (start_line or line or 1), 0)
      local ft = vim.filetype.match({ filename = m.diff.file }) or ""
      -- GitLab multi-line suggestions use the `suggestion:-N+M` fence syntax
      local code_header = ("```%ssuggestion:-%d+0\n"):format(ft == "" and "" or (ft .. " "), above)
      action.template = ("\n%s%s\n```\n"):format(code_header, table.concat(code, "\n"))
      action.on_submit = function(body)
        local s, e = body:find(action.template, 1, true)
        if s and e then -- suggestion not edited, so remove it
          body = body:sub(1, s - 1) .. body:sub(e + 1)
        end
        body = body:gsub(vim.pesc(code_header), ("```suggestion:-%d+0\n"):format(above)) -- remove ft from fence
        return body
      end
    end
    if start_line and start_line ~= line then
      action.title = ("Comment on lines %s%d to %s%d"):format(
        m.diff.side:sub(1, 1):upper(),
        start_line,
        m.diff.side:sub(1, 1):upper(),
        line
      )
    else
      action.title = ("Comment on line %s%d"):format(m.diff.side:sub(1, 1):upper(), line)
    end
    ---@type snacks.glab.Position
    local position = {
      position_type = "text",
      base_sha = diff_refs.base_sha,
      start_sha = diff_refs.start_sha,
      head_sha = diff_refs.head_sha,
      new_path = m.diff.file,
      old_path = m.diff.file,
    }
    if m.diff.side == "left" then
      position.old_line = line
    else
      position.new_line = line
    end
    action.api = {
      endpoint = "projects/{project}/merge_requests/{iid}/discussions",
      method = "POST",
      input = { position = position },
    }
    M.cli(item, action, ctx)
  end,
}

M.actions.glab_comment = {
  desc = "Add comment",
  title = "Comment on {type} {hash}",
  icon = " ",
  action = function(item, ctx)
    local m = get_meta(item, ctx)
    if m and m.discussion_id then
      return M.actions.glab_reply_to_comment.action(item, ctx)
    elseif m and m.diff then
      return M.actions.glab_diff_comment.action(item, ctx)
    end
    local action = vim.deepcopy(M.cli_actions.glab_comment)
    M.cli(item, action, ctx)
  end,
}

--- REST collection name for a type
---@param type "issue" | "mr"
function M.rest(type)
  return type == "mr" and "merge_requests" or "issues"
end

---@type table<string, snacks.glab.cli.Action>
M.cli_actions = {
  glab_comment = {
    icon = " ",
    title = "Comment on {type} {hash}",
    success = "Commented on {type} {hash}",
    edit = "body",
    api = {
      endpoint = "projects/{project}/{collection}/{iid}/notes",
      method = "POST",
    },
  },
  glab_checkout = {
    cmd = "checkout",
    icon = " ",
    type = "mr",
    confirm = "Are you sure you want to checkout MR !{iid}?",
    title = "Checkout MR !{iid}",
    success = "Checked out MR !{iid}",
  },
  glab_close = {
    icon = config.icons.crossmark,
    cmd = "close",
    title = "Close {type} {hash}",
    success = "Closed {type} {hash}",
    enabled = function(item)
      return item.state == "open"
    end,
  },
  glab_edit = {
    icon = " ",
    fields = {
      { arg = "title", prop = "title", name = "Title" },
    },
    success = "Edited {type} {hash}",
    edit = "description",
    template = "{body}",
    title = "Edit {type} {hash}",
    api = {
      endpoint = "projects/{project}/{collection}/{iid}",
      method = "PUT",
    },
  },
  glab_merge = {
    cmd = "merge",
    icon = config.icons.mr.merged,
    type = "mr",
    success = "Merged MR !{iid}",
    title = "Merge MR !{iid}",
    confirm = "Are you sure you want to merge MR !{iid}?",
    enabled = function(item)
      return item.state == "open" and not item.item.draft
    end,
  },
  glab_squash = {
    cmd = "merge",
    icon = config.icons.mr.merged,
    type = "mr",
    success = "Squashed and merged MR !{iid}",
    args = { "--squash" },
    confirm = "Are you sure you want to squash and merge MR !{iid}?",
    title = "Squash and merge MR !{iid}",
    enabled = function(item)
      return item.state == "open" and not item.item.draft
    end,
  },
  glab_rebase = {
    cmd = "rebase",
    icon = "󰚰 ",
    type = "mr",
    title = "Rebase source branch of MR !{iid}",
    success = "Rebased source branch of MR !{iid}",
    enabled = function(item)
      return item.state == "open"
    end,
  },
  glab_reopen = {
    cmd = "reopen",
    icon = " ",
    title = "Reopen {type} {hash}",
    success = "Reopened {type} {hash}",
    enabled = function(item)
      return item.state == "closed"
    end,
  },
  glab_ready = {
    cmd = "update",
    args = { "--ready" },
    icon = config.icons.mr.open,
    type = "mr",
    title = "Mark MR !{iid} as ready for review",
    success = "Marked MR !{iid} as ready for review",
    enabled = function(item)
      return item.state == "open" and item.item.draft == true
    end,
  },
  glab_draft = {
    cmd = "update",
    args = { "--draft" },
    icon = config.icons.mr.draft,
    type = "mr",
    title = "Mark MR !{iid} as draft",
    success = "Marked MR !{iid} as draft",
    enabled = function(item)
      return item.state == "open" and not item.item.draft
    end,
  },
  glab_approve = {
    cmd = "approve",
    icon = config.icons.checkmark,
    type = "mr",
    title = "Approve MR !{iid}",
    success = "Approved MR !{iid}",
    enabled = function(item)
      return item.state == "open"
    end,
  },
  glab_revoke = {
    cmd = "revoke",
    icon = " ",
    type = "mr",
    title = "Revoke approval of MR !{iid}",
    success = "Revoked approval of MR !{iid}",
    enabled = function(item)
      return item.state == "open" and #(item.item.approved_by or {}) > 0
    end,
  },
  glab_ci_retry = {
    icon = "󰚰 ",
    type = "pipeline",
    title = "Retry pipeline {hash}",
    success = "Retried pipeline {hash}",
    api = {
      endpoint = "projects/{project}/pipelines/{id}/retry",
      method = "POST",
    },
    enabled = function(item)
      return item.status == "failed" or item.status == "canceled"
    end,
  },
  glab_ci_cancel = {
    icon = config.icons.crossmark,
    type = "pipeline",
    title = "Cancel pipeline {hash}",
    success = "Canceled pipeline {hash}",
    api = {
      endpoint = "projects/{project}/pipelines/{id}/cancel",
      method = "POST",
    },
    enabled = function(item)
      return vim.tbl_contains(
        { "created", "waiting_for_resource", "preparing", "pending", "running", "scheduled" },
        item.status
      )
    end,
  },
  glab_ci_delete = {
    icon = config.icons.crossmark,
    type = "pipeline",
    title = "Delete pipeline {hash}",
    success = "Deleted pipeline {hash}",
    confirm = "Are you sure you want to delete pipeline {hash}? This cannot be undone.",
    api = {
      endpoint = "projects/{project}/pipelines/{id}",
      method = "DELETE",
    },
  },
  glab_job_retry = {
    icon = "󰚰 ",
    type = "job",
    title = "Retry job {name}",
    success = "Retried job {name}",
    api = {
      endpoint = "projects/{project}/jobs/{id}/retry",
      method = "POST",
    },
    enabled = function(item)
      return vim.tbl_contains({ "failed", "canceled", "success" }, item.status)
    end,
  },
  glab_job_play = {
    icon = config.icons.pipeline.manual,
    type = "job",
    title = "Run manual job {name}",
    success = "Started job {name}",
    api = {
      endpoint = "projects/{project}/jobs/{id}/play",
      method = "POST",
    },
    enabled = function(item)
      return item.status == "manual"
    end,
  },
  glab_job_cancel = {
    icon = config.icons.crossmark,
    type = "job",
    title = "Cancel job {name}",
    success = "Canceled job {name}",
    api = {
      endpoint = "projects/{project}/jobs/{id}/cancel",
      method = "POST",
    },
    enabled = function(item)
      return vim.tbl_contains({ "created", "waiting_for_resource", "pending", "running" }, item.status)
    end,
  },
}

---@param opts snacks.glab.cli.Action
function M.cli_action(opts)
  ---@type snacks.glab.Action
  return setmetatable({
    desc = opts.desc or opts.title,
    ---@type snacks.glab.action.fn
    action = function(item, ctx)
      M.cli(item, opts, ctx)
    end,
  }, { __index = opts })
end

--- Strip ANSI escape sequences and CI section markers from a job trace
---@param text string
---@return string[] lines
function M.clean_trace(text)
  text = text:gsub("\r\n", "\n")
  text = text:gsub("\27%[[0-9;]*[a-zA-Z]", "") -- CSI sequences (colors, cursor)
  text = text:gsub("\27%]%d+;[^\7]*\7", "") -- OSC sequences
  text = text:gsub("section_start:%d+:%S+", ""):gsub("section_end:%d+:%S+", "")
  local lines = {} ---@type string[]
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    line = line:gsub(".*\r", "") -- keep only the final overwrite of progress lines
    lines[#lines + 1] = line
  end
  while #lines > 0 and lines[#lines]:match("^%s*$") do
    table.remove(lines)
  end
  return lines
end

---@param str string
---@param ... table<string, any>
function M.tpl(str, ...)
  local data = { ... }
  return Snacks.picker.util.tpl(
    str,
    setmetatable({}, {
      __index = function(_, key)
        for _, d in ipairs(data) do
          if d[key] ~= nil then
            local ret = d[key]
            return ret == "mr" and "MR" or ret
          end
        end
      end,
    })
  )
end

---@param item snacks.picker.glab.Item
---@param ctx snacks.glab.action.ctx
function M.get_actions(item, ctx)
  local ret = {} ---@type table<string, snacks.glab.Action>
  local keys = vim.tbl_keys(M.actions) ---@type string[]
  vim.list_extend(keys, vim.tbl_keys(M.cli_actions))
  for _, name in ipairs(keys) do
    local action = M.actions[name]
    local kinds = action.type == nil and { "issue", "mr" }
      or type(action.type) == "string" and { action.type }
      or action.type --[[@as string[] ]]
    local enabled = vim.tbl_contains(kinds, item.type)
    enabled = enabled and (action.enabled == nil or action.enabled(item, ctx))
    if enabled then
      local a = setmetatable({}, { __index = action })
      local ca = M.cli_actions[name] or {}
      a.desc = a.title and M.tpl(a.title or name, item, ca) or a.desc
      a.name = name
      ret[name] = a
    end
  end
  return ret
end

--- Executes a glab cli or api action
---@param item snacks.picker.glab.Item
---@param action snacks.glab.cli.Action
---@param ctx snacks.glab.action.ctx
function M.cli(item, action, ctx)
  local args = action.cmd and { item.type, action.cmd, tostring(item.iid) } or {}
  vim.list_extend(args, action.args or {})
  if action.api then
    action.api = vim.deepcopy(action.api)
    action.api.endpoint = action.api.endpoint:gsub("{collection}", M.rest(item.type))
    if item.id then
      action.api.endpoint = action.api.endpoint:gsub("{id}", tostring(item.id))
    end
    action.api.repo = action.api.repo or item.repo
    action.api.iid = action.api.iid or item.iid
  end
  ---@type snacks.glab.cli.Action.ctx
  local cli_ctx = {
    item = item,
    args = args,
    opts = action,
    picker = ctx.picker,
    main = ctx.main,
  }
  if action.edit then
    return M.edit(cli_ctx)
  else
    return M._run(cli_ctx)
  end
end

--- Parses frontmatter fields from body
---@param body string
---@param ctx snacks.glab.cli.Action.ctx
function M.parse(body, ctx)
  if not ctx.opts.fields then
    return body
  end

  local fields = {} ---@type table<string, snacks.glab.Field>
  for _, f in ipairs(ctx.opts.fields) do
    fields[f.name] = f
  end

  local values = {} ---@type table<string, string>
  --- parse markdown frontmatter for fields
  body = body:gsub("^(%-%-%-\n.-\n%-%-%-\n%s*)", function(fm)
    fm = fm:gsub("^%-%-%-\n", ""):gsub("\n%-%-%-\n%s*$", "") --[[@as string]]
    local lines = vim.split(fm, "\n")
    for _, line in ipairs(lines) do
      local field, value = line:match("^(%w+):%s*(.-)%s*$")
      if field and fields[field] then
        values[field] = value
      else
        Snacks.notify.warn(("Unknown field `%s` in frontmatter"):format(field or line))
      end
    end
    return ""
  end) --[[@as string]]

  for _, field in ipairs(ctx.opts.fields) do
    local value = values[field.name]
    if value then
      if ctx.opts.api then
        ctx.opts.api.input = ctx.opts.api.input or {}
        ctx.opts.api.input[field.arg] = value
      else
        vim.list_extend(ctx.args, { "--" .. field.arg, value })
      end
    else
      Snacks.notify.error(("Missing required field `%s` in frontmatter"):format(field.name))
      return
    end
  end
  return body
end

--- Executes the action CLI command
---@param ctx snacks.glab.cli.Action.ctx
function M._run(ctx, force)
  if not force and ctx.opts.confirm then
    Snacks.picker.util.confirm(M.tpl(ctx.opts.confirm, ctx.item, ctx.opts), function()
      M._run(ctx, true)
    end)
    return
  end

  local spinner = require("snacks.picker.util.spinner").loading()
  local cb = function()
    vim.schedule(function()
      spinner:stop()

      -- success message
      if ctx.opts.success then
        Snacks.notify.info(M.tpl(ctx.opts.success, ctx.item, ctx.opts))
      end

      -- refresh item and picker
      if ctx.opts.refresh ~= false then
        vim.schedule(function()
          Api.refresh(ctx.item)
          if ctx.picker and not ctx.picker.closed then
            ctx.picker:refresh()
          end
        end)
        if ctx.picker and not ctx.picker.closed then
          ctx.picker:focus()
        end
      end

      -- clean up scratch buffer
      if ctx.scratch then
        local buf = assert(ctx.scratch.buf)
        local fname = vim.api.nvim_buf_get_name(buf)
        ctx.scratch:on("WinClosed", function()
          vim.schedule(function()
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
            os.remove(fname)
            os.remove(fname .. ".meta")
          end)
        end, { buf = true })
        ctx.scratch:close()
      end
    end)
  end

  if ctx.opts.api then
    Api.request(
      cb,
      Snacks.config.merge(vim.deepcopy(ctx.opts.api), {
        on_error = function()
          spinner:stop()
        end,
      })
    )
  else
    Api.cmd(cb, {
      input = ctx.input,
      args = ctx.args,
      repo = ctx.item.repo or ctx.opts.repo,
      on_error = function()
        spinner:stop()
      end,
    })
  end
end

--- Edit action body in scratch buffer
---@param ctx snacks.glab.cli.Action.ctx
function M.edit(ctx)
  ---@param s? string
  local function tpl(s)
    return s and M.tpl(s, ctx.item, ctx.opts) or nil
  end

  local template = ctx.opts.template or ""
  if not vim.tbl_isempty(ctx.opts.fields or {}) then
    local fm = { "---" }
    for _, f in ipairs(ctx.opts.fields) do
      fm[#fm + 1] = ("%s: {%s}"):format(f.name, f.prop)
    end
    fm[#fm + 1] = "---\n\n"
    template = table.concat(fm, "\n") .. template
  end

  local preview = ctx.picker and ctx.picker.preview and ctx.picker.preview.win:valid() and ctx.picker.preview.win
    or nil
  local actions = preview and preview.opts.actions or {}
  local parent = ctx.main or preview and preview.win or vim.api.nvim_get_current_win()

  local height = config.scratch.height or 15
  local opts = Snacks.win.resolve({
    relative = "win",
    width = 0,
    backdrop = false,
    height = height,
    actions = {
      cycle_win = actions.cycle_win,
      preview_scroll_up = actions.preview_scroll_up,
      preview_scroll_down = actions.preview_scroll_down,
    },
    win = parent,
    wo = { winhighlight = "NormalFloat:Normal,FloatTitle:SnacksGlabScratchTitle,FloatBorder:SnacksGlabScratchBorder" },
    border = "top_bottom",
    row = function(win)
      local border = win:border_size()
      return win:parent_size().height - height - border.top - border.bottom
    end,
    on_win = function(win)
      if vim.api.nvim_win_is_valid(parent) then
        local parent_row = vim.api.nvim_win_call(parent, vim.fn.winline) ---@type number
        parent_row = parent_row + vim.wo[parent].scrolloff -- adjust for scrolloff
        local row = vim.api.nvim_win_get_height(parent) - win:size().height
        if parent_row > row then
          vim.api.nvim_win_call(parent, function()
            vim.cmd(("normal! %d%s"):format(parent_row - row, Snacks.util.keycode("<C-e>")))
          end)
        end
      end
      vim.g.snacks_picker_cycle_win = win.win
      vim.schedule(function()
        vim.cmd.startinsert()
      end)
    end,
    footer_keys = { "<c-s>", "R" },
    keys = {
      submit = {
        "<c-s>",
        function(win)
          ctx.scratch = win
          M.submit(ctx)
        end,
        desc = "Submit",
        mode = { "n", "i" },
      },
    },
  }, preview and {
    keys = {
      ["<a-w>"] = { "cycle_win", mode = { "i", "n" } },
      ["<c-b>"] = { "preview_scroll_up", mode = { "i", "n" } },
      ["<c-f>"] = { "preview_scroll_down", mode = { "i", "n" } },
    },
  } or nil)
  Snacks.scratch({
    ft = "markdown",
    icon = config.icons.logo,
    name = tpl(ctx.opts.title or "{cmd} {type} {hash}"),
    template = tpl(template),
    filekey = {
      cwd = false,
      branch = false,
      count = false,
      id = tpl("{repo}/{type}/{cmd}"),
    },
    win = opts,
  })
end

--- Submit edited body
---@param ctx snacks.glab.cli.Action.ctx
function M.submit(ctx)
  local edit = assert(ctx.opts.edit, "Submit called for action that doesn't need edit?")
  local win = assert(ctx.scratch, "Submit not called from scratch window?")
  ctx = setmetatable({
    args = vim.deepcopy(ctx.args),
  }, { __index = ctx }) -- shallow copy to avoid mutation
  local body = M.parse(win:text(), ctx)

  if not body then
    return -- error already shown in M.parse
  end

  if ctx.opts.on_submit then
    body = ctx.opts.on_submit(body, ctx) or body
  end

  if body:find("%S") then
    if ctx.opts.api then
      ctx.opts.api.input = ctx.opts.api.input or {}
      ctx.opts.api.input[edit] = body
    else
      vim.list_extend(ctx.args, { "--" .. edit, body })
    end
  end

  vim.cmd.stopinsert()
  vim.schedule(function()
    M._run(ctx)
  end)
end

return M
