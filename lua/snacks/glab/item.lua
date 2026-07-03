---@class snacks.picker.glab.Item
---@field opts snacks.glab.api.Config
local M = {}

local time_fields = {
  created = "created_at",
  updated = "updated_at",
  closed = "closed_at",
  merged = "merged_at",
}

--- Parse a GitLab ISO8601 timestamp.
--- Handles fractional seconds and both `Z` and `±hh:mm` offsets:
--- `2024-01-15T10:30:45.123Z`, `2024-01-15T10:30:45+05:30`
---@param s? string
---@return number?
local function ts(s)
  if type(s) ~= "string" then
    return nil
  end
  local year, month, day, hour, min, sec, rest = s:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)(.*)$")
  if not year then
    return
  end
  rest = rest:gsub("^%.%d+", "") -- drop fractional seconds
  local offset = 0
  if rest ~= "" and rest ~= "Z" then
    local sign, oh, om = rest:match("^([+-])(%d%d):?(%d%d)$")
    if sign then
      offset = (tonumber(oh) * 3600 + tonumber(om) * 60) * (sign == "-" and -1 or 1)
    end
  end
  local t = os.time({
    year = assert(tonumber(year), "invalid year in timestamp: " .. s),
    month = assert(tonumber(month), "invalid month in timestamp: " .. s),
    day = assert(tonumber(day), "invalid day in timestamp: " .. s),
    hour = assert(tonumber(hour), "invalid hour in timestamp: " .. s),
    min = assert(tonumber(min), "invalid minute in timestamp: " .. s),
    sec = assert(tonumber(sec), "invalid second in timestamp: " .. s),
    isdst = false,
  })
  -- `t` was interpreted as local time; shift to UTC, then apply the input offset
  local now = os.time()
  local utc_date = os.date("!*t", now) --[[@as osdate]]
  utc_date.isdst = false
  local utc_offset = os.difftime(now, os.time(utc_date))
  return t + utc_offset - offset
end
M.ts = ts

---@param obj {body?:string, created_at?:string, created?:number}
local function fix(obj)
  obj.body = obj.body and obj.body:gsub("\r\n", "\n") or nil
  obj.created = obj.created or ts(obj.created_at)
end

---@param item snacks.glab.Item
---@param opts snacks.glab.api.Config
function M.new(item, opts)
  if getmetatable(item) == M then
    return item --[[@as snacks.picker.glab.Item]]
  end
  local self = setmetatable({}, M) --[[@as snacks.picker.glab.Item]]
  for k, v in pairs(item) do
    if v == vim.NIL then
      item[k] = nil
    end
  end
  self.item = item
  self.opts = opts
  self.type = opts.type
  self.repo = opts.repo
  self.fields = {}
  for _, field in ipairs(opts.fields or {}) do
    self.fields[field] = true
  end
  self:update()
  return self --[[@as snacks.picker.glab.Item]]
end

---@param item any
function M.is(item)
  return getmetatable(item) == M
end

function M:__index(key)
  if time_fields[key] then
    return ts(self.item[time_fields[key]])
  end
  return rawget(M, key) or rawget(self.item, key)
end

---@param fields string[]
function M:need(fields)
  ---@param field string
  return vim.tbl_filter(function(field)
    return not self.fields[field]
  end, fields)
end

---@param data? table<string, any>
---@param fields? string[]
function M:update(data, fields)
  for k, v in pairs(data or {}) do
    ---@diagnostic disable-next-line: no-unknown
    self.item[k] = v ~= vim.NIL and v or nil
  end
  for _, field in ipairs(fields or {}) do
    self.fields[field] = true
  end
  local item = self.item

  if not self.repo and item.web_url then
    self.repo = M.get_repo(item.web_url)
  end
  if self.repo and item.iid then
    self.uri = M.to_uri({ repo = self.repo, type = self.type, iid = item.iid })
    self.file = self.uri
  end

  self.author = item.author and item.author.username or nil
  self.hash = item.iid and ((self.type == "mr" and "!" or "#") .. tostring(item.iid)) or nil
  -- normalize GitLab "opened" to "open"
  self.state = item.state == "opened" and "open" or item.state
  self.status = self.state
  self.body = item.description and item.description:gsub("\r\n", "\n") or nil

  -- normalize labels to {name, color?}[]
  if item.labels then
    ---@param label string|snacks.glab.Label
    item.labels = vim.tbl_map(function(label)
      return type(label) == "string" and { name = label } or label
    end, item.labels)
    self.label = table.concat(
      ---@param label snacks.glab.Label
      vim.tbl_map(function(label)
        return label.name
      end, item.labels),
      ","
    )
  end

  -- normalize discussions: drop system notes, tag notes with discussion id and epoch
  if item.discussions then
    ---@param d snacks.glab.Discussion
    item.discussions = vim.tbl_filter(function(d)
      ---@param note snacks.glab.Note
      d.notes = vim.tbl_filter(function(note)
        return not note.system
      end, d.notes or {})
      for _, note in ipairs(d.notes) do
        note.discussion_id = d.id
        fix(note)
      end
      return #d.notes > 0
    end, item.discussions)
  end

  -- aggregate award emoji into {content, count} reactions
  if item.award_emoji then
    local counts = {} ---@type table<string, number>
    local order = {} ---@type string[]
    for _, award in ipairs(item.award_emoji) do
      if counts[award.name] == nil then
        order[#order + 1] = award.name
      end
      counts[award.name] = (counts[award.name] or 0) + 1
    end
    self.reactions = {}
    for _, name in ipairs(order) do
      self.reactions[#self.reactions + 1] = { content = name, count = counts[name] }
    end
  end

  if self.opts.transform then
    self.opts.transform(self)
  end
  self.text = Snacks.picker.util.text(self, self.opts.text or {})
end

---@param item snacks.glab.api.View
function M.to_uri(item)
  if item.uri then
    return item.uri
  end
  return ("glab://%s/%s/%s"):format(item.repo or "", assert(item.type), tostring(assert(item.iid)))
end

--- Parse `repo/type/iid` from a glab:// uri.
--- The repo may contain subgroups (`group/sub/project`), so parse from the end.
---@param uri string
---@return string? repo, string? type, number? iid
function M.from_uri(uri)
  local repo, type, iid = uri:match("^glab://(.+)/(issue)/(%d+)$")
  if not repo then
    repo, type, iid = uri:match("^glab://(.+)/(mr)/(%d+)$")
  end
  return repo, type, tonumber(iid)
end

--- Extract the full project path from a GitLab web url.
--- GitLab urls use `/-/` to separate the project path from the resource:
--- https://gitlab.com/group/sub/project/-/issues/42
---@param url string
function M.get_repo(url)
  local path = url:find("^http") and url:gsub("^https?://[^/]+/", "") or url
  local repo = path:match("^(.-)/%-/") --[[@as string?]]
  return repo or path:match("^([^/]+/[^/]+)")
end

return M
