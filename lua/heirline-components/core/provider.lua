--- ### Heirline providers.
--
-- DESCRIPTION:
-- The main functions we use to configure heirline.
--
-- Be aware only things assigned inside a the return function will be updated.

local M = {}

local condition = require("heirline-components.core.condition")
local env = require("heirline-components.core.env")
local core_utils = require("heirline-components.core.utils")

local utils = require("heirline-components.utils")
local extend_tbl = utils.extend_tbl
local get_icon = utils.get_icon
local is_available = utils.is_available


--- A provider function for the fill string.
---@return string # the statusline string for filling the empty space.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.fill }
function M.fill() return "%=" end

--- A provider function for the signcolumn string.
---@param opts? table options passed to the stylize function.
---@return string # the statuscolumn string for adding the signcolumn.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.signcolumn }
-- @see heirline-components.core.utils.stylize
function M.signcolumn(opts)
  opts = extend_tbl({ escape = false }, opts)
  return core_utils.stylize("%s", opts)
end

-- local function to resolve the first sign in the signcolumn
-- specifically for usage when `signcolumn=number`
local function resolve_sign(bufnr, lnum)
  local row = lnum - 1
  local extmarks = vim.api.nvim_buf_get_extmarks(
    bufnr, -1, { row, 0 }, { row, -1 }, { details = true, type = "sign" })
  local ret
  for _, extmark in pairs(extmarks) do
    local sign_def = extmark[4]
    if sign_def.sign_text and (
          not ret or (ret.priority < sign_def.priority)) then
      ret = sign_def
    end
  end
  if ret then return { text = ret.sign_text, texthl = ret.sign_hl_group } end
end

--- A provider function for the numbercolumn string
---@param opts? table options passed to the stylize function
---@return function # the statuscolumn string for adding the numbercolumn
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.numbercolumn }
-- @see heirline-components.core.utils.stylize
function M.numbercolumn(opts)
  opts = extend_tbl({ thousands = false, culright = true, escape = false }, opts)
  return function(self)
    local lnum, rnum, virtnum = vim.v.lnum, vim.v.relnum, vim.v.virtnum
    local num, relnum = vim.opt.number:get(), vim.opt.relativenumber:get()
    if not self.bufnr then self.bufnr = vim.api.nvim_get_current_buf() end
    local sign = vim.opt.signcolumn:get():find "nu" and resolve_sign(self.bufnr, lnum)
    local str
    if virtnum ~= 0 then
      str = "%="
    elseif sign then
      str = sign.text
      if sign.texthl then str = "%#" .. sign.texthl .. "#" .. str .. "%*" end
      str = "%=" .. str
    elseif not num and not relnum then
      str = "%="
    else
      local cur = relnum and (rnum > 0 and rnum or (num and lnum or 0)) or lnum
      if opts.thousands and cur > 999 then
        cur = cur
            :reverse()
            :gsub("%d%d%d", "%1" .. opts.thousands)
            :reverse()
            :gsub("^%" .. opts.thousands, "")
      end
      str = (rnum == 0 and not opts.culright and relnum) and cur .. "%=" or "%=" .. cur
    end
    return core_utils.stylize(str, opts)
  end
end

