local Actions = require("snacks.glab.actions")
local Api = require("snacks.glab.api")

local M = {}

M.actions = setmetatable({}, {
  __index = function(t, k)
    if type(k) ~= "string" then
      return
    end
    if not Actions.actions[k] then
      return nil
    end
    ---@type snacks.picker.Action
    local action = {
      desc = Actions.actions[k].desc,
      action = function(picker, item, action)
        local items = picker:selected({ fallback = true })
        if item.glab_item then
          item = item.glab_item
          items = { item }
        end
        ---@diagnostic disable-next-line: param-type-mismatch
        return Actions.actions[k].action(item, {
          picker = picker,
          items = items,
          action = action,
        })
      end,
    }
    rawset(t, k, action)
    return action
  end,
})

---@param opts snacks.picker.glab.list.Config
---@type snacks.picker.finder
function M.glab(opts, ctx)
  if ctx.filter.search ~= "" then
    opts.search = ctx.filter.search
  end
  ---@async
  return function(cb)
    Api.list(opts.type, function(items)
      for _, item in ipairs(items or {}) do
        cb(item)
      end
    end, opts):wait()
  end
end

---@param opts snacks.picker.glab.issue.Config
---@type snacks.picker.finder
function M.issue(opts, ctx)
  return M.glab(
    vim.tbl_extend("force", {
      type = "issue",
    }, opts),
    ctx
  )
end

---@param opts snacks.picker.glab.mr.Config
---@type snacks.picker.finder
function M.mr(opts, ctx)
  return M.glab(
    vim.tbl_extend("force", {
      type = "mr",
    }, opts),
    ctx
  )
end

---@param opts snacks.picker.glab.actions.Config
---@type snacks.picker.finder
function M.get_actions(opts, ctx)
  opts = opts or {}
  ---@async
  return function(cb)
    local item = opts.item
    if not opts.item and not opts.iid then
      item = Api.current_mr()
    end

    if not item then
      local required = { "type", "repo", "iid" }
      local missing = vim.tbl_filter(function(field)
        return opts[field] == nil
      end, required) ---@type string[]
      if #missing > 0 then
        Snacks.notify.error({
          "Missing required options for `Snacks.picker.glab_actions()`:",
          "- `" .. table.concat(missing, ", ") .. "`",
          "",
          "Either provide the fields, or run in a git repo with a **current MR**.",
        }, { title = "Snacks Picker GitLab Actions" })
        return
      end
      item = Api.get({ type = opts.type or "mr", repo = opts.repo, iid = opts.iid })
      if not item then
        Snacks.notify.error("snacks.picker.glab.get_actions: Failed to get item")
        return
      end
    end

    local actions = ctx.async:schedule(function()
      return Actions.get_actions(item, {
        picker = ctx.picker,
        items = { item },
      })
    end)
    actions.glab_actions = nil -- remove this action
    actions.glab_perform_action = nil -- remove this action
    local items = {} ---@type snacks.picker.finder.Item[]
    for name, action in pairs(actions) do
      ---@class snacks.picker.glab.Action: snacks.picker.finder.Item
      items[#items + 1] = {
        text = Snacks.picker.util.text(action, { "name", "desc" }),
        file = item.uri,
        name = name,
        item = item,
        desc = action.desc or name,
        action = action,
      }
    end
    table.sort(items, function(a, b)
      local pa = a.action.priority or 0
      local pb = b.action.priority or 0
      if pa ~= pb then
        return pa > pb
      end
      return a.desc < b.desc
    end)
    for i, it in ipairs(items) do
      it.text = ("%d. %s"):format(i, it.text)
      cb(it)
    end
  end
end

