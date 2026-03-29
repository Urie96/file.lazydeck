local M = {}

local cfg = {
  preview_max_chars = 3000,
  show_hidden = false,
  keymap = {
    new_file = 'n',
    new_dir = 'N',
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

local function normalize(next_cfg)
  local out = lc.tbl_extend('force', {}, next_cfg or {})
  out.preview_max_chars = math.max(tonumber(out.preview_max_chars) or cfg.preview_max_chars, 1024)
  out.show_hidden = out.show_hidden == true
  out.keymap = out.keymap or {}
  out.keymap.new_file = trim(out.keymap.new_file) or cfg.keymap.new_file
  out.keymap.new_dir = trim(out.keymap.new_dir) or cfg.keymap.new_dir
  out.keymap.select = trim(out.keymap.select) or cfg.keymap.select
  out.keymap.toggle_hidden = trim(out.keymap.toggle_hidden) or cfg.keymap.toggle_hidden
  out.keymap.yank = trim(out.keymap.yank) or cfg.keymap.yank
  out.keymap.cut = trim(out.keymap.cut) or cfg.keymap.cut
  out.keymap.delete = trim(out.keymap.delete) or cfg.keymap.delete
  out.keymap.paste = trim(out.keymap.paste) or cfg.keymap.paste
  return out
end

function M.setup(opt)
  local global_keymap = (lc.config.get() or {}).keymap or {}
  cfg = normalize(lc.tbl_deep_extend('force', cfg, { keymap = global_keymap }, opt or {}))
  require('file.metas').setup(cfg)
end

function M.get() return cfg end

function M.toggle_hidden()
  cfg.show_hidden = not cfg.show_hidden
  return cfg.show_hidden
end

return M
