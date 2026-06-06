local M = {}

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
  local s = deck.style.span(tostring(text or ''))
  if color and color ~= '' then s = s:fg(color) end
  return s
end

local function line(parts) return deck.style.line(parts) end
local function text(lines) return deck.style.text(lines) end

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

local function language_for(name)
  if SPECIAL_FILENAMES[name] then return SPECIAL_FILENAMES[name] end
  local ext = tostring(name):match '%.([^.]+)$'
  if not ext then return nil end
  ext = string.lower(ext)
  if CODE_EXTENSIONS[ext] then return ext end
  return nil
end

local IMAGE_EXTENSIONS = {
  jpeg = true,
  jpg = true,
  png = true,
  webp = true,
}

local function is_code_file(name)
  return language_for(name) ~= nil
end

local function is_image_file(name)
  local ext = tostring(name or ''):match '%.([^.]+)$'
  if not ext then return false end
  return IMAGE_EXTENSIONS[string.lower(ext)] == true
end

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
      local highlighted = deck.style.highlight(content, language)
      highlighted:append ''
      highlighted:append(line { span('Preview truncated', 'yellow') })
      return highlighted
    end
    local plain = text { content }
    plain:append ''
    plain:append(line { span('Preview truncated', 'yellow') })
    return plain
  end

  if language then return deck.style.highlight(content, language) end
  return text { content }
end

function M.new(browser)
  local self = {
    browser = browser,
    preview_token = 0,
  }
  return setmetatable(self, { __index = M })
end

function M:next_preview_token()
  self.preview_token = self.preview_token + 1
  return self.preview_token
end

function M:is_latest_preview_token(token)
  return self.preview_token == token
end

function M:is_current_hover(entry)
  return deck.deep_equal(entry.path_parts or {}, deck.api.get_hovered_path() or {})
end

function M:run_debounced(entry, cb, work)
  local token = self:next_preview_token()
  local delay = tonumber(self.browser.config.preview_debounce_ms) or 0

  local run = function()
    if not self:is_latest_preview_token(token) then return end
    if not self:is_current_hover(entry) then return end
    work(token)
  end

  if delay <= 0 then
    run()
    return token
  end

  deck.defer_fn(run, delay)
  return token
end

function M:read_children(handle, cb)
  self.browser.provider:list(handle, function(entries, err)
    if err then
      cb(nil, err)
      return
    end

    entries = sort_handles(entries or {})
    if self.browser.config.show_hidden then
      cb(entries)
      return
    end

    local visible = {}
    for _, entry in ipairs(entries) do
      if not is_hidden(entry.name) then table.insert(visible, entry) end
    end
    cb(visible)
  end)
end

