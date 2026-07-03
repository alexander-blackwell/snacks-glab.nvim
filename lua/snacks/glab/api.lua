local Async = require("snacks.picker.util.async")
local Item = require("snacks.glab.item")
local Proc = require("snacks.util.spawn")

---@class snacks.glab.api
local M = {}

---@type table<string, snacks.picker.glab.Item>
local cache = setmetatable({}, { __mode = "v" })
local mr_cache = {} ---@type table<string, snacks.picker.glab.Item?>

--- pseudo-fields fetched by `view` (glab has no field selection like `gh --json`,
--- so we track whole responses instead of individual fields)
local view_fields = {
  issue = { "detail", "discussions", "awards" },
  mr = { "detail", "discussions", "awards", "approvals" },
}

---@type table<string, snacks.glab.api.Config|{}>
local config = {
  base = {
    text = { "author", "hash", "label", "title" },
    options = { "assignee", "author", "label", "milestone", "search", "group" },
  },
  issue = {
    options = {},
    ---@param item snacks.picker.glab.Item
    transform = function(item)
      item.status = item.state
      return item
    end,
  },
  mr = {
    options = { "reviewer" },
    ---@param item snacks.picker.glab.Item
    transform = function(item)
      item.status = (item.state == "open" and item.item.draft) and "draft" or item.state
      return item
    end,
  },
}

---@param item snacks.glab.api.View
local function cache_get(item)
  return cache[Item.to_uri(item)]
end

---@param item snacks.picker.glab.Item
local function cache_set(item)
  cache[item.uri] = item
  return item
end

---@generic T
---@param fn fun(cb:fun(proc:snacks.spawn.Proc, data?:any), opts:T): snacks.spawn.Proc
---@return fun(opts:T): any?
local function wrap_sync(fn)
  ---@async
  return function(opts)
    local ret ---@type any
    fn(function(_, data)
      ret = data
    end, opts):wait()
    return ret
  end
end

---@param what "issue" | "mr"
local function get_opts(what)
  local base = vim.deepcopy(config.base)
  local specific = vim.deepcopy(config[what] or {})
  base.type = what
  base.fields = { "list" }
  base.text = vim.list_extend(base.text, specific.text or {})
  base.options = vim.list_extend(base.options, specific.options or {})
  base.transform = specific.transform
  return base
end

---@param repo? string
local function enc(repo)
  -- url-encode the project path; `:id` resolves from the cwd repo as a fallback
  return repo and repo:gsub("/", "%%2F") or ":id"
end

--- REST collection name for a type
---@param type "issue" | "mr"
local function rest(type)
  return type == "mr" and "merge_requests" or "issues"
end

--- Build a project-scoped endpoint for an item
---@param item snacks.glab.api.View
---@param suffix? string
function M.endpoint(item, suffix)
  return ("projects/%s/%s/%s%s"):format(enc(item.repo), rest(item.type), tostring(item.iid), suffix or "")
end

