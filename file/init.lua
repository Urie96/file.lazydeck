local M = {}

local actions = require 'file.actions'
local config = require 'file.config'
local metas = require 'file.metas'

local function span(text, color)
  local s = lc.style.span(tostring(text or ''))
  if color and color ~= '' then s = s:fg(color) end
  return s
end

local function line(parts) return lc.style.line(parts) end

local function sort_entries(entries)
  table.sort(entries, function(a, b)
    if a.is_dir ~= b.is_dir then return a.is_dir end
    return string.lower(a.name) < string.lower(b.name)
  end)
  return entries
end

local function is_hidden(name) return type(name) == 'string' and name:sub(1, 1) == '.' end

local function fs_path_from_page_path(path)
  local segments = {}
  for i = 2, #path do
    table.insert(segments, path[i])
  end
  if #segments == 0 then return '/' end
  return '/' .. table.concat(segments, '/')
end

local function page_path_for_child(path, name)
  local next_path = {}
  for i = 1, #path do
    table.insert(next_path, path[i])
  end
  table.insert(next_path, name)
  return next_path
end

local function display_entry(name, is_dir)
  return line {
    span ' ',
    span(name, is_dir and 'blue' or 'white'),
  }
end

local function info_entry(key, message, color)
  return {
    key = key,
    kind = 'info',
    message = message,
    color = color or 'darkgray',
    display = line { span(message, color or 'darkgray') },
  }
end

local function build_entries(path)
  local current_fs_path = fs_path_from_page_path(path)
  local entries, err = lc.fs.read_dir_sync(current_fs_path)
  if err then
    return {
      info_entry('error', 'Failed to read ' .. current_fs_path, 'red'),
      info_entry('error-detail', err, 'red'),
    }
  end

  entries = sort_entries(entries or {})
  local out = {}
  local show_hidden = config.get().show_hidden

  for _, entry in ipairs(entries) do
    if not show_hidden and is_hidden(entry.name) then goto continue end
    local child_fs_path = current_fs_path == '/' and ('/' .. entry.name) or (current_fs_path .. '/' .. entry.name)
    local marker_color = actions.marker_color(child_fs_path)
    local marker = span ' '
    if marker_color then marker = marker:bg(marker_color) end
    table.insert(out, {
      key = entry.name,
      kind = entry.is_dir and 'dir' or 'file',
      name = entry.name,
      path = child_fs_path,
      path_parts = page_path_for_child(path, entry.name),
      is_dir = entry.is_dir,
      display = line {
        marker,
        span(entry.name, entry.is_dir and 'blue' or 'white'),
      },
    })
    ::continue::
  end

  if #out == 0 then table.insert(out, info_entry('empty', 'Empty directory')) end

  return out
end

function M.setup(opt) config.setup(opt or {}) end

function M.list(path, cb) cb(metas.attach_all(build_entries(path))) end

M.copy_hovered_entry = actions.copy_hovered_entry

return M