--- A provider function for building a foldcolumn.
---@param opts? table options passed to the stylize function.
---@return function # a custom foldcolumn function for
---                   the statuscolumn that doesn't show the nest levels.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.foldcolumn }
-- @see heirline-components.core.utils.stylize
function M.foldcolumn(opts)
  opts = extend_tbl({ escape = false }, opts)

  -- Nvim C Extensions
  local ffi = require "ffi"

  -- Custom C extension to get direct fold information from Neovim
  ffi.cdef [[
	  typedef struct {} Error;
	  typedef struct {} win_T;
	  typedef struct {
		  int start;  // line number where deepest fold starts.
		  int level;  // fold level, when zero other fields are N/A.
		  int llevel; // lowest level that starts in v:lnum.
		  int lines;  // number of lines from v:lnum to end of closed fold.
	  } foldinfo_T;
	  foldinfo_T fold_info(win_T* wp, int lnum);
	  win_T *find_window_by_handle(int Window, Error *err);
	  int compute_foldcolumn(win_T *wp, int col);
  ]]

  local fillchars = vim.opt.fillchars:get()
  local foldopen = fillchars.foldopen or get_icon("FoldOpened")
  local foldclosed = fillchars.foldclose or get_icon("FoldClosed")
  local foldsep = fillchars.foldsep or get_icon("FoldSeparator")

  return function()                                            -- move to M.fold_indicator
    local wp = ffi.C.find_window_by_handle(0, ffi.new "Error") -- get window handler
    local width = ffi.C.compute_foldcolumn(wp, 0)              -- get foldcolumn width

    -- get fold info of current line
    local foldinfo = width > 0 and ffi.C.fold_info(wp, vim.v.lnum)
        or { start = 0, level = 0, llevel = 0, lines = 0 }

    local str = ""
    if width ~= 0 then
      str = vim.v.relnum > 0 and "%#FoldColumn#" or "%#CursorLineFold#"
      if foldinfo.level == 0 then
        str = str .. (" "):rep(width)
      else
        local closed = foldinfo.lines > 0
        local first_level = foldinfo.level - width - (closed and 1 or 0) + 1
        if first_level < 1 then first_level = 1 end

        for col = 1, width do
          str = str
              .. (
                (vim.v.virtnum ~= 0 and foldsep)
                or ((closed and (col == foldinfo.level or col == width)) and foldclosed)
                or ((foldinfo.start == vim.v.lnum and first_level + col > foldinfo.llevel) and foldopen)
                or foldsep
              )
          if col == foldinfo.level then
            str = str .. (" "):rep(width - col)
            break
          end
        end
      end
    end
    return core_utils.stylize(str .. "%*", opts)
  end
end

--- A provider function for the current tab number.
---@return function # the statusline function to return a string for a tab number.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.tabnr() }
function M.tabnr()
  return function(self)
    return (self and self.tabnr)
        and "%" .. self.tabnr .. "T " .. self.tabnr .. " %T"
        or ""
  end
end

--- A provider function for showing if spellcheck is on.
---@param opts? table options passed to the stylize function.
---@return function # the function for outputting if spell is enabled.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.spell() }
-- @see heirline-components.core.utils.stylize
function M.spell(opts)
  opts = extend_tbl(
    { str = "", icon = { kind = "Spellcheck" }, show_empty = true },
    opts
  )
  return function()
    return core_utils.stylize(vim.wo.spell and opts.str or nil, opts)
  end
end

--- A proider function for showing if paste is enabled.
---@param opts? table options passed to the stylize function.
---@return function # the function for outputting if paste is enabled.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.paste() }
-- @see heirline-components.core.utils.stylize
function M.paste(opts)
  opts = extend_tbl(
    { str = "", icon = { kind = "Paste" }, show_empty = true },
    opts
  )
  local paste = vim.opt.paste
  if type(paste) ~= "boolean" then paste = paste:get() end
  return function()
    return core_utils.stylize(paste and opts.str or nil, opts)
  end
end

--- A provider function for displaying if a macro is currently being recorded.
---@param opts? table a prefix before the recording register
---                   and options passed to the stylize function.
---@return function # a function that returns
---                   a string of the current recording status.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.macro_recording() }
-- @see heirline-components.core.utils.stylize
function M.macro_recording(opts)
  opts = extend_tbl({ prefix = "@" }, opts)
  return function()
    local register = vim.fn.reg_recording()
    if register ~= "" then register = opts.prefix .. register end
    return core_utils.stylize(register, opts)
  end
end

--- A provider function for displaying the current command.
---@param opts? table of options passed to the stylize function.
---@return string # the statusline string for showing the current command.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.showcmd() }
-- @see heirline-components.core.utils.stylize
function M.showcmd(opts)
  opts = extend_tbl({ minwid = 0, maxwid = 5, escape = false }, opts)
  return core_utils.stylize(
    ("%%%d.%d(%%S%%)"):format(opts.minwid, opts.maxwid),
    opts
  )
end

