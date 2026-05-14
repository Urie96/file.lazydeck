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

local function list_to_map(items)
  local out = {}
  for _, item in ipairs(items or {}) do
    out[item.id] = item
  end
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
    clipboard_handles = {},
    clipboard_operation = nil,
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
  if self.clipboard_handles[id] then
    if self.clipboard_operation == 'copy' then return 'green' end
    if self.clipboard_operation == 'move' then return 'red' end
  end
  if self.selected_handles[id] then return 'yellow' end
  return nil
end

function M:toggle_hidden()
  self.browser.config.show_hidden = not self.browser.config.show_hidden
  self.browser:refresh_current_page()
  return self.browser.config.show_hidden
end

function M:invalidate_parent_caches(handles)
  local seen = {}
  for _, handle in ipairs(handles or {}) do
    local parent = self.browser.provider:parent(handle)
    if parent and not seen[parent.id] then
      seen[parent.id] = true
      deck.api.clear_page_cache(self.browser.provider:encode_page_path(parent))
    end
  end
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

function M:register_paste_keymap(source_handles, operation)
  local paste_key = self.browser.config.keymap.paste
  if not paste_key or paste_key == '' then return end

  local handles = copy_list(source_handles)
  local action = operation == 'move' and 'move' or 'paste'
  local desc = #handles == 1 and (action .. ' ' .. basename(handles[1]))
    or ((operation == 'move' and 'move ' or 'paste ') .. tostring(#handles) .. ' entries')

  deck.keymap.set('main', paste_key, function()
    self:current_target_dir(function(target_dir)
      if not target_dir then
        self:register_paste_keymap(handles, operation)
        return
      end

      local fn = operation == 'move' and self.browser.provider.move or self.browser.provider.copy
      fn(self.browser.provider, handles, target_dir, function(ok, err, result)
        if ok then
          self:invalidate_parent_caches(handles)
          self.clipboard_handles = {}
          self.clipboard_operation = nil

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
          self.browser:refresh_current_page()
          return
        end

        self:register_paste_keymap(handles, operation)
        deck.notify((operation == 'move' and 'Move failed: ' or 'Copy failed: ') .. tostring(err or 'unknown error'))
      end)
    end)
  end, {
    once = true,
    desc = desc,
  })
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

function M:copy_hovered_entry()
  local source_handles = self:selected_or_hovered_handles()
  if not source_handles then
    deck.notify 'Nothing to copy'
    return
  end

  self.clipboard_handles = list_to_map(source_handles)
  self.clipboard_operation = 'copy'
  self:register_paste_keymap(source_handles, 'copy')
  self:clear_selected()
  self.browser:refresh_current_page()

  if #source_handles == 1 then
    deck.notify(('Copied %s. Press %s to paste'):format(source_handles[1].path or source_handles[1].id, self.browser.config.keymap.paste))
  else
    deck.notify(('Copied %d entries. Press %s to paste'):format(#source_handles, self.browser.config.keymap.paste))
  end
end

function M:cut_hovered_entry()
  local source_handles = self:selected_or_hovered_handles()
  if not source_handles then
    deck.notify 'Nothing to cut'
    return
  end

  self.clipboard_handles = list_to_map(source_handles)
  self.clipboard_operation = 'move'
  self:register_paste_keymap(source_handles, 'move')
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
