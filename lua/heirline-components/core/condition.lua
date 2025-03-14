--- ### Heirline conditions.
--
-- DESCRIPTION:
-- When a condition is used on a component,
-- the component will only enabled when the condition returns true.

local M = {}

local env = require("heirline-components.core.env")

--- A condition function if the window is currently active.
---@return boolean # whether or not the window is currently actie.
-- @usage local heirline_component = { provider = "Example Provider", condition = require("heirline-components.core").condition.is_active }
function M.is_active()
  return vim.api.nvim_get_current_win() == tonumber(vim.g.actual_curwin)
end

--- A condition function if the buffer filetype,buftype,bufname match a pattern.
---@param patterns table the table of patterns to match.
---@param bufnr number of the buffer to match (Default: 0 [current]).
---@return boolean # whether or not LSP is attached.
-- @usage local heirline_component = { provider = "Example Provider", condition = function() return require("heirline-components.core").condition.buffer_matches { buftype = { "terminal" } } end }
function M.buffer_matches(patterns, bufnr)
  for kind, pattern_list in pairs(patterns) do
    if env.buf_matchers[kind](pattern_list, bufnr) then return true end
  end
  return false
end

--- A condition function if a macro is being recorded.
---@return boolean # whether or not a macro is currently being recorded.
-- @usage local heirline_component = { provider = "Example Provider", condition = require("heirline-components.core").condition.is_macro_recording }
function M.is_macro_recording() return vim.fn.reg_recording() ~= "" end

--- A condition function if search is visible.
---@return boolean # whether or not searching is currently visible.
-- @usage local heirline_component = { provider = "Example Provider", condition = require("heirline-components.core").condition.is_hlsearch }
function M.is_hlsearch() return vim.v.hlsearch ~= 0 end

--- A condition function if showcmdloc is set to statusline.
---@return boolean # whether or not statusline showcmd is enabled.
-- @usage local heirline_component = { provider = "Example Provider", condition = require("heirline-components.core").condition.is_statusline_showcmd }
function M.is_statusline_showcmd()
  return vim.opt.showcmdloc:get() == "statusline"
end

--- A condition function if the current file is in a git repo.
---@param bufnr table|integer a buffer number to check the condition for, a table with bufnr property, or nil to get the current buffer.
---@return boolean # whether or not the current file is in a git repo.
-- @usage local heirline_component = { provider = "Example Provider", condition = require("heirline-components.core").condition.is_git_repo }
function M.is_git_repo(bufnr)
  if type(bufnr) == "table" then bufnr = bufnr.bufnr end
  return vim.b[bufnr or 0].gitsigns_head
      or vim.b[bufnr or 0].gitsigns_status_dict
end

--- A condition function if there are any git changes.
---@param bufnr table|integer a buffer number to check the condition for, a table with bufnr property, or nil to get the current buffer.
---@return boolean # whether or not there are any git changes.
-- @usage local heirline_component = { provider = "Example Provider", condition = require("heirline-components.core").condition.git_changed }
function M.git_changed(bufnr)
  if type(bufnr) == "table" then bufnr = bufnr.bufnr end
  if not bufnr then bufnr = 0 end

  local git_status, n_changes, is_changed
  local gitsigns = vim.b[bufnr].gitsigns_status_dict
  local minidiff = vim.b[bufnr].minidiff_summary

  if gitsigns then -- gitsigns support
    git_status = gitsigns
    n_changes = (git_status.added or 0) + (git_status.removed or 0) + (git_status.changed or 0)
  elseif minidiff then -- mini.diff support
    git_status = minidiff
    n_changes = (git_status.add or 0) + (git_status.delete or 0) + (git_status.change or 0)
  end

  is_changed = n_changes and n_changes > 0

  return is_changed
end

--- A condition function if the current buffer is modified.
---@param bufnr table|integer a buffer number to check the condition for, a table with bufnr property, or nil to get the current buffer.
---@return boolean # whether or not the current buffer is modified.
-- @usage local heirline_component = { provider = "Example Provider", condition = require("heirline-components.core").condition.file_modified }
function M.file_modified(bufnr)
  if type(bufnr) == "table" then bufnr = bufnr.bufnr end
  return vim.bo[bufnr or 0].modified
end

--- A condition function if the current buffer is read only.
---@param bufnr table|integer a buffer number to check the condition for, a table with bufnr property, or nil to get the current buffer.
---@return boolean # whether or not the current buffer is read only or not modifiable.
-- @usage local heirline_component = { provider = "Example Provider", condition = require("heirline-components.core").condition.file_read_only }
function M.file_read_only(bufnr)
  if type(bufnr) == "table" then bufnr = bufnr.bufnr end
  local buffer = vim.bo[bufnr or 0]
  return not buffer.modifiable or buffer.readonly