--- A provider function for displaying the current search count.
---@param opts? table options for `vim.fn.searchcount`
---                   and options passed to the stylize function.
---@return function # a function that returns
---                   a string of the current search location.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.search_count() }
-- @see heirline-components.core.utils.stylize
function M.search_count(opts)
  local search_func = vim.tbl_isempty(opts or {})
      and function() return vim.fn.searchcount() end
      or function() return vim.fn.searchcount(opts) end
  return function()
    local search_ok, search = pcall(search_func)
    if search_ok and type(search) == "table" and search.total then
      return core_utils.stylize(
        string.format(
          "%s%d/%s%d",
          search.current > search.maxcount and ">" or "",
          math.min(search.current, search.maxcount),
          search.incomplete == 2 and ">" or "",
          math.min(search.total, search.maxcount)
        ),
        opts
      )
    end
  end
end

--- A provider function for showing the text of the current vim mode.
---@param opts? table options for padding the text
---                   and options passed to the stylize function.
---@return function # the function for displaying
---                   the text of the current vim mode.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.mode_text() }
-- @see heirline-components.core.utils.stylize
function M.mode_text(opts)
  local max_length = math.max(
    unpack(
      vim.tbl_map(function(str) return #str[1] end, vim.tbl_values(env.modes))
    )
  )
  return function()
    local text = env.modes[vim.fn.mode()][1]
    if opts and opts.pad_text then
      local padding = max_length - #text
      if opts.pad_text == "right" then
        text = string.rep(" ", padding) .. text
      elseif opts.pad_text == "left" then
        text = text .. string.rep(" ", padding)
      elseif opts.pad_text == "center" then
        text = string.rep(" ", math.floor(padding / 2))
            .. text
            .. string.rep(" ", math.ceil(padding / 2))
      end
    end
    return core_utils.stylize(text, opts)
  end
end

--- A provider function for showing the percentage of
--- the current location in a document.
---@param opts? table options for Top/Bot text, fixed width,
---                   and options passed to the stylize function.
---@return function # the statusline string for displaying the percentage of
---                   current document location.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.percentage() }
-- @see heirline-components.core.utils.stylize
function M.percentage(opts)
  opts =
      extend_tbl({ escape = false, fixed_width = true, edge_text = true }, opts)
  return function()
    local text = "%"
        .. (opts.fixed_width and (opts.edge_text and "2" or "3") or "")
        .. "p%%"
    if opts.edge_text then
      local current_line = vim.fn.line "."
      if current_line == 1 then
        text = "Top"
      elseif current_line == vim.fn.line "$" then
        text = "Bot"
      end
    end
    return core_utils.stylize(text, opts)
  end
end

--- A provider function for showing the current line and character in a document.
---@param opts? table options for padding the line and character locations
---                   and options passed to the stylize function.
---@return function # the statusline string for showing location in document line_num:char_num.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.ruler({ pad_ruler = { line = 3, char = 2 } }) }
-- @see heirline-components.core.utils.stylize
function M.ruler(opts)
  opts = extend_tbl({ pad_ruler = { line = 3, char = 2 } }, opts)
  local padding_str =
      string.format("%%%dd:%%-%dd", opts.pad_ruler.line, opts.pad_ruler.char)
  return function()
    local line = vim.fn.line "."
    local char = vim.fn.virtcol "."
    return core_utils.stylize(string.format(padding_str, line, char), opts)
  end
end

