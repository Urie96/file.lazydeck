local M = {}

local actions = require 'file.actions'
local config = require 'file.config'
local preview = require 'file.preview'

local function toggle_hidden()
  local show_hidden = config.toggle_hidden()
  lc.cmd 'reload'
  return show_hidden
end

local metatables = {
  dir = {
    __index = {
      preview = preview.dir_preview,
      keymap = {},
    },
  },
  file = {
    __index = {
      preview = preview.file_preview,
      keymap = {},
    },
  },
  info = {
    __index = {
      preview = preview.info_preview,
      keymap = {},
    },
  },
}

local function add_keymap(maps, key, callback, desc)
  if key and key ~= '' then
    for _, map in ipairs(maps) do
      map[key] = { callback = callback, desc = desc }
    end
  end
end

function M.setup(cfg)
  local keymap = cfg.keymap
  local dir_keymap = metatables.dir.__index.keymap
  local file_keymap = metatables.file.__index.keymap
  local info_keymap = metatables.info.__index.keymap
  local dir_and_file_keymap = { dir_keymap, file_keymap }
  local all_keymap = { dir_keymap, file_keymap, info_keymap }
  add_keymap(all_keymap, keymap.new_file, actions.create_file, 'new file')
  add_keymap(all_keymap, keymap.new_dir, actions.create_dir, 'new directory')
  add_keymap(all_keymap, keymap.toggle_hidden, toggle_hidden, 'toggle hidden files')
  add_keymap(dir_and_file_keymap, keymap.select, actions.select_hovered_entry, 'select entry')
  add_keymap(dir_and_file_keymap, keymap.yank, actions.copy_hovered_entry, 'copy entry')
  add_keymap(dir_and_file_keymap, keymap.cut, actions.cut_hovered_entry, 'cut entry')
  add_keymap(dir_and_file_keymap, keymap.delete, actions.delete_hovered_entry, 'delete entry')
end

function M.attach_all(entries)
  local out = {}
  for _, entry in ipairs(entries or {}) do
    local mt = metatables[entry.kind]
    if mt then
      table.insert(out, setmetatable(entry, mt))
    else
      table.insert(out, entry)
    end
  end
  return out
end

return M
