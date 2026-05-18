local Clipboard = require 'file.clipboard'

local M = {}

local function copy_list(items)
  local out = {}
  for i = 1, #items do
    out[i] = items[i]
  end
  return out
end

local function sorted_values(map)
  local out = {}
  for _, value in pairs(map) do
    table.insert(out, value)
  end
  table.sort(out, function(a, b)
    return tostring(a.id or '') < tostring(b.id or '')
  end)
  return out
end

local function basename(handle)
  if type(handle) ~= 'table' then return '' end
  return tostring(handle.name or handle.path or handle.id or '')
end

function M.new(browser)
  local self = {
    browser = browser,
    selected_handles = {},
  }
  return setmetatable(self, { __index = M })
end

function M:clear_selected()
  self.selected_handles = {}
end

function M:selected_or_hovered_handles()
  local handles = sorted_values(self.selected_handles)
  if #handles > 0 then return handles end

  local entry = deck.api.get_hovered()
  if not entry or not entry.handle then return nil end
  return { entry.handle }
end

function M:marker_color(handle)
  local id = handle and handle.id
  if not id then return nil end
  local clip = Clipboard.get()
  if clip and clip.provider == self.browser.provider and clip.handles_map[id] then
    if clip.operation == 'copy' then return 'green' end
    if clip.operation == 'move' then return 'red' end
  end
  if self.selected_handles[id] then return 'yellow' end
  return nil
end

function M:toggle_hidden()
  self.browser.config.show_hidden = not self.browser.config.show_hidden
  self.browser:refresh_current_page()
  return self.browser.config.show_hidden
end

function M:invalidate_provider_caches(provider, handles)
  local seen = {}
  for _, handle in ipairs(handles or {}) do
    local parent = provider:parent(handle)
    if parent and not seen[parent.id] then
      seen[parent.id] = true
      deck.api.clear_page_cache(provider:encode_page_path(parent))
    end
  end
end

function M:invalidate_parent_caches(handles)
  self:invalidate_provider_caches(self.browser.provider, handles)
end

function M:current_target_dir(cb)
  local current_path = deck.api.get_current_path()
  local dir_handle, err = self.browser.provider:decode_page_path(current_path)
  if not dir_handle then
    deck.notify(err)
    cb(nil)
    return
  end

  self.browser.provider:stat(dir_handle, function(stat, stat_err)
    if stat_err then
      deck.notify('Failed to access directory: ' .. tostring(stat_err))
      cb(nil)
      return
    end
    if not stat.exists or not stat.is_dir then
      deck.notify('Current page is not a directory: ' .. tostring(dir_handle.path or dir_handle.id))
      cb(nil)
      return
    end
    cb(dir_handle)
  end)
end