--- A provider function for showing the current location as a scrollbar.
---@param opts? table options passed to the stylize function.
---@return function # the function for outputting the scrollbar.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.scrollbar() }
-- @see heirline-components.core.utils.stylize
function M.scrollbar(opts)
  local sbar = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
  return function()
    local curr_line = vim.api.nvim_win_get_cursor(0)[1]
    local lines = vim.api.nvim_buf_line_count(0)
    local i = math.floor((curr_line - 1) / lines * #sbar) + 1
    if sbar[i] then
      return core_utils.stylize(string.rep(sbar[i], 2), opts)
    end
  end
end

--- A provider to simply show a close button icon.
---@param opts? table options passed to the stylize function
---                   and the kind of icon to use.
---@return string # the stylized icon.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.close_button() }
-- @see heirline-components.core.utils.stylize
function M.close_button(opts)
  opts = extend_tbl({ kind = "BufferClose" }, opts)
  return core_utils.stylize(get_icon(opts.kind), opts)
end

--- A provider function for showing the current filetype.
---@param opts? table options passed to the stylize function.
---@return function  # the function for outputting the filetype.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.filetype() }
-- @see heirline-components.core.utils.stylize
function M.filetype(opts)
  return function(self)
    local buffer = vim.bo[self and self.bufnr or 0]
    return core_utils.stylize(string.lower(buffer.filetype), opts)
  end
end

--- A provider function for showing the current filename.
---@param opts? table options for argument to fnamemodify to format filename
---                   and options passed to the stylize function.
---@return function # the function for outputting the filename.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.filename() }
-- @see heirline-components.core.utils.stylize
function M.filename(opts)
  opts = extend_tbl({
    fallback = "[No Name]",
    fname = function(nr) return vim.api.nvim_buf_get_name(nr) end,
    modify = ":t",
  }, opts)
  return function(self)
    local path = opts.fname(self and self.bufnr or 0)
    local filename = vim.fn.fnamemodify(path, opts.modify)
    return core_utils.stylize((path == "" and opts.fallback or filename), opts)
  end
end

--- A provider function for showing the current file encoding.
---@param opts? table options passed to the stylize function.
---@return function  # the function for outputting the file encoding.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.file_encoding() }
-- @see heirline-components.core.utils.stylize
function M.file_encoding(opts)
  return function(self)
    local buf_enc = vim.bo[self and self.bufnr or 0].fenc
    return core_utils.stylize(
      string.upper(buf_enc ~= "" and buf_enc or vim.o.enc),
      opts
    )
  end
end

--- A provider function for showing the current file format.
---@param opts? table options passed to the stylize function.
---@return function  # the function for outputting the file format.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.file_format() }
-- @see heirline-components.core.utils.stylize
function M.file_format(opts)
  return function(self)
    local buf_format = vim.bo[self and self.bufnr or 0].fileformat
    return core_utils.stylize(
      string.upper(buf_format ~= "" and buf_format or vim.o.fileformat),
      opts
    )
  end
end

--- Get a unique filepath between all buffers.
---@param opts? table options for function to get the buffer name,
---                   a buffer number, max length, and options passed
---                   to the stylize function.
---@return function # path to file that uniquely identifies each buffer.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.unique_path() }
-- @see heirline-components.core.utils.stylize
function M.unique_path(opts)
  opts = extend_tbl({
    buf_name = function(bufnr)
      if vim.api.nvim_buf_is_valid(bufnr) then
        return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")
      else
        return ""
      end
    end,
    bufnr = 0,
    max_length = 16,
  }, opts)
  local function path_parts(bufnr)
    local parts = {}
    for match in
    (vim.api.nvim_buf_get_name(bufnr) .. "/"):gmatch("(.-)" .. "/")
    do
      table.insert(parts, match)
    end
    return parts
  end
  return function(self)
    opts.bufnr = self and self.bufnr or opts.bufnr
    local name = opts.buf_name(opts.bufnr)
    local unique_path = ""
    -- check for same buffer names under different dirs
    local current
    for _, value in ipairs(vim.t.bufs or {}) do
      if name == opts.buf_name(value) and value ~= opts.bufnr then
        if not current then current = path_parts(opts.bufnr) end
        local other = path_parts(value)

        for i = #current - 1, 1, -1 do
          if current[i] ~= other[i] then
            unique_path = current[i] .. "/"
            break
          end
        end
      end
    end
    return core_utils.stylize(
      (
        opts.max_length > 0
        and #unique_path > opts.max_length
        and string.sub(unique_path, 1, opts.max_length - 2)
        .. get_icon("Ellipsis")
        .. "/"
      ) or unique_path,
      opts
    )
  end
end

--- A provider function for showing if the current file is modifiable.
---@param opts? table options passed to the stylize function.
---@return function # the function for outputting the indicator
---                   if the file is modified.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.file_modified() }
-- @see heirline-components.core.utils.stylize
function M.file_modified(opts)
  opts = extend_tbl(
    { str = "", icon = { kind = "FileModified" }, show_empty = true },
    opts
  )
  return function(self)
    return core_utils.stylize(
      condition.file_modified((self or {}).bufnr) and opts.str or nil,
      opts
    )
  end