end

--- A condition function if the current file has any diagnostics.
---@param bufnr table|integer a buffer number to check the condition for, a table with bufnr property, or nil to get the current buffer.
---@return boolean # whether or not the current file has any diagnostics.
-- @usage local heirline_component = { provider = "Example Provider", condition = require("heirline-components.core").condition.has_diagnostics }
function M.has_diagnostics(bufnr)
  if type(bufnr) == "table" then bufnr = bufnr.bufnr end
  return vim.tbl_contains(
    vim.diagnostic.count(bufnr or 0),
    function(v) return v > 0 end,
    { predicate = true }
  )
end

--- A condition function if there is a defined filetype.
---@param bufnr table|integer a buffer number to check the condition for, a table with bufnr property, or nil to get the current buffer.
---@return boolean # whether or not there is a filetype.
-- @usage local heirline_component = { provider = "Example Provider", condition = require("heirline-components.core").condition.has_filetype }
function M.has_filetype(bufnr)
  if type(bufnr) == "table" then bufnr = bufnr.bufnr end
  return vim.bo[bufnr or 0].filetype and vim.bo[bufnr or 0].filetype ~= ""
end

--- A condition function if a buffer is a file
---@param bufnr table|integer a buffer number to check the condition for, a table with bufnr property, or nil to get the current buffer
---@return boolean # whether or not the buffer is a file
-- @usage local heirline_component = { provider = "Example Provider", condition = require("heirline-components.core").condition.is_file }
function M.is_file(bufnr)
  if type(bufnr) == "table" then bufnr = bufnr.bufnr end
  return vim.bo[bufnr or 0].buftype == ""
end

--- A condition function if a virtual environment is activated
---@return boolean # whether or not virtual environment is activated
-- @usage local heirline_component = { provider = "Example Provider", condition = require("heirline-components.core").condition.has_virtual_env }
function M.has_virtual_env() return vim.env.VIRTUAL_ENV ~= nil or vim.env.CONDA_DEFAULT_ENV ~= nil end

--- A condition function if Aerial is available.
---@return boolean # whether or not aerial plugin is installed.
-- @usage local heirline_component = { provider = "Example Provider", condition = require("heirline-components.core").condition.aerial_available }
function M.aerial_available() return package.loaded["aerial"] end

--- A condition function if LSP is attached.
---@param bufnr table|integer a buffer number to check the condition for, a table with bufnr property, or nil to get the current buffer.
---@return boolean # whether or not LSP is attached.
-- @usage local heirline_component = { provider = "Example Provider", condition = require("heirline-components.core").condition.lsp_attached }
function M.lsp_attached(bufnr)
  if type(bufnr) == "table" then bufnr = bufnr.bufnr end
  return next(vim.lsp.get_clients { bufnr = bufnr or 0 }) ~= nil
end

--- A condition function if treesitter is in use.
---@param bufnr table|integer a buffer number to check the condition for, a table with bufnr property, or nil to get the current buffer.
---@return boolean # whether or not treesitter is active.
-- @usage local heirline_component = { provider = "Example Provider", condition = require("heirline-components.core").condition.treesitter_available }
function M.treesitter_available(bufnr)
  if type(bufnr) == "table" then bufnr = bufnr.bufnr end
  if not bufnr then bufnr = vim.api.nvim_get_current_buf() end
  return vim.treesitter.highlighter.active[bufnr] ~= nil
end

--- A condition function if the foldcolumn is enabled.
---@return boolean # true if vim.opt.foldcolumn > 0, false if vim.opt.foldcolumn == 0
function M.foldcolumn_enabled() return vim.opt.foldcolumn:get() ~= "0" end

--- A condition function if the number column is enabled.
---@return boolean # true if vim.opt.number or vim.opt.relativenumber, false if neither
function M.numbercolumn_enabled()
  return vim.opt.number:get() or vim.opt.relativenumber:get()
end

--- A condition function if the signcolumn is enabled
---@return boolean # false if vim.opt.signcolumn == "no", true otherwise
function M.signcolumn_enabled() return vim.opt.signcolumn:get() ~= "no" end

--- A condition function if the dap ui is opened.
---@return boolean # true if there is a visible buf with the filetype "dapui_breakpoints"
function M.is_dap_ui_visible()
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(winid)
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    local buf_ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    if bufname ~= "" and buf_ft == "dapui_breakpoints" then return true end
  end
  return false
end

return M
