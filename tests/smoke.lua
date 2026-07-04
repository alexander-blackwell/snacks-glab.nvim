-- Headless smoke test for snacks-glab.nvim
-- Run with: nvim --headless --clean -c "luafile tests/smoke.lua"
-- Requires snacks.nvim at ~/.local/share/nvim/lazy/snacks.nvim (or $SNACKS_DIR)

local root = vim.fn.fnamemodify(vim.fn.expand("<script>"):gsub("/tests/smoke%.lua$", ""), ":p"):gsub("/$", "")
if root == "" or not vim.uv.fs_stat(root .. "/lua/snacks/glab") then
  root = vim.fn.getcwd()
end
local snacks_dir = vim.env.SNACKS_DIR or (vim.fn.expand("~") .. "/.local/share/nvim/lazy/snacks.nvim")

vim.opt.rtp:prepend(snacks_dir)
vim.opt.rtp:prepend(root)

local failed, passed = {}, 0
local function check(name, ok, extra)
  if ok then
    passed = passed + 1
    print(("ok   - %s"):format(name))
  else
    failed[#failed + 1] = name
    print(("FAIL - %s%s"):format(name, extra and (": " .. tostring(extra)) or ""))
  end
end

---@param fn fun(): boolean?, any?
local function try(name, fn)
  local ok, res, extra = pcall(fn)
  if not ok then
    check(name, false, res)
  else
    check(name, res ~= false, extra)
  end
end

-- 1. setup snacks with the mock glab binary
local mock = root .. "/tests/mock/glab"
require("snacks").setup({
  picker = { enabled = true },
  glab = { cmd = mock },
})
require("snacks.picker.config").setup()

-- 2. plugin bootstrap registers sources
dofile(root .. "/plugin/snacks-glab.lua")

try("modules load", function()
  for _, mod in ipairs({ "snacks.glab", "snacks.glab.item", "snacks.glab.api", "snacks.glab.actions",
    "snacks.glab.buf", "snacks.glab.render", "snacks.picker.source.glab" }) do
    require(mod)
  end
  return true
end)

try("config uses mock binary", function()
  return require("snacks.glab").config().cmd == mock
end)

try("picker sources registered", function()
  local sources = require("snacks.picker.config.sources")
  for _, s in ipairs({ "glab_issue", "glab_mr", "glab_diff", "glab_reactions", "glab_labels", "glab_actions" }) do
    assert(sources[s], "missing source: " .. s)
  end
  return type(Snacks.picker.glab_issue) == "function" and type(Snacks.picker.glab_mr) == "function"
end)

-- 3. timestamp parsing
try("timestamp parsing", function()
  local Item = require("snacks.glab.item")
  local base = Item.ts("2026-06-01T10:30:45Z")
  assert(base, "plain Z timestamp")
  assert(Item.ts("2026-06-01T10:30:45.123Z") == base, "fractional seconds")
  local offset = Item.ts("2026-06-01T12:30:45+02:00")
  assert(offset == base, ("offset +02:00 (%s vs %s)"):format(offset, base))
  assert(Item.ts("garbage") == nil, "invalid input")
  return true
end)

-- 4. repo extraction from web urls (incl. subgroups)
try("get_repo handles subgroups", function()
  local Item = require("snacks.glab.item")
  assert(Item.get_repo("https://gitlab.example.com/group/sub/proj/-/issues/42") == "group/sub/proj")
  assert(Item.get_repo("https://gitlab.com/owner/repo/-/merge_requests/1") == "owner/repo")
  return true
end)

try("uri round-trip with subgroups", function()
  local Item = require("snacks.glab.item")
  local uri = Item.to_uri({ repo = "group/sub/proj", type = "issue", iid = 42 })
  assert(uri == "glab://group/sub/proj/issue/42", uri)
  local repo, type, iid = Item.from_uri(uri)
  return repo == "group/sub/proj" and type == "issue" and iid == 42
end)

-- 5. list finder against the mock
local Api = require("snacks.glab.api")

local function wait_for(pred, ms)
  return vim.wait(ms or 5000, pred, 10)
end

try("issue list via mock glab", function()
  local items
  Api.list("issue", function(res)
    items = res or {}
  end, {})
  assert(wait_for(function()
    return items ~= nil
  end), "timeout")
  assert(#items == 1, "expected 1 issue, got " .. #items)
  local it = items[1]
  assert(it.iid == 42, "iid")
  assert(it.hash == "#42", "hash: " .. tostring(it.hash))
  assert(it.state == "open", "state normalized: " .. tostring(it.state))
  assert(it.status == "open", "status")
  assert(it.repo == "group/sub/proj", "repo from web_url: " .. tostring(it.repo))
  assert(it.uri == "glab://group/sub/proj/issue/42", "uri")
  assert(it.author == "jdoe", "author")
  assert(it.label == "bug,frontend", "labels: " .. tostring(it.label))
  assert(it.body and not it.body:find("\r"), "body normalized")
  assert(it.created and it.updated, "timestamps")
  return true
end)

try("mr list via mock glab", function()
  local items
  Api.list("mr", function(res)
    items = res or {}
  end, {})
  assert(wait_for(function()
    return items ~= nil
  end), "timeout")
  local it = items[1]
  assert(it.hash == "!7", "hash: " .. tostring(it.hash))
  assert(it.status == "draft", "draft status: " .. tostring(it.status))
  assert(it.item.source_branch == "feat/rate-limit", "source branch")
  return true
end)

-- items held here so the weak api cache can't drop them mid-test
local issue_item, mr_item
-- 6. full view fetch (detail + discussions + awards)
try("issue view fetches discussions and awards", function()
  local item
  Api.view(function(it)
    item = it
  end, { repo = "group/sub/proj", type = "issue", iid = 42 })
  assert(wait_for(function()
    return item ~= nil
  end), "timeout")
  assert(#item.item.discussions == 2, "system-only discussions filtered: " .. #item.item.discussions)
  assert(item.item.discussions[2].notes[1].discussion_id == "disc2", "discussion id tagged")
  assert(item.reactions, "reactions aggregated")
  local thumbs
  for _, r in ipairs(item.reactions) do
    if r.content == "thumbsup" then
      thumbs = r.count
    end
  end
  assert(thumbs == 2, "thumbsup count: " .. tostring(thumbs))
  assert(item.fields.detail and item.fields.discussions and item.fields.awards, "fields tracked")
  issue_item = item
  return true
end)

try("mr view fetches approvals and pipeline", function()
  local item
  Api.view(function(it)
    item = it
  end, { repo = "group/sub/proj", type = "mr", iid = 7 })
  assert(wait_for(function()
    return item ~= nil
  end), "timeout")
  assert(item.item.approved_by and item.item.approved_by[1].username == "asmith", "approvals")
  assert(item.item.head_pipeline and item.item.head_pipeline.status == "running", "pipeline")
  assert(item.item.diff_refs and item.item.diff_refs.base_sha == "base111", "diff refs")
  mr_item = item
  return true
end)

-- 7. glab:// buffer end-to-end render
try("glab:// buffer renders", function()
  require("snacks.glab").setup()
  vim.cmd.edit("glab://group/sub/proj/issue/42")
  local buf = vim.api.nvim_get_current_buf()
  assert(wait_for(function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    return #lines > 5 and table.concat(lines, "\n"):find("Safari", 1, true) ~= nil
  end), "timeout waiting for render")
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  assert(text:find("Login button unresponsive", 1, true), "title rendered")
  assert(text:find("Reproduced on Safari 17.", 1, true), "comment rendered")
  assert(text:find("Thanks!", 1, true), "reply rendered")
  assert(not text:find("changed the description", 1, true), "system note filtered")
  assert(text:find("Author:", 1, true), "props rendered")
  local b = vim.b[buf].snacks_glab
  assert(b and b.repo == "group/sub/proj" and b.iid == 42, "buffer marker")
  assert(vim.bo[buf].filetype == "markdown.glab", "filetype")
  -- reply metadata attached to comment lines
  local meta = Snacks.picker.highlight.meta(buf)
  local found
  for _, m in pairs(meta or {}) do
    if m.discussion_id == "disc2" then
      found = true
    end
  end
  assert(found, "line meta with discussion_id")
  return true
end)

-- 8. actions
try("issue actions enabled correctly", function()
  local Actions = require("snacks.glab.actions")
  local item = assert(issue_item, "issue item from view test")
  assert(Api.get_cached({ repo = "group/sub/proj", type = "issue", iid = 42 }) == item, "cache hit")
  local actions = Actions.get_actions(item, { items = { item } })
  assert(actions.glab_close, "close enabled for open issue")
  assert(not actions.glab_reopen, "reopen disabled for open issue")
  assert(not actions.glab_merge, "merge not offered for issues")
  assert(not actions.glab_diff, "diff not offered for issues")
  assert(actions.glab_comment and actions.glab_react and actions.glab_label and actions.glab_yank, "common actions")
  assert(actions.glab_close.desc == "Close issue #42", "tpl desc: " .. tostring(actions.glab_close.desc))
  return true
end)

try("mr actions enabled correctly", function()
  local Actions = require("snacks.glab.actions")
  local item = assert(mr_item, "mr item from view test")
  local actions = Actions.get_actions(item, { items = { item } })
  assert(actions.glab_ready, "ready enabled for draft MR")
  assert(not actions.glab_draft, "draft disabled for draft MR")
  assert(not actions.glab_merge, "merge disabled for draft MR")
  assert(actions.glab_checkout and actions.glab_approve and actions.glab_diff and actions.glab_rebase, "mr actions")
  assert(actions.glab_revoke, "revoke enabled when approved")
  assert(actions.glab_ready.desc == "Mark MR !7 as ready for review", tostring(actions.glab_ready.desc))
  return true
end)

-- 9. diff annotations from positioned discussions
try("mr diff annotations", function()
  local Render = require("snacks.glab.render")
  local item = assert(mr_item, "mr item from view test")
  local annotations = Render.annotations(item)
  assert(#annotations == 1, "one annotation, got " .. #annotations)
  local a = annotations[1]
  assert(a.file == "src/limiter.lua" and a.line == 2 and a.side == "right", vim.inspect(a))
  assert(#a.text > 0, "annotation text rendered")
  return true
end)

-- 10. icon consistency: every palette action carries a real glyph
try("all palette actions have icons", function()
  local Actions = require("snacks.glab.actions")
  local skip = { glab_actions = true, glab_perform_action = true }
  for _, it in ipairs({ issue_item, mr_item }) do
    local actions = Actions.get_actions(it, { items = { it } })
    for name, action in pairs(actions) do
      if not skip[name] then
        local icon = action.icon
        assert(type(icon) == "string" and icon:gsub("%s", "") ~= "", "blank icon for " .. name)
      end
    end
  end
  return true
end)

try("no blank icons in config", function()
  local icons = require("snacks.glab").config().icons
  local function walk(tbl, path)
    for k, v in pairs(tbl) do
      local p = path .. "." .. k
      if type(v) == "table" then
        walk(v, p)
      else
        assert(type(v) == "string" and v:gsub("%s", "") ~= "", "blank icon at " .. p)
      end
    end
  end
  walk(icons, "icons")
  return true
end)

print(("\n%d passed, %d failed"):format(passed, #failed))
if #failed > 0 then
  print("failed: " .. table.concat(failed, ", "))
  vim.cmd.cquit()
else
  vim.cmd.quitall()
end