end

--- A provider function for showing if the current file is read-only.
---@param opts? table options passed to the stylize function.
---@return function # the function for outputting the indicator if the file is read-only.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.file_read_only() }
-- @see heirline-components.core.utils.stylize
function M.file_read_only(opts)
  opts = extend_tbl(
    { str = "", icon = { kind = "FileReadOnly" }, show_empty = true },
    opts
  )
  return function(self)
    return core_utils.stylize(
      condition.file_read_only((self or {}).bufnr) and opts.str or nil,
      opts
    )
  end
end

--- A provider function for showing the current filetype icon.
---@param opts? table options passed to the stylize function.
---@return function # the function for outputting the filetype icon.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.file_icon() }
-- @see heirline-components.core.utils.stylize
function M.file_icon(opts)
  return function(self)
    return core_utils.stylize(
      core_utils.icon_provider(self and self.bufnr or 0), opts
    )
  end
end

--- A provider function for showing the current git branch.
---@param opts table options passed to the stylize function.
---@return function # the function for outputting the git branch.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.git_branch() }
-- @see heirline-components.core.utils.stylize
function M.git_branch(opts)
  return function(self)
    return core_utils.stylize(
      vim.b[self and self.bufnr or 0].gitsigns_head or "",
      opts
    )
  end
end

--- A provider function for showing the current git diff count of a specific type.
---@param opts? table options for type of git diff and options passed to the stylize function.
---@return function|nil # the function for outputting the git diff.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.git_diff({ type = "added" }) }
-- @see heirline-components.core.utils.stylize
function M.git_diff(opts)
  if not opts or not opts.type then return end -- guard clause

  local minidiff_types = { added = "add", changed = "change", removed = "delete" }

  return function(self)
    local bufnr, total = self and self.bufnr or 0, nil
    local gitsigns = vim.b[bufnr].gitsigns_status_dict
    local minidiff = vim.b[bufnr].minidiff_summary

    if gitsigns then -- gitsigns support
      total = gitsigns[opts.type]
    elseif minidiff then -- mini.diff support
      total = minidiff[minidiff_types[opts.type]]
    end

    return core_utils.stylize(total and total > 0 and tostring(total) or "", opts)
  end
end

--- A provider function for
--- showing the current diagnostic count of a specific severity.
---@param opts table options for severity of diagnostic and options passed
---                  to the stylize function.
---@return function|nil # the function for outputting the diagnostic count.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.diagnostics({ severity = "ERROR" }) }
-- @see heirline-components.core.utils.stylize
function M.diagnostics(opts)
  if not opts or not opts.severity then return end
  return function(self)
    local bufnr = self and self.bufnr or 0
    local count = vim.diagnostic.count(bufnr)[vim.diagnostic.severity[opts.severity]] or 0
    return core_utils.stylize(count ~= 0 and tostring(count) or "", opts)
  end
end

