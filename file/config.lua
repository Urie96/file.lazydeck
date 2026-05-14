local M = {}

local defaults = {
  preview_max_chars = 3000,
  preview_debounce_ms = 0,
  preview_mode = 'full',
  show_hidden = false,
  keymap = {
    new_file = 'n',
    new_dir = 'N',
    edit = 'e',
    rename = 'r',
    select = '<space>',
    toggle_hidden = '.',
    yank = 'yy',
    cut = 'xx',
    delete = 'dd',
    paste = 'p',
  },
}

local function trim(s)
  if s == nil then return nil end
  return tostring(s):match '^%s*(.-)%s*$'
end

local function normalize_key(value, default)
  if value == false then return false end
  return trim(value) or default
end

local function normalize(next_cfg)
  local out = deck.tbl_extend('force', {}, next_cfg or {})
  out.preview_max_chars = math.max(tonumber(out.preview_max_chars) or defaults.preview_max_chars, 1024)
  out.preview_debounce_ms = math.max(tonumber(out.preview_debounce_ms) or defaults.preview_debounce_ms, 0)
  out.preview_mode = tostring(out.preview_mode or defaults.preview_mode)
  if out.preview_mode ~= 'full' and out.preview_mode ~= 'file-only' then
    out.preview_mode = defaults.preview_mode
  end
  out.show_hidden = out.show_hidden == true
  out.keymap = out.keymap or {}
  out.keymap.new_file = normalize_key(out.keymap.new_file, defaults.keymap.new_file)
  out.keymap.new_dir = normalize_key(out.keymap.new_dir, defaults.keymap.new_dir)
  out.keymap.edit = normalize_key(out.keymap.edit, defaults.keymap.edit)
  out.keymap.rename = normalize_key(out.keymap.rename, defaults.keymap.rename)
  out.keymap.select = normalize_key(out.keymap.select, defaults.keymap.select)
  out.keymap.toggle_hidden = normalize_key(out.keymap.toggle_hidden, defaults.keymap.toggle_hidden)
  out.keymap.yank = normalize_key(out.keymap.yank, defaults.keymap.yank)
  out.keymap.cut = normalize_key(out.keymap.cut, defaults.keymap.cut)
  out.keymap.delete = normalize_key(out.keymap.delete, defaults.keymap.delete)
  out.keymap.paste = normalize_key(out.keymap.paste, defaults.keymap.paste)
  return out
end

function M.new(opt)
  local global_keymap = (deck.config.get() or {}).keymap or {}
  return normalize(deck.tbl_deep_extend('force', defaults, { keymap = global_keymap }, opt or {}))
end

return M
