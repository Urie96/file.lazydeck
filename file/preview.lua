local M = {}

local config = require 'file.config'

local runtime = {
  preview_token = 0,
}

local CODE_EXTENSIONS = {
  c = true,
  cc = true,
  cpp = true,
  css = true,
  go = true,
  h = true,
  hpp = true,
  html = true,
  java = true,
  js = true,
  json = true,
  jsx = true,
  lua = true,
  md = true,
  nix = true,
  py = true,
  rb = true,
  rs = true,
  sh = true,
  sql = true,
  toml = true,
  ts = true,
  tsx = true,
  txt = true,
  xml = true,
  yaml = true,
  yml = true,
  zig = true,
}

local SPECIAL_FILENAMES = {
  ['Dockerfile'] = 'dockerfile',
  ['Makefile'] = 'makefile',
  ['justfile'] = 'makefile',
}

local function span(text, color)
  local s = lc.style.span(tostring(text or ''))
  if color and color ~= '' then s = s:fg(color) end
  return s
end

local function line(parts) return lc.style.line(parts) end
local function text(lines) return lc.style.text(lines) end

local function sort_entries(entries)
  table.sort(entries, function(a, b)
    if a.is_dir ~= b.is_dir then return a.is_dir end
    return string.lower(a.name) < string.lower(b.name)
  end)
  return entries
end

local function is_hidden(name) return type(name) == 'string' and name:sub(1, 1) == '.' end

local function read_children(path)
  local entries, err = lc.fs.read_dir_sync(path)
  if err then return nil, err end
  entries = sort_entries(entries or {})
  if config.get().show_hidden then return entries end

  local visible = {}
  for _, entry in ipairs(entries) do
    if not is_hidden(entry.name) then table.insert(visible, entry) end
  end
  return visible
end

local function language_for(name)
  if SPECIAL_FILENAMES[name] then return SPECIAL_FILENAMES[name] end
  local ext = tostring(name):match '%.([^.]+)$'
  if not ext then return nil end
  ext = string.lower(ext)
  if CODE_EXTENSIONS[ext] then return ext end
  return nil
end

local function directory_lines(path)
  local entries, err = read_children(path)
  if err then return {
    line { span('Failed to read directory', 'red') },
    line { span(err, 'red') },
  } end

  if #entries == 0 then return {
    line { span('Empty directory', 'darkgray') },
  } end

  local lines = {
    line { span(path, 'cyan') },
    line { span(string.format('%d items', #entries), 'darkgray') },
    line { '' },
  }

  for _, entry in ipairs(entries) do
    table.insert(
      lines,
      line {
        span(entry.name, entry.is_dir and 'blue' or 'white'),
      }
    )
  end

  return lines
end

local function next_preview_token()
  runtime.preview_token = runtime.preview_token + 1
  return runtime.preview_token
end

local function is_latest_preview_token(token) return runtime.preview_token == token end

local function is_current_hover(entry) return lc.deep_equal(entry.path_parts or {}, lc.api.get_hovered_path() or {}) end

local function render_file_preview(path, content, err, meta)
  if err then return text {
    line { span('Failed to read file', 'red') },
    line { span(err, 'red') },
  } end

  if content:find('\0', 1, true) then
    return text {
      line { span('Binary file', 'yellow') },
      line { span(path, 'white') },
    }
  end

  local truncated = meta and meta.truncated == true
  local language = language_for(path:match '[^/]+$' or path)

  if truncated then
    if language then
      local highlighted = lc.style.highlight(content, language)
      highlighted:append ''
      highlighted:append(line { span('Preview truncated', 'yellow') })
      return highlighted
    end
    local plain = text { content }
    plain:append ''
    plain:append(line { span('Preview truncated', 'yellow') })
    return plain
  end

  if language then return lc.style.highlight(content, language) end
  return text { content }
end

function M.dir_preview(entry, cb)
  next_preview_token()
  cb(text(directory_lines(entry.path)))
end

function M.file_preview(entry, cb)
  local token = next_preview_token()
  local language = language_for(entry.path:match '[^/]+$' or entry.path)
  if not language then
    cb(text {
      line { span('No preview for this file type', 'darkgray') },
    })
    return
  end

  lc.fs.read_file(entry.path, { max_chars = config.get().preview_max_chars }, function(content, err, meta)
    if not is_latest_preview_token(token) then return end
    if not is_current_hover(entry) then return end
    cb(render_file_preview(entry.path, content, err, meta))
  end)
end

function M.info_preview(entry, cb)
  next_preview_token()
  cb(text {
    line { span(entry.message or 'file', entry.color or 'darkgray') },
  })
end

return M