--- A provider function for showing the current progress of loading language servers.
---@param opts? table options passed to the stylize function.
---@return function # the function for outputting the LSP progress.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.lsp_progress() }
-- @see heirline-components.core.utils.stylize
function M.lsp_progress(opts)
  local lsp = opts.init
  local spinner = utils.get_spinner("LSPLoading", 1) or { "" }
  return function()
    local _, Lsp = next(lsp.progress)
    return core_utils.stylize(
      Lsp
      and (
        spinner[math.floor(vim.uv.hrtime() / 12e7) % #spinner + 1]
        .. table.concat({
          Lsp.title or "",
          Lsp.message or "",
          Lsp.percentage and "(" .. Lsp.percentage .. "%)" or "",
        }, " ")
      ),
      opts
    )
  end
end

--- A provider function for showing the connected LSP client names
---@param opts? table options for explanding null_ls clients, max width percentage, and options passed to the stylize function.
---@return function # the function for outputting the LSP client names
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.lsp_client_names({ integrations = { null_ls = true, conform = true, lint = true }, truncate = 0.25 }) }
-- @see heirline-components.core.utils.stylize
function M.lsp_client_names(opts)
  opts = extend_tbl({
      integrations = {
        null_ls = is_available("none-ls.nvim"),
        conform = is_available("conform.nvim"),
        ["nvim-lint"] = is_available("nvim-lint"),
      },
      truncate = 0.25,
    },
    opts
  )
  return function(self)
    local str
    local bufnr = self and self.bufnr or 0
    local buf_client_names = {}

    -- none-ls integration
    for _, client in pairs(vim.lsp.get_clients({ bufnr = bufnr })) do
      if client.name == "null-ls" and opts.integrations.null_ls then
        local null_ls_sources = {}
        local ft = vim.bo[bufnr].filetype
        local params =
          { client_id = client.id, bufname = vim.api.nvim_buf_get_name(bufnr), bufnr = bufnr, filetype = ft, ft = ft }
        for _, type in ipairs { "FORMATTING", "DIAGNOSTICS" } do
          params.method = type
          for _, source in ipairs(core_utils.null_ls_sources(params)) do
            null_ls_sources[source] = true
          end
        end
        vim.list_extend(buf_client_names, vim.tbl_keys(null_ls_sources))
      else
        table.insert(buf_client_names, client.name)
      end
    end

    -- conform integration
    if opts.integrations.conform and package.loaded["conform"] then
      vim.list_extend(buf_client_names, vim.tbl_map(
        function(c) return c.name end,
        require("conform").list_formatters_to_run(bufnr))
      )
    end

    -- nvim-lint integration
    if opts.integrations["nvim-lint"] and package.loaded["lint"] then
      vim.list_extend(buf_client_names, require("lint")._resolve_linter_by_ft(vim.bo[bufnr].filetype))
    end

    -- filter duplicate names
    local filter_duplicates = false
    if filter_duplicates then
      local buf_client_names_set, client_name_lookup = {}, {}
      for _, client in ipairs(buf_client_names) do
        if not client_name_lookup[client] then
          client_name_lookup[client] = true
          table.insert(buf_client_names_set, client)
        end
      end
      str = table.concat(buf_client_names_set, ", ")
    else
      str = table.concat(buf_client_names, ", ")
    end

    -- truncate
    if type(opts.truncate) == "number" then
      local max_width = math.floor(core_utils.width() * opts.truncate)
      if #str > max_width then str = string.sub(str, 0, max_width) .. "…" end
    end

    return core_utils.stylize(str, opts)
  end
end

