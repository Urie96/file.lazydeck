local M = {}

local config = require 'file.config'
local selected_paths = {}
local clipboard_paths = {}
local clipboard_operation = nil

local function basename(path)
  local value = tostring(path or '')
  return value:match '([^/]+)$' or value
end

local function dirname(path)
  local value = tostring(path or '')
  if value == '' or value == '/' then return '/' end
  local dir = value:match '^(.*)/[^/]+$'
  if not dir or dir == '' then return '/' end
  return dir
end

local function copy_list(paths)
  local out = {}
  for i = 1, #paths do
    out[i] = paths[i]
  end
  return out
end

local function sorted_keys(set)
  local out = {}
  for path, selected in pairs(set) do
    if selected then table.insert(out, path) end
  end
  table.sort(out)
  return out
end

local function list_to_set(paths)
  local out = {}
  for _, path in ipairs(paths or {}) do
    out[path] = true
  end
  return out
end

local function page_path_from_fs_path(path)
  local out = { 'file' }
  local value = tostring(path or '')
  if value == '' or value == '/' then return out end
  for segment in value:gmatch '[^/]+' do
    table.insert(out, segment)
  end
  return out
end

local function file_fs_path_from_page_path(path)
  if type(path) ~= 'table' or path[1] ~= 'file' then
    return nil, 'Paste is only available under /file'
  end

  local segments = {}
  for i = 2, #path do
    table.insert(segments, path[i])
  end

  if #segments == 0 then return '/' end
  return '/' .. table.concat(segments, '/')
end

local function join_path(dir, name)
  if dir == '/' then return '/' .. name end
  return dir .. '/' .. name
end

local function notify_copy_ready(source_path, paste_key)
  lc.notify(('Copied %s. Press %s to paste'):format(source_path, paste_key))
end

