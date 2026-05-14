local Actions = require 'file.actions'
local config = require 'file.config'
local Icons = require 'file.icons'
local Metas = require 'file.metas'
local Preview = require 'file.preview'

local M = {}

local function span(text, color)
  local s = deck.style.span(tostring(text or ''))
  if color and color ~= '' then s = s:fg(color) end
  return s
end

local function line(parts) return deck.style.line(parts) end

local function format_size(bytes)
  local value = tonumber(bytes)
  if not value or value < 0 then return nil end
  if value < 1024 then return string.format('%dB', value) end

  local units = { 'K', 'M', 'G', 'T', 'P' }
  value = value / 1024
  for i, unit in ipairs(units) do
    if value < 1024 or i == #units then
      if value >= 10 then
        return string.format('%.0f%s', value, unit)
      end
      return string.format('%.1f%s', value, unit)
    end
    value = value / 1024
  end
end

local function build_bottom_line(handle)
  if not handle or handle.is_dir then return nil end

  local size = format_size(handle.size)
  if not size then return nil end

  return line {
    span('', 'white'),
    span(' ' .. size .. ' ', 'blue'):bg('white'),
    span('', 'white'),
  }
end

local function sort_handles(handles)
  table.sort(handles, function(a, b)
    if a.is_dir ~= b.is_dir then return a.is_dir end
    return string.lower(a.name) < string.lower(b.name)
  end)
  return handles
end

local function is_hidden(name)
  return type(name) == 'string' and name:sub(1, 1) == '.'
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

function M.new(provider, opt)
  local self = {
    provider = provider,
    config = config.new(opt or {}),
  }
  setmetatable(self, { __index = M })
  self.actions = Actions.new(self)
  self.previewer = Preview.new(self)
  self.metas = Metas.new(self)
  return self
end

function M:build_entries(path)
  local dir_handle, decode_err = self.provider:decode_page_path(path)
  if not dir_handle then
    return {
      info_entry('error', decode_err, 'red'),
    }, nil
  end

  return nil, dir_handle
end

function M:list(path, cb)
  local error_entries, dir_handle = self:build_entries(path)
  if error_entries then
    cb(self.metas:attach_all(error_entries))
    return
  end

  self.provider:list(dir_handle, function(handles, err)
    if err then
      cb(self.metas:attach_all {
        info_entry('error', 'Failed to read ' .. tostring(dir_handle.path or dir_handle.id), 'red'),
        info_entry('error-detail', err, 'red'),
      })
      return
    end

    handles = sort_handles(handles or {})
    local out = {}
    for _, handle in ipairs(handles) do
      if not self.config.show_hidden and is_hidden(handle.name) then goto continue end

      local marker_color = self.actions:marker_color(handle)
      local marker = span ' '
      if marker_color then marker = span('▌', marker_color) end

      local icon, icon_color = Icons.get_icon(handle)
      local name_color = handle.is_dir and 'blue' or 'white'

      table.insert(out, {
        key = handle.name,
        kind = handle.is_dir and 'dir' or 'file',
        name = handle.name,
        handle = handle,
        path = handle.path,
        path_parts = self.provider:encode_page_path(handle),
        is_dir = handle.is_dir,
        display = line {
          marker,
          span(icon .. ' ', icon_color),
          span(handle.name, name_color),
        },
        bottom_line = build_bottom_line(handle),
      })

      ::continue::
    end

    if #out == 0 then table.insert(out, info_entry('empty', 'Empty directory')) end
    cb(self.metas:attach_all(out))
  end)
end

function M:refresh_current_page(cb)
  local expected_path = deck.api.get_current_path() or {}
  self:list(expected_path, function(entries)
    if not deck.deep_equal(expected_path, deck.api.get_current_path() or {}) then return end
    deck.api.set_entries(nil, entries)
    if cb then cb(entries) end
  end)
end

function M:preview(entry, cb)
  if not entry then return end
  if entry.kind == 'dir' then return self.previewer:dir_preview(entry, cb) end
  if entry.kind == 'file' then return self.previewer:file_preview(entry, cb) end
  return self.previewer:info_preview(entry, cb)
end

return M