--- A provider function for showing the current virtual environment name
---@param opts table options passed to the stylize function
---@return function # the function for outputting the virtual environment
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.virtual_env() }
-- @see heirline-components.core.utils.stylize
function M.virtual_env(opts)
  opts = extend_tbl(
    {
      env_names = { "env", ".env", "venv", ".venv" },
      conda = { enabled = true, ignore_base = true },
    },
    opts
  )
  return function()
    local conda = vim.env.CONDA_DEFAULT_ENV
    local venv = vim.env.VIRTUAL_ENV
    local env_str
    if venv then
      local path = vim.fn.split(venv, "/")
      env_str = path[#path]
      if #path > 1 and vim.tbl_contains(opts.env_names, env_str) then
        env_str = path[#path - 1]
      end
    elseif opts.conda.enabled and conda then
      if conda ~= "base" or not opts.conda.ignore_base then env_str = conda end
    end
    if env_str then
      return core_utils.stylize(
        opts.format and opts.format:format(env_str) or env_str,
        opts
      )
    end
  end
end

--- A provider function for showing if treesitter is connected.
---@param opts? table options passed to the stylize function.
---@return function # function for outputting TS if treesitter is connected.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.treesitter_status() }
-- @see heirline-components.core.utils.stylize
function M.treesitter_status(opts)
  return function()
    return core_utils.stylize(
      require("nvim-treesitter.parser").has_parser() and "TS" or "",
      opts
    )
  end
end

--- A provider function for displaying a single string.
---@param opts? table options passed to the stylize function.
---@return string # the stylized statusline string.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.str({ str = "Hello" }) }
-- @see heirline-components.core.utils.stylize
function M.str(opts)
  opts = extend_tbl({ str = " " }, opts)
  return core_utils.stylize(opts.str, opts)
end

--- A provider function for displaying the compiler state.
--- Be aware using this provider, will auto load the plugin compiler.nvim into memory.
---@return function # the state of the compiler.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.compiler_state() }
-- @see heirline-components.core.utils.stylize
function M.compiler_state(opts)
  local ovs
  local state
  local tasks
  local tasks_by_status
  local spinner = utils.get_spinner("LSPLoading", 1) or { "" }

  return function()
    if is_available "compiler.nvim"
        or is_available("overseer.nvim")
        and not ovs then
      vim.defer_fn(function()
        ovs = require("overseer")
      end, 100) -- Hotfix: Defer to avoid stack trace on new files.
    end
    if not ovs then return nil end

    tasks = ovs.list_tasks({ unique = false })
    tasks_by_status = ovs.util.tbl_group_by(tasks, "status")

    if tasks_by_status["RUNNING"] then
      state = "compiling"
    else
      state = ""
    end

    -- calculate string to return
    local str
    if tasks_by_status["RUNNING"] then
      str = (table.concat({
        "",
        spinner[math.floor(vim.uv.hrtime() / 12e7) % #spinner + 1] or "",
        state,
      }, ""))
    else
      str = get_icon("ToggleResults")
    end

    return core_utils.stylize(str, opts)
  end
end

--- A provider function for displaying the compiler play button.
---@return string # the play button.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.compiler_play() }
-- @see heirline-components.core.utils.stylize
function M.compiler_play(opts)
  return core_utils.stylize(table.concat({ get_icon("CompilerPlay") }, ""), opts)
end

--- A provider function for displaying the compiler stop button.
---@return string # the stop button.
-- @usage local heirline_component = { provier = require("heirline-components.core").provider.compiler_stop() }
-- @see heirline-components.core.utils.stylize
function M.compiler_stop(opts)
  return core_utils.stylize(table.concat({ get_icon("CompilerStop") }, ""), opts)
end

--- A provider function for displaying the compiler redo button.
---@return string # the redo button.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.compiler_redo() }
-- @see heirline-components.core.utils.stylize
function M.compiler_redo(opts)
  return core_utils.stylize(table.concat({ get_icon("CompilerRedo") }, ""), opts)
end

--- A provider function for displaying the compiler redo button.
---@return string # the redo button.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.neotree() }
-- @see heirline-components.core.utils.stylize
function M.neotree(opts)
  return core_utils.stylize(table.concat({ get_icon("NeoTree") }, ""), opts)
end

--- A provider function for displaying the compiler redo button.
---@return string # the redo button.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.aerial() }
-- @see heirline-components.core.utils.stylize
function M.aerial(opts)
  return core_utils.stylize(table.concat({ get_icon("Aerial") }, ""), opts)
end

--- A provider function for displaying the zen_mode button.
---@return string # the zen_mode button.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.zen-mode() }
-- @see heirline-components.core.utils.stylize
function M.zen_mode(opts)
  return core_utils.stylize(table.concat({ get_icon("ZenMode") }, ""), opts)
end

--- A provider function for displaying the write buffer button.
---@return string # the write buffer button.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.write_buffer() }
-- @see heirline-components.core.utils.stylize
function M.write_buffer(opts)
  return core_utils.stylize(table.concat({ get_icon("BufWrite") }, ""), opts)
end

--- A provider function for displaying the write all buffers button.
---@return string # the write all buffers button.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.write_all_buffers() }
-- @see heirline-components.core.utils.stylize
function M.write_all_buffers(opts)
  return core_utils.stylize(table.concat({ get_icon("BufWriteAll") }, ""), opts)
end

--- A provider function for displaying the compiler build type.
---@return function # the build type label.
-- @usage local heirline_component = { provider = require("heirline-components.core").provider.compiler_build_type() }
-- @see heirline-components.core.utils.stylize
function M.compiler_build_type(opts)
  return function()
    local build_type = ""
    if vim.bo.filetype == "c" then
      build_type = vim.g.CMAKE_BUILD_TYPE
    elseif vim.g.heirline_components_build_type == "java" then
      build_type = vim.g.GRADLE_BUILD_TYPE
    end

    return core_utils.stylize(table.concat({ build_type }, ""), opts)
  end
end

return M
