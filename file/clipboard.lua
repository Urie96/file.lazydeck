local M = {}

local state = {
  provider = nil,
  handles = {},
  operation = nil,
}

local function copy_list(items)
  local out = {}
  for i = 1, #items do
    out[i] = items[i]
  end
  return out
end

local function map_handles(handles)
  local out = {}
  for _, handle in ipairs(handles or {}) do
    out[handle.id] = handle
  end
  return out
end

function M.set(provider, handles, operation)
  state.provider = provider
  state.handles = copy_list(handles or {})
  state.operation = operation
end

function M.get()
  if not state.provider then return nil end
  return {
    provider = state.provider,
    handles = copy_list(state.handles),
    handles_map = map_handles(state.handles),
    operation = state.operation,
  }
end

function M.clear()
  state.provider = nil
  state.handles = {}
  state.operation = nil
end

function M.has()
  return state.provider ~= nil and #state.handles > 0
end

return M
