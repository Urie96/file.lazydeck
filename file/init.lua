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

local function should_register_page_keymaps(opt)
  return not opt or opt.register_page_keymaps ~= false
end

local function page_keymap_pattern(browser)
  local provider = browser.provider
  local root_path

  if type(provider.root) == 'function' and type(provider.encode_page_path) == 'function' then
    local ok, root = pcall(function() return provider:root() end)
    if ok and root then
      ok, root_path = pcall(function() return provider:encode_page_path(root) end)
      if not ok then root_path = nil end
    end
  end

  if type(root_path) ~= 'table' or #root_path == 0 then
    root_path = { provider.route_name or 'file' }
  end

  return '/' .. table.concat(root_path, '/') .. '/**'
end

local function map_file_key(browser, key, callback, desc)
  if not key or key == '' then return end
  deck.keymap.set('main', key, callback, { path = page_keymap_pattern(browser), desc = desc })
end

function M.register_page_keymaps(browser)
  local keymap = browser.config.keymap
  local actions = browser.actions

  map_file_key(browser, keymap.open, function() actions:open_hovered_entry() end, 'open entry')
  map_file_key(browser, keymap.enter, function() actions:open_hovered_entry() end, 'open entry')
  map_file_key(browser, keymap.new_file, function() actions:create_file() end, 'new file')
  map_file_key(browser, keymap.new_dir, function() actions:create_dir() end, 'new directory')
  map_file_key(browser, keymap.toggle_hidden, function() actions:toggle_hidden() end, 'toggle hidden files')
  map_file_key(browser, keymap.edit, function() actions:edit_hovered_entry() end, 'edit file')
  map_file_key(browser, keymap.rename, function() actions:rename_hovered_entry() end, 'rename entry')
  map_file_key(browser, keymap.select, function() deck.api.toggle_selected() end, 'select entry')
  map_file_key(browser, keymap.yank, function() actions:yank_hovered_entry() end, 'yank entry')
  map_file_key(browser, keymap.cut, function() actions:cut_hovered_entry() end, 'cut entry')
  map_file_key(browser, keymap.delete, function() actions:delete_hovered_entry() end, 'delete entry')
  map_file_key(browser, keymap.paste, function() actions:paste_from_clipboard() end, 'paste entry')
  map_file_key(browser, keymap.force_preview, function() actions:force_preview_hovered_entry() end, 'force preview')
end

local function ensure_default_browser()
  if not default_browser then
    default_browser = M.new_local({})
  end
  return default_browser
end

function M.new(provider, opt)
  local browser = Browser.new(provider, opt or {})
  if should_register_page_keymaps(opt) then
    M.register_page_keymaps(browser)
  end
  return browser
end

function M.new_local(opt)
  local browser = Browser.new(LocalProvider.new(opt or {}), opt or {})
  if should_register_page_keymaps(opt) then
    M.register_page_keymaps(browser)
  end
  return browser
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