---@param args string[]
---@param options string[]
---@param opts table<string, string|boolean|nil>
local function set_options(args, options, opts)
  for _, option in ipairs(options or {}) do
    local value = opts[option] ---@type string|boolean|nil
    if type(value) == "boolean" and value then
      args[#args + 1] = "--" .. option
    elseif value and value ~= "" then
      vim.list_extend(args, { "--" .. option, tostring(value) })
    end
  end
end

---@param cb fun(proc: snacks.spawn.Proc, data?: string)
---@param opts snacks.glab.api.Cmd
function M.cmd(cb, opts)
  opts = opts or {}
  local glab = require("snacks.glab").config().cmd or "glab"
  local args = vim.deepcopy(opts.args)
  if opts.repo then
    vim.list_extend(args, { "--repo", opts.repo })
  end
  local async = Async.running()
  local ret ---@type snacks.spawn.Proc

  if async then
    async:on("abort", function()
      if ret and ret:running() then
        ret:kill()
      end
    end)
  end
  ret = Proc.new({
    cmd = glab,
    args = args,
    input = opts.input,
    timeout = 10000,
    on_exit = function(proc, err)
      if err then
        vim.schedule(function()
          if not proc.aborted then
            if opts.notify ~= false then
              Snacks.debug.cmd({
                header = "GitLab Error",
                cmd = { glab, unpack(args) },
                footer = proc:err(),
                level = vim.log.levels.ERROR,
                props = { input = opts.input },
              })
            end
            if opts.on_error then
              opts.on_error(proc, proc:err())
            end
          end
        end)
        return
      end
      return cb(proc, not err and proc:out() or nil)
    end,
  })
  return ret
end
M.cmd_sync = wrap_sync(M.cmd)

--- Run a glab command with `--output json` and parse the result
---@param cb fun(proc: snacks.spawn.Proc, data?: unknown)
---@param opts snacks.glab.api.Cmd
function M.fetch(cb, opts)
  local args = vim.deepcopy(opts.args)
  vim.list_extend(args, { "--output", "json" })
  return M.cmd(function(proc, data)
    cb(proc, data and data:find("%S") and proc:json() or nil)
  end, {
    args = args,
    repo = opts.repo,
    notify = opts.notify,
    on_error = opts.on_error,
  })
end
M.fetch_sync = wrap_sync(M.fetch)

--- Make a GitLab REST API request via `glab api`.
--- The endpoint may contain `{project}` and `{iid}` placeholders,
--- expanded from `opts.repo` / `opts.iid`.
---@param cb fun(proc: snacks.spawn.Proc, data?: table)
---@param opts snacks.glab.api.Api
function M.request(cb, opts)
  local endpoint = opts.endpoint
  endpoint = endpoint:gsub("{project}", enc(opts.repo))
  endpoint = endpoint:gsub("{iid}", opts.iid and tostring(opts.iid) or "{iid}")
  local args = { "api", endpoint }
  for _, option in ipairs({ "method", "paginate", "silent" }) do
    local value = opts[option]
    if type(value) == "boolean" and value then
      args[#args + 1] = "--" .. option
    elseif value and value ~= "" then
      vim.list_extend(args, { "--" .. option, tostring(value) })
    end
  end
  if opts.input then
    vim.list_extend(args, { "--input", "-" })
  end
  for k, v in pairs(opts.fields or {}) do
    vim.list_extend(args, { "--raw-field", ("%s=%s"):format(k, tostring(v)) })
  end
  for k, v in pairs(opts.params or {}) do
    vim.list_extend(args, { "--field", ("%s=%s"):format(k, tostring(v)) })
  end
  for k, v in pairs(opts.header or {}) do
    vim.list_extend(args, { "--header", ("%s:%s"):format(k, tostring(v)) })
  end
  return M.cmd(function(proc, data)
    cb(proc, data and data:find("%S") and proc:json() or nil)
  end, {
    args = args,
    input = opts.input and vim.json.encode(opts.input) or nil,
    on_error = opts.on_error,
  })
end
M.request_sync = wrap_sync(M.request)

---@async
function M.user()
  ---@type snacks.glab.User
  return M.request_sync({
    endpoint = "user",
  })
end

---@param what "issue" | "mr"
---@param cb fun(items?: snacks.picker.glab.Item[])
---@param opts? snacks.picker.glab.Config|{}
function M.list(what, cb, opts)
  opts = opts or {}
  local api_opts = get_opts(what)
  api_opts.repo = opts.repo
  local args = { what, "list" }

  vim.list_extend(args, { "--per-page", tostring(math.min(opts.limit or 50, 100)) })

  -- state: open (default) | closed | merged (mr) | all
  local state = opts.state
  if state == "closed" then
    args[#args + 1] = "--closed"
  elseif state == "merged" and what == "mr" then
    args[#args + 1] = "--merged"
  elseif state == "all" then
    args[#args + 1] = "--all"
  end

  -- draft filter (mr only)
  if what == "mr" and opts.draft ~= nil then
    args[#args + 1] = opts.draft and "--draft" or "--not-draft"
  end

  set_options(args, api_opts.options, opts)

  ---@param data? snacks.glab.Item[]
  return M.fetch(function(_, data)
    if not data or vim.tbl_isempty(data) and not vim.islist(data) then
      return cb()
    end
    ---@param item snacks.glab.Item
    return cb(vim.tbl_map(function(item)
      return cache_set(Item.new(item, api_opts))
    end, data))
  end, {
    args = args,
    repo = opts.repo,
    notify = opts.notify,
  })
end

--- Fetch the full item: detail, discussions, award emoji and approvals (MRs).
--- Only fetches what the item doesn't have yet, unless `force` is set.
---@param cb fun(item?: snacks.picker.glab.Item, updated?: boolean)
---@param item snacks.glab.api.View|{iid?: number}
---@param opts? { force?: boolean }
function M.view(cb, item, opts)
  opts = opts or {}
  local api_opts = get_opts(item.type)
  api_opts.repo = item.repo

  item = M.get_cached(item)
  local all = view_fields[item.type] or view_fields.issue
  local todo = Item.is(item) and item:need(all) or vim.deepcopy(all)
  if opts.force or item.dirty then
    todo = vim.deepcopy(all)
  end

  if #todo == 0 then
    cb(item, false)
    return
  end

  local it = {} ---@type table<string, any>
  local completed = 0
  local procs = {} ---@type snacks.spawn.Proc[]

  local function done()
    completed = completed + 1
    if completed < #procs then
      return
    end
    if Item.is(item) then
      item:update(it, todo)
    else
      it = vim.tbl_extend("force", { iid = item.iid }, it)
      item = Item.new(it, api_opts)
      item:update({}, todo)
    end
    item.dirty = false
    cb(cache_set(item --[[@as snacks.picker.glab.Item]]), true)
  end

  ---@type table<string, {endpoint: string, transform: fun(data: any): table<string, any>}>
  local requests = {
    detail = {
      endpoint = M.endpoint(item),
      transform = function(data)
        return data or {}
      end,
    },
    discussions = {
      endpoint = M.endpoint(item, "/discussions?per_page=100"),
      transform = function(data)
        return { discussions = data or {} }
      end,
    },
    awards = {
      endpoint = M.endpoint(item, "/award_emoji?per_page=100"),
      transform = function(data)
        return { award_emoji = data or {} }
      end,
    },
    approvals = {
      endpoint = M.endpoint(item, "/approvals"),
      transform = function(data)
        ---@param a {user: snacks.glab.User}
        return {
          approved_by = vim.tbl_map(function(a)
            return a.user
          end, data and data.approved_by or {}),
        }
      end,
    },
  }

  for _, field in ipairs(todo) do
    local req = requests[field]
    if req then
      procs[#procs + 1] = M.request(function(_, data)
        it = vim.tbl_extend("force", it, req.transform(data))
        done()
      end, {
        endpoint = req.endpoint,
        on_error = function()
          done() -- keep going; partial view is better than none
        end,
      })
    end
  end

  ---@type snacks.picker.Waitable
  return {
    ---@async
    wait = function()
      for _, proc in ipairs(procs) do
        proc:wait()
      end
    end,
  }
end

---@param item snacks.glab.api.View
---@param opts? { force?: boolean }
---@async
function M.get(item, opts)
  local ret ---@type snacks.picker.glab.Item?
  local procs = M.view(function(it)
    ret = it
  end, item, opts)
  if procs then
    procs:wait()
  end
  return ret
end

---@param item snacks.glab.api.View
function M.get_cached(item)
  return not Item.is(item) and cache_get(item) or item
end

--- Mark an item dirty and re-render any buffers showing it
---@param item snacks.picker.glab.Item
function M.refresh(item)
  item.dirty = true
  cache_set(item)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      if vim.api.nvim_buf_get_name(buf) == item.uri then
        require("snacks.glab.buf").attach(buf, item)
      end
    end
  end
end

--- MR associated with the current branch, if any
---@async
function M.current_mr()
  local root = Snacks.git.get_root(vim.fn.getcwd() or ".")
  if not root then
    return
  end
  local branch = Proc.exec({ "git", "branch", "--show-current" })
  branch = branch and vim.trim(branch) or ""

  local key = root .. "::" .. branch
  if mr_cache[key] ~= nil then
    return mr_cache[key] or nil
  end

  local api_opts = get_opts("mr")
  ---@type snacks.glab.Item?
  local mr = M.fetch_sync({
    args = { "mr", "view" },
    notify = false,
  })
  mr = mr and mr.iid and cache_set(Item.new(mr, api_opts)) or nil
  mr_cache[key] = mr or false
  return mr
end

return M