---@param opts snacks.picker.glab.diff.Config
---@type snacks.picker.finder
function M.diff(opts, ctx)
  opts = opts or {}
  if not opts.mr then
    Snacks.notify.error("snacks.picker.glab.diff: `opts.mr` is required")
    return {}
  end
  local cwd = ctx:git_root()
  local args = { "mr", "diff", tostring(opts.mr), "--raw", "--color", "never" }
  if opts.repo then
    vim.list_extend(args, { "--repo", opts.repo })
  end

  opts.previewers.diff.style = "fancy" -- only fancy style supports inline discussion threads

  local Render = require("snacks.glab.render")
  local Diff = require("snacks.picker.source.diff")
  ---@async
  return function(cb)
    local item = Api.get({ type = "mr", repo = opts.repo, iid = opts.mr })

    -- fetch on the main thread since rendering uses non-fast APIs
    local annotations = ctx.async:schedule(function()
      return Render.annotations(item)
    end)

    Diff.diff(
      ctx:opts({
        cmd = require("snacks.glab").config().cmd or "glab",
        args = args,
        cwd = cwd,
        annotations = annotations,
      }),
      ctx
    )(function(it)
      it.glab_item = item
      cb(it)
    end)
  end
end

---@param opts snacks.picker.glab.reactions.Config
---@type snacks.picker.finder
function M.reactions(opts, ctx)
  if not opts.repo then
    Snacks.notify.error("snacks.picker.glab.reactions: `opts.repo` is required")
    return {}
  end
  if not opts.iid then
    Snacks.notify.error("snacks.picker.glab.reactions: `opts.iid` is required")
    return {}
  end

  local all = { "thumbsup", "thumbsdown", "laughing", "tada", "confused", "heart", "rocket", "eyes" }
  ---@async
  return function(cb)
    local items = {} ---@type table<string, snacks.picker.finder.Item>
    local user = Api.user()

    local collection = opts.type == "issue" and "issues" or "merge_requests"
    ---@type snacks.glab.Award[]?
    local awards = Api.request_sync({
      endpoint = ("projects/{project}/%s/{iid}/award_emoji?per_page=100"):format(collection),
      repo = opts.repo,
      iid = opts.iid,
    })

    for _, award in ipairs(awards or {}) do
      if user and award.user and award.user.username == user.username then
        items[award.name] = {
          text = award.name,
          reaction = award.name,
          added = true,
          id = award.id,
        }
      end
    end

    for _, reaction in ipairs(all) do
      cb(items[reaction] or {
        text = reaction,
        reaction = reaction,
        added = false,
      })
    end
  end
end

---@param opts snacks.picker.glab.labels.Config
---@type snacks.picker.finder
function M.labels(opts, ctx)
  if not opts.repo then
    Snacks.notify.error("snacks.picker.glab.labels: `opts.repo` is required")
    return {}
  end
  if not opts.iid then
    Snacks.notify.error("snacks.picker.glab.labels: `opts.iid` is required")
    return {}
  end

  ---@async
  return function(cb)
    ---@type snacks.glab.Label[]?
    local labels = Api.request_sync({
      endpoint = "projects/{project}/labels?per_page=100",
      repo = opts.repo,
    })
    local item = Api.get_cached({ type = opts.type, repo = opts.repo, iid = opts.iid })
    local added = {} ---@type table<string, boolean>
    if item and item.item then
      for _, label in ipairs(item.item.labels or {}) do
        added[label.name] = true
      end
    end
    labels = labels or {}
    table.sort(labels, function(a, b)
      if added[a.name] ~= added[b.name] then
        return added[a.name] == true
      end
      return (a.name or ""):lower() < (b.name or ""):lower()
    end)

    for _, label in ipairs(labels) do
      cb({
        text = label.name,
        label = label.name,
        added = added[label.name] == true,
        item = label,
      })
    end
  end
end