local function notify_transfer_success(operation, handles, target_dir, result)
  local targets = result and result.targets or {}
  if #handles == 1 then
    local target = targets[1]
    local target_path = target and (target.path or target.id) or (target_dir.path or target_dir.id)
    if operation == 'move' then
      deck.notify(('Moved %s -> %s'):format(handles[1].path or handles[1].id, target_path))
    else
      deck.notify(('Copied %s -> %s'):format(handles[1].path or handles[1].id, target_path))
    end
  else
    if operation == 'move' then
      deck.notify(('Moved %d entries to %s'):format(#handles, target_dir.path or target_dir.id))
    else
      deck.notify(('Copied %d entries to %s'):format(#handles, target_dir.path or target_dir.id))
    end
  end
end

function M:run_paste(clip, target_dir, done)
  local source_provider = clip.provider
  local target_provider = self.browser.provider
  local handles = copy_list(clip.handles or {})
  local operation = clip.operation == 'move' and 'move' or 'copy'

  if source_provider == target_provider then
    local fn = operation == 'move' and target_provider.move or target_provider.copy
    return fn(target_provider, handles, target_dir, done)
  end

  if operation == 'move' then
    done(false, 'cross-provider move is not supported')
    return
  end

  if source_provider.name == 'local' and type(target_provider.upload) == 'function' then
    return target_provider:upload({ provider = source_provider, handles = handles, operation = operation }, target_dir, done)
  end

  if target_provider.name == 'local' and type(source_provider.download) == 'function' then
    return source_provider:download({ provider = source_provider, handles = handles, operation = operation }, target_dir, done)
  end

  done(false, 'cross-provider paste is not supported between '
    .. tostring(source_provider.name or 'unknown') .. ' and ' .. tostring(target_provider.name or 'unknown'))
end

function M:paste_from_clipboard()
  local clip = Clipboard.get()
  if not clip then
    deck.notify 'Nothing to paste'
    return
  end

  self:current_target_dir(function(target_dir)
    if not target_dir then return end

    self:run_paste(clip, target_dir, function(ok, err, result)
      if ok then
        self:invalidate_provider_caches(clip.provider, clip.handles)
        Clipboard.clear()
        notify_transfer_success(clip.operation, clip.handles, target_dir, result)
        self.browser:refresh_current_page()
        return
      end

      deck.notify((clip.operation == 'move' and 'Move failed: ' or 'Copy failed: ') .. tostring(err or 'unknown error'))
    end)
  end)
end

function M:select_hovered_entry()
  local entry = deck.api.get_hovered()
  if not entry or not entry.handle then
    deck.notify 'Nothing to select'
    return
  end

  local id = entry.handle.id
  if self.selected_handles[id] then
    self.selected_handles[id] = nil
  else
    self.selected_handles[id] = entry.handle
  end
  self.browser:refresh_current_page(function()
    deck.cmd 'scroll_by 1'
  end)
end

function M:edit_hovered_entry()
  local entry = deck.api.get_hovered()
  if not entry or not entry.handle then
    deck.notify 'Nothing to edit'
    return
  end
  if entry.handle.is_dir then
    deck.notify 'Cannot edit a directory'
    return
  end
  if type(self.browser.provider.edit) ~= 'function' then
    deck.notify('Edit is not supported by provider ' .. tostring(self.browser.provider.name or 'unknown'))
    return
  end
  self.browser.provider:edit(entry.handle)
end

function M:rename_hovered_entry()
  local entry = deck.api.get_hovered()
  if not entry or not entry.handle then
    deck.notify 'Nothing to rename'
    return
  end
  if type(self.browser.provider.rename) ~= 'function' then
    deck.notify('Rename is not supported by provider ' .. tostring(self.browser.provider.name or 'unknown'))
    return
  end

  local old_handle = entry.handle
  deck.input {
    prompt = 'Rename',
    placeholder = old_handle.name,
    value = old_handle.name,
    on_submit = function(input)
      local name = tostring(input or ''):trim()
      if name == '' then
        deck.notify 'Name cannot be empty'
        return
      end
      if name == old_handle.name then return end
      if name:find('/', 1, true) then
        deck.notify 'Name cannot contain /'
        return
      end

      self.browser.provider:rename(old_handle, name, function(ok, err, result)
        if not ok then
          deck.notify('Rename failed: ' .. tostring(err or 'unknown error'))
          return
        end

        local parent = self.browser.provider:parent(old_handle)
        if parent then
          deck.api.clear_page_cache(self.browser.provider:encode_page_path(parent))
        end

        local target = result and result.target or self.browser.provider:join(parent or old_handle, name)
        deck.notify(('Renamed %s -> %s'):format(old_handle.path or old_handle.id, target.path or target.id))
        self.browser:refresh_current_page(function()
          deck.api.set_hovered(self.browser.provider:encode_page_path(target))
        end)
      end)
    end,
  }
end

local function prompt_create(self, kind)
  self:current_target_dir(function(target_dir)
    if not target_dir then return end

    local is_dir = kind == 'dir'
    deck.input({
      prompt = is_dir and 'New directory name' or 'New file name',
      placeholder = is_dir and 'folder-name' or 'file.txt',
      on_submit = function(input)
        local name = tostring(input or ''):trim()
        if name == '' then
          deck.notify(is_dir and 'Directory name cannot be empty' or 'File name cannot be empty')
          return
        end
        if name:find('/', 1, true) then
          deck.notify('Name cannot contain /')
          return
        end

        local fn = is_dir and self.browser.provider.create_dir or self.browser.provider.create_file
        fn(self.browser.provider, target_dir, name, function(ok, err)
          if not ok then
            if is_dir then
              deck.notify('Create directory failed: ' .. tostring(err or 'unknown error'))
            else
              deck.notify('Create file failed: ' .. tostring(err or 'unknown error'))
            end
            return
          end

          local target = self.browser.provider:join(target_dir, name)
          deck.notify((is_dir and 'Created directory: ' or 'Created file: ')
            .. tostring(target.path))
          deck.api.clear_page_cache(self.browser.provider:encode_page_path(target_dir))
          self.browser:refresh_current_page(function()
            deck.api.set_hovered(self.browser.provider:encode_page_path(target))
          end)
        end)
      end,
    })
  end)
end

function M:yank_hovered_entry()
  local source_handles = self:selected_or_hovered_handles()
  if not source_handles then
    deck.notify 'Nothing to yank'
    return
  end

  Clipboard.set(self.browser.provider, source_handles, 'copy')
  self:clear_selected()
  self.browser:refresh_current_page()

  if #source_handles == 1 then
    deck.notify(('Yanked %s. Press %s to paste'):format(source_handles[1].path or source_handles[1].id, self.browser.config.keymap.paste))
  else
    deck.notify(('Yanked %d entries. Press %s to paste'):format(#source_handles, self.browser.config.keymap.paste))
  end
end

function M:cut_hovered_entry()
  local source_handles = self:selected_or_hovered_handles()
  if not source_handles then
    deck.notify 'Nothing to cut'
    return
  end

  Clipboard.set(self.browser.provider, source_handles, 'move')
  self:clear_selected()
  self.browser:refresh_current_page()

  if #source_handles == 1 then
    deck.notify(('Cut %s. Press %s to paste'):format(source_handles[1].path or source_handles[1].id, self.browser.config.keymap.paste))
  else
    deck.notify(('Cut %d entries. Press %s to paste'):format(#source_handles, self.browser.config.keymap.paste))
  end
end

function M:delete_hovered_entry()
  local source_handles = self:selected_or_hovered_handles()
  if not source_handles then
    deck.notify 'Nothing to delete'
    return
  end

  local prompt = #source_handles == 1
      and ('Delete "' .. basename(source_handles[1]) .. '"?')
    or ('Delete ' .. tostring(#source_handles) .. ' selected entries?')

  deck.confirm({
    title = 'Delete File',
    prompt = prompt,
    on_confirm = function()
      self.browser.provider:remove(source_handles, function(ok, err)
        self:clear_selected()
        self:invalidate_parent_caches(source_handles)
        self.browser:refresh_current_page()

        if ok then
          if #source_handles == 1 then
            deck.notify('Deleted ' .. (source_handles[1].path or source_handles[1].id))
          else
            deck.notify(('Deleted %d entries'):format(#source_handles))
          end
          return
        end

        deck.notify('Delete failed: ' .. tostring(err or 'unknown error'))
      end)
    end,
  })
end

function M:create_file()
  prompt_create(self, 'file')
end

function M:create_dir()
  prompt_create(self, 'dir')
end

return M
