local icons_by_key = require 'file.icons_by_file_extension'

local M = {}

local folder_icon = { icon = '', color = '#519ABA', cterm_color = '74', name = 'Folder' }
local default_icon = { icon = '', color = '#6d8086', cterm_color = '66', name = 'Default' }

local function basename(path)
  local value = tostring(path or '')
  if value == '' then return '' end
  return value:match('([^/]+)$') or value
end

local function ext_candidates(name)
  local out = {}
  local parts = {}
  for part in name:gmatch('[^.]+') do
    table.insert(parts, part)
  end
  for i = 2, #parts do
    table.insert(out, table.concat(parts, '.', i))
  end
  table.sort(out, function(a, b) return #a > #b end)
  return out
end

function M.get_icon(target, opts)
  local options = opts or {}
  local filename = target

  if type(target) == 'table' then
    options = deck.tbl_extend('keep', options, { is_dir = target.is_dir == true })
    filename = target.name or target.path or ''
  end

  filename = basename(filename)
  if options.is_dir then
    return folder_icon.icon, folder_icon.color, folder_icon
  end
  if filename == '' then
    return default_icon.icon, default_icon.color, default_icon
  end

  local data = icons_by_key[filename] or icons_by_key[filename:lower()]
  if not data then
    for _, candidate in ipairs(ext_candidates(filename)) do
      data = icons_by_key[candidate] or icons_by_key[candidate:lower()]
      if data then break end
    end
  end
  if not data then
    return default_icon.icon, default_icon.color, default_icon
  end
  return data.icon, data.color, data
end

return M