---@param item snacks.picker.glab.Item
---@type snacks.picker.format
function M.format(item, picker)
  local ret = {} ---@type snacks.picker.Highlight[]
  local a = Snacks.picker.util.align

  local config = require("snacks.glab").config()
  -- Status Icon
  local icons = config.icons[item.type]
  local status = icons[item.status] and item.status or "other"
  if status then
    local icon = icons[status]
    local icon_hl = "SnacksGlab" .. Snacks.picker.util.title(item.type) .. Snacks.picker.util.title(status)
    ret[#ret + 1] = { a(icon, 2), icon_hl }
    ret[#ret + 1] = { " " }
  end

  -- Number (issues use #, MRs use !)
  if item.hash then
    ret[#ret + 1] = { a(item.hash, 6), "SnacksPickerDimmed" }
  end

  -- Title
  if item.title then
    item.msg = item.title
    Snacks.picker.highlight.extend(ret, Snacks.picker.format.commit_message(item, picker))
  end

  -- Author
  if item.author then
    ret[#ret + 1] = { " ", nil }
    ret[#ret + 1] = { "@" .. item.author, "SnacksPickerGitAuthor" }
  end

  -- Labels
  for _, label in ipairs(item.item.labels or {}) do
    ret[#ret + 1] = { " ", nil }
    local badge = label.color and Snacks.picker.highlight.badge(label.name, label.color)
      or Snacks.picker.highlight.badge(label.name, "SnacksGlabLabel")
    vim.list_extend(ret, badge)
  end

  return ret
end

---@param ctx snacks.picker.preview.ctx
function M.preview_diff(ctx)
  Snacks.picker.preview.diff(ctx)
  local item = ctx.item.glab_item ---@type snacks.picker.glab.Item?
  if item then
    vim.b[ctx.buf].snacks_glab = {
      repo = item.repo,
      type = item.type,
      iid = tonumber(item.iid) or item.iid,
    }
  end
end

---@param ctx snacks.picker.preview.ctx
function M.preview(ctx)
  local config = require("snacks.glab").config()
  local item = ctx.item
  item.wo = config.wo
  item.bo = config.bo
  item.preview_title = ("%s %s %s"):format(
    config.icons.logo,
    (item.type == "issue" and "Issue" or "MR"),
    (item.hash or "")
  )
  return Snacks.picker.preview.file(ctx)
end

---@type snacks.picker.format
function M.format_label(item, picker)
  local ret = {} ---@type snacks.picker.Highlight[]
  local added = item.added
  if picker.list:is_selected(item) then
    added = not added -- reflect the change that will happen on action
  end
  ret[#ret + 1] = { added and "󰱒 " or "󰄱 ", "SnacksPickerDelim" }
  ret[#ret + 1] = { " " }
  local badge = item.item.color and Snacks.picker.highlight.badge(item.label, item.item.color)
    or Snacks.picker.highlight.badge(item.label, "SnacksGlabLabel")
  vim.list_extend(ret, badge)
  return ret
end

---@param item snacks.picker.glab.Action
---@type snacks.picker.format
function M.format_action(item, picker)
  local ret = {} ---@type snacks.picker.Highlight[]

  if item.action.icon then
    ret[#ret + 1] = { item.action.icon, "Special" }
    ret[#ret + 1] = { " " }
  end

  local count = picker:count()
  local idx = tostring(item.idx)
  idx = (" "):rep(#tostring(count) - #idx) .. idx
  ret[#ret + 1] = { idx .. ".", "SnacksPickerIdx" }

  ret[#ret + 1] = { " " }

  if item.desc then
    ret[#ret + 1] = { item.desc or "" }
    Snacks.picker.highlight.highlight(ret, {
      ["[#!]%d+"] = "Number",
    })
  end
  return ret
end

---@type snacks.picker.format
function M.format_reaction(item, picker)
  local config = require("snacks.glab").config()
  local ret = {} ---@type snacks.picker.Highlight[]
  local name = item.reaction
  local added = item.added
  if picker.list:is_selected(item) then
    added = not added -- reflect the change that will happen on action
  end
  ret[#ret + 1] = { added and "󰱒 " or "󰄱 ", "SnacksPickerDelim" }
  ret[#ret + 1] = { " " }
  ret[#ret + 1] = { config.icons.reactions[name] or name }
  return ret
end

return M
