local M = {}

local function add_keymap(maps, key, callback, desc)
  if key and key ~= '' then
    for _, map in ipairs(maps) do
      map[key] = { callback = callback, desc = desc }
    end
  end
end

function M.new(browser)
  local preview = browser.previewer
  local actions = browser.actions

  local self = {
    dir = {
      __index = {
        preview = function(entry, cb) return preview:dir_preview(entry, cb) end,
        keymap = {},
      },
    },
    file = {
      __index = {
        preview = function(entry, cb) return preview:file_preview(entry, cb) end,
        keymap = {},
      },
    },
    info = {
      __index = {
        preview = function(entry, cb) return preview:info_preview(entry, cb) end,
        keymap = {},
      },
    },
  }

  local keymap = browser.config.keymap
  local dir_keymap = self.dir.__index.keymap
  local file_keymap = self.file.__index.keymap
  local info_keymap = self.info.__index.keymap
  local dir_and_file_keymap = { dir_keymap, file_keymap }
  local all_keymap = { dir_keymap, file_keymap, info_keymap }

  add_keymap(all_keymap, keymap.new_file, function() actions:create_file() end, 'new file')
  add_keymap(all_keymap, keymap.new_dir, function() actions:create_dir() end, 'new directory')
  add_keymap(all_keymap, keymap.toggle_hidden, function() actions:toggle_hidden() end, 'toggle hidden files')
  add_keymap({ file_keymap }, keymap.edit, function() actions:edit_hovered_entry() end, 'edit file')
  add_keymap(dir_and_file_keymap, keymap.rename, function() actions:rename_hovered_entry() end, 'rename entry')
  add_keymap(dir_and_file_keymap, keymap.select, function() actions:select_hovered_entry() end, 'select entry')
  add_keymap(dir_and_file_keymap, keymap.yank, function() actions:yank_hovered_entry() end, 'yank entry')
  add_keymap(dir_and_file_keymap, keymap.cut, function() actions:cut_hovered_entry() end, 'cut entry')
  add_keymap(dir_and_file_keymap, keymap.delete, function() actions:delete_hovered_entry() end, 'delete entry')
  add_keymap(dir_and_file_keymap, keymap.paste, function() actions:paste_from_clipboard() end, 'paste entry')

  return setmetatable(self, { __index = M })
end

function M:attach_all(entries)
  local out = {}
  for _, entry in ipairs(entries or {}) do
    local mt = self[entry.kind]
    if mt then
      table.insert(out, setmetatable(entry, mt))
    else
      table.insert(out, entry)
    end
  end
  return out
end

return M
