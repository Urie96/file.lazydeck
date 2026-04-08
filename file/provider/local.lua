local M = {}

local function basename(path)
  local value = tostring(path or '')
  if value == '' or value == '/' then return '/' end
  return value:match '([^/]+)$' or value
end

local function dirname(path)
  local value = tostring(path or '')
  if value == '' or value == '/' then return '/' end
  local dir = value:match '^(.*)/[^/]+$'
  if not dir or dir == '' then return '/' end
  return dir
end

local function join_path(dir, name)
  if dir == '/' then return '/' .. name end
  return dir .. '/' .. name
end

function M.new(opt)
  local self = {
    name = 'local',
    route_name = (opt or {}).route_name or 'file',
  }
  return setmetatable(self, { __index = M })
end

function M:handle(path, is_dir, size)
  local value = tostring(path or '/')
  if value == '' then value = '/' end
  return {
    id = value,
    name = value == '/' and '/' or basename(value),
    path = value,
    is_dir = is_dir == true,
    size = size,
  }
end

function M:root()
  return self:handle('/', true)
end

function M:decode_page_path(path)
  if type(path) ~= 'table' or path[1] ~= self.route_name then
    return nil, 'Invalid page path for provider ' .. self.route_name
  end

  local segments = {}
  for i = 2, #path do
    table.insert(segments, path[i])
  end
  if #segments == 0 then return self:root() end
  return self:handle('/' .. table.concat(segments, '/'), true)
end

function M:encode_page_path(handle)
  local out = { self.route_name }
  local value = tostring(handle.path or '')
  if value == '' or value == '/' then return out end
  for segment in value:gmatch '[^/]+' do
    table.insert(out, segment)
  end
  return out
end

function M:list(dir_handle, cb)
  local entries, err = lc.fs.read_dir_sync(dir_handle.path)
  if err then
    cb(nil, err)
    return
  end

  local out = {}
  for _, entry in ipairs(entries or {}) do
    local path = join_path(dir_handle.path, entry.name)
    table.insert(out, self:handle(path, entry.is_dir, entry.size))
  end
  cb(out)
end

function M:stat(handle, cb)
  cb(lc.fs.stat(handle.path))
end

function M:parent(handle)
  local value = tostring(handle.path or '')
  if value == '' or value == '/' then return nil end
  return self:handle(dirname(value), true)
end

function M:join(dir_handle, name)
  return self:handle(join_path(dir_handle.path, name))
end

function M:read_file(handle, opts, cb)
  return lc.fs.read_file(handle.path, opts, cb)
end

function M:edit(handle)
  lc.system.edit({ path = handle.path })
end

function M:create_file(dir_handle, name, cb)
  local handle = self:join(dir_handle, name)
  local existing = lc.fs.stat(handle.path)
  if existing.exists then
    cb(false, 'Target already exists: ' .. handle.path)
    return
  end
  local ok, err = lc.fs.write_file_sync(handle.path, '')
  cb(ok, err)
end

function M:create_dir(dir_handle, name, cb)
  local handle = self:join(dir_handle, name)
  local existing = lc.fs.stat(handle.path)
  if existing.exists then
    cb(false, 'Target already exists: ' .. handle.path)
    return
  end
  local ok, err = lc.fs.mkdir(handle.path)
  cb(ok, err)
end

function M:remove(handles, cb)
  local errors = {}
  for _, handle in ipairs(handles or {}) do
    local ok, err = lc.fs.remove(handle.path)
    if not ok then
      table.insert(errors, tostring(handle.path) .. ': ' .. tostring(err or 'unknown error'))
    end
  end

  if #errors == 0 then
    cb(true)
    return
  end
  cb(false, errors[1])
end

local function complete_transfer(self, operation, handles, target_dir, cb)
  local cmd = { operation == 'move' and 'mv' or 'cp' }
  if operation ~= 'move' then table.insert(cmd, '-R') end
  for _, handle in ipairs(handles) do
    table.insert(cmd, handle.path)
  end
  table.insert(cmd, target_dir.path)

  lc.system(cmd, function(out)
    if out.code == 0 then
      local targets = {}
      for _, handle in ipairs(handles) do
        table.insert(targets, self:join(target_dir, handle.name))
      end
      cb(true, nil, { targets = targets })
      return
    end

    local err = tostring(out.stderr or ''):trim()
    if err == '' then err = 'exit code ' .. tostring(out.code) end
    cb(false, err)
  end)
end

function M:copy(handles, target_dir, cb)
  complete_transfer(self, 'copy', handles, target_dir, cb)
end

function M:move(handles, target_dir, cb)
  complete_transfer(self, 'move', handles, target_dir, cb)
end

function M:rename(handle, name, cb)
  if handle.path == '/' then
    cb(false, 'Cannot rename root directory')
    return
  end

  local parent = self:parent(handle)
  if not parent then
    cb(false, 'Failed to resolve parent directory')
    return
  end

  local target = self:join(parent, name)
  local existing = lc.fs.stat(target.path)
  if existing.exists then
    cb(false, 'Target already exists: ' .. target.path)
    return
  end

  lc.system({ 'mv', handle.path, target.path }, function(out)
    if out.code == 0 then
      target.is_dir = handle.is_dir
      target.size = handle.size
      cb(true, nil, { target = target })
      return
    end

    local err = tostring(out.stderr or ''):trim()
    if err == '' then err = 'exit code ' .. tostring(out.code) end
    cb(false, err)
  end)
end

return M
