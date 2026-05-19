local Browser = require 'file.browser'
local Icons = require 'file.icons'
local LocalProvider = require 'file.provider.local'

local M = {}

function M.meta()
  return {
    icon = '󰈔',
    desc = 'File browser',
    color = 'blue',
  }
end

local default_browser = nil

local function ensure_default_browser()
  if not default_browser then
    default_browser = M.new_local({})
  end
  return default_browser
end

function M.new(provider, opt)
  return Browser.new(provider, opt or {})
end

function M.new_local(opt)
  return Browser.new(LocalProvider.new(opt or {}), opt or {})
end

function M.setup(opt)
  local cfg = opt or {}
  if cfg.root == nil then cfg.root = os.getenv('HOME') or '/' end
  default_browser = M.new_local(cfg)
end

function M.list(path, cb)
  return ensure_default_browser():list(path, cb)
end

function M.preview(entry, cb)
  return ensure_default_browser():preview(entry, cb)
end

function M.get_icon(target, opt)
  return Icons.get_icon(target, opt)
end

function M.yank_hovered_entry()
  return ensure_default_browser().actions:yank_hovered_entry()
end

return M
