---@meta

--- GitLab data shapes as returned by the GitLab REST API v4
--- (via `glab ... list --output json` and `glab api`).

---@class snacks.glab.api.Config
---@field type "issue" | "mr"
---@field repo? string
---@field fields string[] pseudo-fields fetched so far (list, detail, discussions, awards, approvals)
---@field text string[] item properties used for fuzzy matching
---@field options string[] list options mapped to CLI flags
---@field transform? fun(item: snacks.picker.glab.Item): snacks.picker.glab.Item?

---@class snacks.picker.glab.list.Config: snacks.picker.glab.Config
---@field type "issue" | "mr"

---@alias snacks.glab.api.View snacks.picker.glab.Item|{iid: number, type: string, repo: string}

---@class snacks.glab.api.Cmd
---@field args string[]
---@field repo? string
---@field input? string
---@field notify? boolean
---@field on_error? fun(proc: snacks.spawn.Proc, err: string)

---@class snacks.glab.api.Api
---@field endpoint string may contain `{project}` (url-encoded repo) and `{iid}` placeholders
---@field fields? table<string, string|number|boolean> raw fields (--raw-field)
---@field params? table<string, string|number|boolean> typed fields (--field)
---@field header? table<string, string|number|boolean>
---@field input? any JSON request body (--input -)
---@field method? "GET" | "POST" | "PATCH" | "PUT" | "DELETE"
---@field paginate? boolean
---@field silent? boolean
---@field repo? string project path used to expand `{project}`
---@field iid? number|string used to expand `{iid}`
---@field on_error? fun(proc: snacks.spawn.Proc, err: string)

---@alias snacks.glab.Field {arg:string, prop:string, name:string}

---@class snacks.glab.cli.Action: snacks.glab.api.Cmd
---@field args? string[]
---@field edit? string field to edit in a scratch buffer. cli: `--<edit> <body>`, api: `input[<edit>] = body`
---@field api? snacks.glab.api.Api api options (used instead of a subcommand)
---@field cmd? string subcommand to run (e.g., "close" -> `glab issue close`)
---@field fields? snacks.glab.Field[] frontmatter fields to parse from the body
---@field title? string title of the scratch buffer
---@field template? string template for the scratch buffer
---@field desc? string description
---@field icon? string icon for the action
---@field type? snacks.glab.Kind|snacks.glab.Kind[] item kinds this action applies to (nil means issues and MRs)
---@field enabled? fun(item: snacks.picker.glab.Item, ctx: snacks.glab.action.ctx): boolean
---@field success? string success message shown after the action
---@field confirm? string confirmation message shown before performing the action
---@field refresh? boolean refresh the item after performing the action (default: true)
---@field on_submit? fun(body: string, ctx: snacks.glab.cli.Action.ctx): string?

---@class snacks.glab.User
---@field id number
---@field username string
---@field name string
---@field state? string

---@class snacks.glab.Milestone
---@field id number
---@field title string

--- A single award emoji (one per user per emoji)
---@class snacks.glab.Award
---@field id number
---@field name string emoji name, e.g. "thumbsup"
---@field user snacks.glab.User

---@class snacks.glab.Label
---@field name string
---@field color? string hex color, e.g. "#ff0000" (only known from the labels API)
---@field description? string

---@alias snacks.glab.Kind "issue" | "mr" | "pipeline" | "job"

--- CI job as returned by the REST API
---@class snacks.glab.Job
---@field id number
---@field name string
---@field stage string
---@field status string
---@field allow_failure? boolean
---@field duration? number seconds
---@field created_at string
---@field web_url? string
---@field pipeline? snacks.glab.Pipeline

---@class snacks.glab.Pipeline
---@field id number
---@field status string created|waiting_for_resource|preparing|pending|running|success|failed|canceled|skipped|manual|scheduled
---@field web_url? string
---@field sha? string

---@class snacks.glab.Position
---@field position_type "text" | "image" | "file"
---@field base_sha string
---@field start_sha string
---@field head_sha string
---@field new_path? string
---@field old_path? string
---@field new_line? number
---@field old_line? number

--- A note (comment). System notes are filtered out.
---@class snacks.glab.Note
---@field id number
---@field body string
---@field author snacks.glab.User
---@field created_at string
---@field updated_at? string
---@field system boolean
---@field resolvable? boolean
---@field resolved? boolean
---@field position? snacks.glab.Position
---@field created? number epoch, added client-side
---@field discussion_id? string added client-side from the parent discussion

--- A discussion (thread of notes)
---@class snacks.glab.Discussion
---@field id string
---@field individual_note boolean
---@field notes snacks.glab.Note[]

---@class snacks.glab.DiffRefs
---@field base_sha string
---@field head_sha string
---@field start_sha string

--- Issue/MR as returned by the REST API
---@class snacks.glab.Item
---@field id number global id
---@field iid number project-scoped id
---@field title string
---@field description? string
---@field state string opened|closed|merged|locked
---@field labels? (string|snacks.glab.Label)[]
---@field author? snacks.glab.User
---@field assignees? snacks.glab.User[]
---@field milestone? snacks.glab.Milestone
---@field created_at string
---@field updated_at string
---@field closed_at? string
---@field merged_at? string
---@field web_url string
---@field references? {short: string, relative: string, full: string}
---@field user_notes_count? number
--- MR specific:
---@field source_branch? string
---@field target_branch? string
---@field draft? boolean
---@field merge_status? string deprecated, use detailed_merge_status
---@field detailed_merge_status? string
---@field has_conflicts? boolean
---@field sha? string HEAD sha of the source branch
---@field diff_refs? snacks.glab.DiffRefs
---@field head_pipeline? snacks.glab.Pipeline
---@field pipeline? snacks.glab.Pipeline deprecated head pipeline
---@field changes_count? string|number
--- added client-side:
---@field discussions? snacks.glab.Discussion[]
---@field award_emoji? snacks.glab.Award[]
---@field approved_by? snacks.glab.User[]

--- Normalized picker item wrapping a snacks.glab.Item
---@class snacks.picker.glab.Item: snacks.picker.Item,snacks.glab.Item
---@field type "issue" | "mr"
---@field dirty? boolean
---@field uri string glab://{repo}/{type}/{iid}
---@field repo? string project path with namespace (may contain subgroups)
---@field hash string "!{iid}" for MRs, "#{iid}" for issues
---@field status string open|closed|merged|draft
---@field author? string author username
---@field label? string comma-separated label names (for matching)
---@field item snacks.glab.Item
---@field body? string normalized description
---@field reactions? {content: string, count: number}[]
---@field fields table<string, boolean>
---@field created number
---@field updated number
---@field closed? number
---@field merged? number