function M:directory_lines(handle, cb)
  self:read_children(handle, function(entries, err)
    if err then
      cb {
        line { span('Failed to read directory', 'red') },
        line { span(err, 'red') },
      }
      return
    end

    if #entries == 0 then
      cb {
        line { span('Empty directory', 'darkgray') },
      }
      return
    end

    local lines = {
      line { span(handle.path or handle.id, 'cyan') },
      line { span(string.format('%d items', #entries), 'darkgray') },
      line { '' },
    }

    for _, entry in ipairs(entries) do
      table.insert(lines, line {
        span(entry.name, entry.is_dir and 'blue' or 'white'),
      })
    end

    cb(lines)
  end)
end

function M:dir_preview(entry, cb)
  if self.browser.config.preview_mode == 'file-only' then
    self:next_preview_token()
    cb(text {
      line { span('Directory', 'cyan') },
      line { span(entry.handle.path or entry.handle.id, 'white') },
    })
    return
  end

  self:run_debounced(entry, cb, function(token)
    self:directory_lines(entry.handle, function(lines)
      if not self:is_latest_preview_token(token) then return end
      if not self:is_current_hover(entry) then return end
      cb(text(lines))
    end)
  end)
end

function M:read_file_preview(entry, cb)
  local path = entry.handle.path or entry.handle.id
  self:run_debounced(entry, cb, function(token)
    self.browser.provider:read_file(entry.handle, { max_chars = self.browser.config.preview_max_chars }, function(content, err, meta)
      if not self:is_latest_preview_token(token) then return end
      if not self:is_current_hover(entry) then return end
      cb(render_file_preview(path, content, err, meta))
    end)
  end)
end

local function remote_image_cache_dir(provider, handle)
  local home = os.getenv 'HOME'
  if not home or home == '' then return nil, 'HOME is not set' end

  local source = tostring(provider.name or 'provider')
    .. '\0' .. tostring(handle.id or '')
    .. '\0' .. tostring(handle.path or '')
    .. '\0' .. tostring(handle.size or '')
  local key = deck.hash.md5(source)
  return home .. '/.cache/lazydeck/remote-preview-images/' .. key
end

function M:remote_image_preview(entry, cb)
  local path = entry.handle.path or entry.handle.id
  if type(self.browser.provider.read_file) ~= 'function' then return false end

  local cache_dir, cache_err = remote_image_cache_dir(self.browser.provider, entry.handle)
  if not cache_dir then
    cb(text {
      line { span('Failed to preview image', 'red') },
      line { span(tostring(cache_err), 'red') },
      line { span(path, 'white') },
    })
    return true
  end

  local target_path = cache_dir .. '/' .. tostring(entry.handle.name or 'preview-image')
  local stat = deck.fs.stat(target_path)
  local expected_size = tonumber(entry.handle.size)
  if stat and stat.exists and stat.is_file and (not expected_size or tonumber(stat.size) == expected_size) then
    self:next_preview_token()
    cb(deck.style.image(target_path))
    return true
  end

  local ok_mkdir, mkdir_err = deck.fs.mkdir(cache_dir)
  if not ok_mkdir then
    cb(text {
      line { span('Failed to preview image', 'red') },
      line { span(tostring(mkdir_err), 'red') },
      line { span(path, 'white') },
    })
    return true
  end

  local token = self:next_preview_token()
  self.browser.provider:read_file(entry.handle, nil, function(content, err)
    if not self:is_latest_preview_token(token) then return end
    if not self:is_current_hover(entry) then return end

    if err then
      cb(text {
        line { span('Failed to preview image', 'red') },
        line { span(tostring(err), 'red') },
        line { span(path, 'white') },
      })
      return
    end

    local ok_write, write_err = deck.fs.write_file_sync(target_path, content or '')
    if not ok_write then
      cb(text {
        line { span('Failed to preview image', 'red') },
        line { span(tostring(write_err), 'red') },
        line { span(path, 'white') },
      })
      return
    end

    cb(deck.style.image(target_path))
  end)
  return true
end

function M:force_file_preview(entry, cb)
  if not entry or not entry.handle then return end

  local path = entry.handle.path or entry.handle.id
  local provider_name = tostring(self.browser.provider and self.browser.provider.name or '')
  local filename = path:match '[^/]+$' or path
  if provider_name ~= 'local' and is_image_file(filename) and self:remote_image_preview(entry, cb) then return end

  self:read_file_preview(entry, cb)
end

function M:file_preview(entry, cb)
  local path = entry.handle.path or entry.handle.id
  local provider_name = tostring(self.browser.provider and self.browser.provider.name or '')
  local filename = path:match '[^/]+$' or path

  if provider_name == 'local' and is_image_file(filename) then
    self:next_preview_token()
    cb(deck.style.image(path))
    return
  end

  if provider_name ~= 'local' and not is_code_file(filename) then
    self:next_preview_token()
    cb(text {
      line { span('Preview skipped', 'yellow') },
      line { span('Non-code file on non-local provider', 'darkgray') },
      line { span('Press P to force preview', 'darkgray') },
      line { span(path, 'white') },
    })
    return
  end

  self:read_file_preview(entry, cb)
end

function M:info_preview(entry, cb)
  self:next_preview_token()
  cb(text {
    line { span(entry.message or 'file', entry.color or 'darkgray') },
  })
end

return M