local function notify_multi_copy_ready(source_paths, paste_key)
  if #source_paths == 1 then
    notify_copy_ready(source_paths[1], paste_key)
    return
  end

  lc.notify(('Copied %d entries. Press %s to paste'):format(#source_paths, paste_key))
end

local function notify_multi_cut_ready(source_paths, paste_key)
  if #source_paths == 1 then
    lc.notify(('Cut %s. Press %s to paste'):format(source_paths[1], paste_key))
    return
  end

  lc.notify(('Cut %d entries. Press %s to paste'):format(#source_paths, paste_key))
end

local function unique_parent_dirs(paths)
  local seen = {}
  local out = {}
  for _, path in ipairs(paths) do
    local dir = dirname(path)
    if not seen[dir] then
      seen[dir] = true
      table.insert(out, dir)
    end
  end
  table.sort(out)
  return out
end

local function invalidate_source_caches(paths)
  for _, dir in ipairs(unique_parent_dirs(paths)) do
    lc.api.clear_page_cache(page_path_from_fs_path(dir))
  end
end

local function validate_target_paths(target_dir, source_paths)
  local seen = {}
  for _, source_path in ipairs(source_paths) do
    local target_path = join_path(target_dir, basename(source_path))
    if seen[target_path] then return nil, 'Multiple selected entries share the same name: ' .. target_path end
    seen[target_path] = true

    local existing = lc.fs.stat(target_path)
    if existing.exists then return nil, 'Target already exists: ' .. target_path end
  end

  local ordered = {}
  for path, _ in pairs(seen) do
    table.insert(ordered, path)
  end
  table.sort(ordered)
  return ordered
end

local function current_target_dir()
  local current_path = lc.api.get_current_path()
  local target_dir, err = file_fs_path_from_page_path(current_path)
  if not target_dir then
    lc.notify(err)
    return nil
  end

  local stat = lc.fs.stat(target_dir)
  if not stat.exists or not stat.is_dir then
    lc.notify('Current page is not a directory: ' .. target_dir)
    return nil
  end
  return target_dir
end

local function selected_or_hovered_paths()
  local source_paths = sorted_keys(selected_paths)
  if #source_paths > 0 then return source_paths end

  local entry = lc.api.page_get_hovered()
  if not entry or not entry.path then return nil end
  return { entry.path }
end

function M.register_paste_keymap(source_paths, operation)
  local paste_key = config.get().keymap.paste
  if not paste_key or paste_key == '' then return end

  local paths = copy_list(source_paths)
  local action = operation == 'move' and 'move' or 'paste'
  local desc = #paths == 1 and (action .. ' ' .. basename(paths[1])) or ((operation == 'move' and 'move ' or 'paste ') .. tostring(#paths) .. ' entries')

  lc.keymap.set('main', paste_key, function()
    local current_path = lc.api.get_current_path()
    local target_dir, path_err = file_fs_path_from_page_path(current_path)
    if not target_dir then
      M.register_paste_keymap(paths, operation)
      lc.notify(path_err)
      return
    end

    local target_stat = lc.fs.stat(target_dir)
    if not target_stat.exists or not target_stat.is_dir then
      M.register_paste_keymap(paths, operation)
      lc.notify('Current page is not a directory: ' .. target_dir)
      return
    end

    local target_paths, target_err = validate_target_paths(target_dir, paths)
    if not target_paths then
      M.register_paste_keymap(paths, operation)
      lc.notify(target_err)
      return
    end

    local cmd = { operation == 'move' and 'mv' or 'cp' }
    if operation ~= 'move' then table.insert(cmd, '-R') end
    for _, source_path in ipairs(paths) do
      table.insert(cmd, source_path)
    end
    table.insert(cmd, target_dir)

    lc.system(cmd, function(out)
      if out.code == 0 then
        invalidate_source_caches(paths)
        clipboard_paths = {}
        clipboard_operation = nil
        if #paths == 1 then
          if operation == 'move' then
            lc.notify(('Moved %s -> %s'):format(paths[1], target_paths[1]))
          else
            lc.notify(('Copied %s -> %s'):format(paths[1], target_paths[1]))
          end
        else
          if operation == 'move' then
            lc.notify(('Moved %d entries to %s'):format(#paths, target_dir))
          else
            lc.notify(('Copied %d entries to %s'):format(#paths, target_dir))
          end
        end
        lc.cmd 'reload'
        return
      end

      M.register_paste_keymap(paths, operation)
      local err = tostring(out.stderr or ''):trim()
      if err == '' then err = 'exit code ' .. tostring(out.code) end
      lc.notify((operation == 'move' and 'Move failed: ' or 'Copy failed: ') .. err)
    end)
  end, {
    once = true,
    desc = desc,
  })
end

function M.is_selected(path)
  return path ~= nil and selected_paths[path] == true
end

function M.marker_color(path)
  if path == nil then return nil end
  if clipboard_paths[path] then
    if clipboard_operation == 'copy' then return 'green' end
    if clipboard_operation == 'move' then return 'red' end
  end
  if selected_paths[path] then return 'yellow' end
  return nil
end

function M.select_hovered_entry()
  local entry = lc.api.page_get_hovered()
  if not entry or not entry.path then
    lc.notify 'Nothing to select'
    return
  end

  if selected_paths[entry.path] then
    selected_paths[entry.path] = nil
  else
    selected_paths[entry.path] = true
  end
  lc.cmd 'reload'
  lc.cmd 'scroll_by 1'
end

function M.clear_selected()
  selected_paths = {}
end

local function prompt_create(kind)
  local target_dir = current_target_dir()
  if not target_dir then return end

  local is_dir = kind == 'dir'
  lc.input({
    prompt = is_dir and 'New directory name' or 'New file name',
    placeholder = is_dir and 'folder-name' or 'file.txt',
    on_submit = function(input)
      local name = tostring(input or ''):trim()
      if name == '' then
        lc.notify(is_dir and 'Directory name cannot be empty' or 'File name cannot be empty')
        return
      end
      if name:find('/', 1, true) then
        lc.notify('Name cannot contain /')
        return
      end

      local path = join_path(target_dir, name)
      local existing = lc.fs.stat(path)
      if existing.exists then
        lc.notify('Target already exists: ' .. path)
        return
      end

      if is_dir then
        local ok, err = lc.fs.mkdir(path)
        if not ok then
          lc.notify('Create directory failed: ' .. tostring(err or 'unknown error'))
          return
        end
        lc.notify('Created directory: ' .. path)
      else
        local ok, err = lc.fs.write_file_sync(path, '')
        if not ok then
          lc.notify('Create file failed: ' .. tostring(err or 'unknown error'))
          return
        end
        lc.notify('Created file: ' .. path)
      end

      lc.api.clear_page_cache(page_path_from_fs_path(target_dir))
      lc.cmd 'reload'
    end,
  })
end

function M.copy_hovered_entry()
  local source_paths = selected_or_hovered_paths()
  if not source_paths then
    lc.notify 'Nothing to copy'
    return
  end

  clipboard_paths = list_to_set(source_paths)
  clipboard_operation = 'copy'
  M.register_paste_keymap(source_paths, 'copy')
  M.clear_selected()
  lc.cmd 'reload'
  notify_multi_copy_ready(source_paths, config.get().keymap.paste)
end

function M.cut_hovered_entry()
  local source_paths = selected_or_hovered_paths()
  if not source_paths then
    lc.notify 'Nothing to cut'
    return
  end

  clipboard_paths = list_to_set(source_paths)
  clipboard_operation = 'move'
  M.register_paste_keymap(source_paths, 'move')
  M.clear_selected()
  lc.cmd 'reload'
  notify_multi_cut_ready(source_paths, config.get().keymap.paste)
end

function M.delete_hovered_entry()
  local source_paths = selected_or_hovered_paths()
  if not source_paths then
    lc.notify 'Nothing to delete'
    return
  end

  local prompt = #source_paths == 1
      and ('Delete "' .. basename(source_paths[1]) .. '"?')
    or ('Delete ' .. tostring(#source_paths) .. ' selected entries?')

  lc.confirm({
    title = 'Delete File',
    prompt = prompt,
    on_confirm = function()
      local errors = {}
      for _, path in ipairs(source_paths) do
        local ok, err = lc.fs.remove(path)
        if not ok then
          table.insert(errors, tostring(path) .. ': ' .. tostring(err or 'unknown error'))
        end
      end

      M.clear_selected()
      invalidate_source_caches(source_paths)
      lc.cmd 'reload'

      if #errors == 0 then
        if #source_paths == 1 then
          lc.notify('Deleted ' .. source_paths[1])
        else
          lc.notify(('Deleted %d entries'):format(#source_paths))
        end
        return
      end

      lc.notify('Delete failed: ' .. errors[1])
    end,
  })
end

function M.create_file()
  prompt_create 'file'
end

function M.create_dir()
  prompt_create 'dir'
end

return M
