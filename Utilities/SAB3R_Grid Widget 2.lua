-- @description Grid Widget 2
-- @author Krisz Kosa
-- @version 2.2.0
-- @provides [main=main,midi_editor] .
-- @about Adds a widget to the arrangement and midi editor views that displays the current grid size
-- @changelog
--   # Alt-click widget to snap to lower right corner
--   # Support quintuplets and septuplets

local extname = 'SAB3R.GridWidget'
local widget_height = 40
local font_size = widget_height - 4

-- Check if js_ReaScriptAPI extension is installed
if not reaper.JS_Window_SetPosition then
  reaper.MB('Please install js_ReaScriptAPI extension', 'Error', 0)
  return
end

function EscapeString(str)
  local function EscapeChar(char)
    if char == ',' then return '\\,' end
    if char == ':' then return '\\:' end
    if char == '{' then return '\\[' end
    if char == '}' then return '\\]' end
    if char == '\\' then return '\\&' end
  end
  return str:gsub('[,:{}\\]', EscapeChar)
end

function UnEscapeString(str)
  local function UnEscapeChar(char)
    if char == ',' then return ',' end
    if char == ':' then return ':' end
    if char == '[' then return '{' end
    if char == ']' then return '}' end
    if char == '&' then return '\\' end
  end
  return str:gsub('\\([,:%[%]&])', UnEscapeChar)
end

function Serialize(value, add_newlines)
  local value_type = type(value)
  if value_type == 'string' then return 's:' .. EscapeString(value) end
  if value_type == 'number' then return 'n:' .. value end
  if value_type == 'boolean' then return 'b:' .. (value and 1 or 0) end
  if value_type == 'table' then
    local value_str = 't:{'
    local has_elems = false
    for key, elem in pairs(value) do
      if type(elem) ~= 'function' then
        -- Avoid adding protected elements that start with underscore
        local is_str_key = type(key) == 'string'
        if not is_str_key or key:sub(1, 1) ~= '_' then
          if is_str_key then key = EscapeString(key) end
          if not has_elems and add_newlines then
            value_str = value_str .. '\n'
          end
          local entry = Serialize(elem, add_newlines)
          value_str = value_str .. key .. ':' .. entry .. ','
          if add_newlines then value_str = value_str .. '\n' end
          has_elems = true
        end
      end
    end
    if has_elems then
      value_str = value_str:sub(1, -2)
      if add_newlines then value_str = value_str .. '\n' end
    end
    return value_str .. '}'
  end
  return ''
end

function Deserialize(value_str)
  local value_type, payload = value_str:sub(1, 1), value_str:sub(3)
  if value_type == 's' then return UnEscapeString(payload) end
  if value_type == 'n' then return tonumber(payload) end
  if value_type == 'b' then return payload == '1' end
  if value_type == 't' then
    local matches = {}
    local m = 0

    local function AddMatch(table_str)
      m = m + 1
      local match = {}
      local i = 1
      for value in (table_str .. ','):gmatch('(.-[^\\]),\r?\n?') do
        match[i] = value
        i = i + 1
      end
      matches[m] = match
      return m
    end

    local _, bracket_cnt = payload:gsub('{', '')
    for _ = 1, bracket_cnt do
      payload = payload:gsub('{\r?\n?([^{}]*)\r?\n?}', AddMatch, 1)
    end

    local function AssembleTable(match)
      local ret = {}
      for _, elem in ipairs(match) do
        local key, value = elem:match('^(.-[^\\]):(.-)$')
        key = tonumber(key) or UnEscapeString(key)
        if value:sub(1, 1) == 't' then
          local n = tonumber(value:match('^t:(.-)$'))
          ret[key] = AssembleTable(matches[n])
        else
          ret[key] = Deserialize(value)
        end
      end
      return ret
    end
    return AssembleTable(matches[m])
  end
end

function ExtSave(key, value, is_temporary)
  local value_str = Serialize(value)
  if not value_str then return end
  reaper.SetExtState(extname, key, value_str, not is_temporary)
end

function ExtLoad(key, default)
  local value = default
  local value_str = reaper.GetExtState(extname, key)
  if value_str ~= '' then value = Deserialize(value_str) end
  return value
end

local settings = ExtLoad('settings', {})

local arrange_view
local midi_view

local prev_arrange_grid, prev_midi_grid

local os = reaper.GetOS()
local is_windows = os:match('Win')
local is_linux = os:match('Other')

local lice_font = reaper.JS_LICE_CreateFont()

local gdi = reaper.JS_GDI_CreateFont(font_size, 0, 0, 0, 0, 0, 'Verdana')
reaper.JS_LICE_SetFontFromGDI(lice_font, gdi, '')
reaper.JS_GDI_DeleteObject(gdi)

local bm_h = widget_height
gfx.setfont(1, 'Verdana', font_size)
local bm_w = gfx.measurestr('1/32768 + 22%') + 4 -- measure width of widget in worst case scenario

local arrange_bitmap = reaper.JS_LICE_CreateBitmap(true, bm_w, bm_h)
local midi_bitmap = reaper.JS_LICE_CreateBitmap(true, bm_w, bm_h)

local a_bm_x, a_bm_y, m_bm_x, m_bm_y

local _, _, sec, cmd = reaper.get_action_context()

function print(msg)
  reaper.ShowConsoleMsg(tostring(msg) .. '\n')
end

local drag_x
local drag_y

local is_left_click = false
local is_right_click = false

local menu_time

local normal_cursor = reaper.JS_Mouse_LoadCursor(is_windows and 32512 or 0)
local diag1_resize_cursor = reaper.JS_Mouse_LoadCursor(is_linux and 32642 or 32643)
local diag2_resize_cursor = reaper.JS_Mouse_LoadCursor(is_linux and 32643 or 32642)
local horz_resize_cursor = reaper.JS_Mouse_LoadCursor(32644)
local vert_resize_cursor = reaper.JS_Mouse_LoadCursor(32645)
local move_cursor = reaper.JS_Mouse_LoadCursor(32646)

local Intercept = reaper.JS_WindowMessage_Intercept
local Release = reaper.JS_WindowMessage_Release
local Peek = reaper.JS_WindowMessage_Peek

local prev_cursor = normal_cursor
local is_intercept = false

local intercepts = {
  { timestamp = 0, passthrough = false, message = 'WM_SETCURSOR' },
  { timestamp = 0, passthrough = false, message = 'WM_LBUTTONDOWN' },
  { timestamp = 0, passthrough = false, message = 'WM_LBUTTONUP' },
  { timestamp = 0, passthrough = false, message = 'WM_RBUTTONDOWN' },
  { timestamp = 0, passthrough = false, message = 'WM_RBUTTONUP' },
  { timestamp = 0, passthrough = false, message = 'WM_MOUSEWHEEL' },
}

function SetCursor(cursor)
  reaper.JS_Mouse_SetCursor(cursor)
  prev_cursor = cursor
end

function StartIntercepts(hwnd)
  if is_intercept then return end
  is_intercept = true
  for _, intercept in ipairs(intercepts) do
    Intercept(hwnd, intercept.message, intercept.passthrough)
  end
end

function EndIntercepts(hwnd)
  if not is_intercept then return end
  is_intercept = false
  for _, intercept in ipairs(intercepts) do
    Release(hwnd, intercept.message)
    intercept.timestamp = 0
  end

  if prev_cursor ~= normal_cursor then
    reaper.JS_Mouse_SetCursor(normal_cursor)
  end
  prev_cursor = -1
end

function PeekIntercepts(hwnd, m_x, m_y)
  for _, intercept in ipairs(intercepts) do
    local msg = intercept.message
    local ret, _, time, _, _ = Peek(hwnd, msg)

    if ret and time ~= intercept.timestamp then
      intercept.timestamp = time

      if msg == 'WM_LBUTTONDOWN' then
        -- Avoid new clicks after showing menu
        if menu_time and reaper.time_precise() < menu_time + 0.05 then
          return
        end
        is_left_click = true
        drag_x = m_x
        drag_y = m_y
      end

      if msg == 'WM_LBUTTONUP' then
        if not is_left_click then return end
        if reaper.JS_Mouse_GetState(16) == 16 then
          settings.draggable = not settings.draggable
          -- Force position recalculation
          local _, a_w, a_h = reaper.JS_Window_GetClientSize(arrange_view)
          CalculateDefaultPosition(a_w, a_h, 'arrange')
          if midi_view then
            local _, m_w, m_h = reaper.JS_Window_GetClientSize(midi_view)
            CalculateDefaultPosition(a_w, a_h, 'midi')
          end
          ExtSave('settings', settings)
        end
      end
    end
  end
end

-- from https://stackoverflow.com/a/43572223
local function ToFraction(num)
  local W = math.floor(num)
  local F = num - W
  local pn, n, N = 0, 1, nil
  local pd, d, D = 1, 0, nil
  local x, err, q, Q
  repeat
    x = x and 1 / (x - q) or F
    q, Q = math.floor(x), math.floor(x + 0.5)
    pn, n, N = n, q * n + pn, Q * n + pn
    pd, d, D = d, q * d + pd, Q * d + pd
    err = F - N / D
  until math.abs(err) < 1e-15
  return N + D * W, D
end

function DrawLICE(bitmap, division, swing)
  local alpha = 0xFF000000
  local text_color = reaper.GetThemeColor('col_main_text', 0) | alpha

  local num, denom = ToFraction(division)

  local is_triplet, is_quintuplet, is_septuplet, is_dotted
  if division > 1 then
    is_triplet = 2 * division % (2 / 3) == 0
    is_quintuplet = 4 * division % (4 / 5) == 0
    is_septuplet = 4 * division % (4 / 7) == 0
    is_dotted = 2 * division % 3 == 0
  else
    is_triplet = 2 / division % 3 == 0
    is_quintuplet = 4 / division % 5 == 0
    is_septuplet = 4 / division % 7 == 0
    is_dotted = 2 / division % (2 / 3) == 0
  end

  local suffix = ''
  if is_triplet then
    suffix = 'T'
    denom = denom * 2 / 3
  elseif is_quintuplet then
    suffix = 'Q'
    denom = denom * 4 / 5
  elseif is_septuplet then
    suffix = 'S'
    denom = denom * 4 / 7
  elseif is_dotted then
    suffix = 'D'
    denom = denom / 2
    num = num / 3
  end

  -- Simplify fractions, e.g. 2/4 to 1/2
  if num > 1 then
    local rest = denom % num
    if rest == 0 then
      denom = denom / num
      num = 1
    end
  end

  local grid
  if num >= denom and num % denom == 0 then
    grid = ('%.0f/1%s'):format(num / denom, suffix)
  else
    grid = ('%.0f/%.0f%s'):format(num, denom, suffix)
  end

  reaper.JS_LICE_Clear(bitmap, 0)
  -- Draw Text
  gfx.setfont(1, 'Verdana', font_size)
  local text_w, text_h = gfx.measurestr(grid)
  local text_x = bm_w - text_w
  local text_y = bm_h - text_h

  reaper.JS_LICE_FillRect(bitmap, text_x - 2, text_y - 2, bm_w, bm_h, 0x77000000, 1, "HSVADJ ALPHA")

  local len = grid:len()
  reaper.JS_LICE_SetFontColor(lice_font, text_color)
  reaper.JS_LICE_DrawText(bitmap, lice_font, grid, len, text_x - 1, text_y - 3, bm_w, bm_h)
  --reaper.JS_LICE_FillRect(bitmap, text_x + 2, text_y + 2, text_w, bm_h, 0x77FFFFFF, 1, "HSVADJ ALPHA")

  if is_windows then
    --reaper.JS_LICE_ProcessRect(bitmap, text_x, text_y, bm_w, bm_h, "ALPHAMUL", 0)
  end
end

local function Combine(...)
  local out = ''
  for _, v in ipairs({ ... }) do
    out = out .. tostring(v)
  end
  return out
end

local previous_size = {}
function IsResized(width, height, key)
  if not previous_size[key] then
    return true
  end
  local resized = width ~= previous_size[key].width or height ~= previous_size[key].height
  if resized then
    previous_size[key].width = width
    previous_size[key].height = height
  end
  return resized
end

local previous_position = {}
function ReturnToPosition(width, height, key)
  if not previous_position[key] then
    previous_position[key] = {}
  end
  local previous = previous_position[key][Combine(width, 'x', height)]
  -- don't reposition if dragging or has no previous position
  if not previous or drag_x then
    return
  end
  settings[key .. '_bm_x'] = previous.x
  settings[key .. '_bm_y'] = previous.y
end

function EnsureBitmapVisible(width, height, key)
  settings[key .. '_bm_x'] = math.max(0, math.min(width - bm_w, settings[key .. '_bm_x']))
  settings[key .. '_bm_y'] = math.max(0, math.min(height - bm_h, settings[key .. '_bm_y']))
end

function CalculateDefaultPosition(width, height, key)
  settings[key .. '_bm_x'] = width - bm_w - 5
  settings[key .. '_bm_y'] = height - bm_h - 5
  ExtSave('settings', settings)
end

function HandleDrag(hwnd, width, height, key)
  local x, y = reaper.GetMousePosition()
  local m_x, m_y = reaper.JS_Window_ScreenToClient(hwnd, x, y)
  local is_hovered = m_x > settings[key .. '_bm_x'] and m_y > settings[key .. '_bm_y'] and
      m_x < settings[key .. '_bm_x'] + bm_w and
      m_y < settings[key .. '_bm_y'] + bm_h

  if is_hovered then
    if settings.draggable and drag_x and (drag_x ~= m_x or drag_y ~= m_y) then
      -- Move window
      local new_bm_x = settings[key .. '_bm_x'] + m_x - drag_x
      local new_bm_y = settings[key .. '_bm_y'] + m_y - drag_y
      settings[key .. '_bm_x'] = new_bm_x
      settings[key .. '_bm_y'] = new_bm_y
      if m_x > 0 and m_y > 0 and m_x < width and m_y < height then
        SetCursor(move_cursor)
      end
      drag_x = m_x
      drag_y = m_y
      is_left_click = false
    end
    StartIntercepts(hwnd)
    PeekIntercepts(hwnd, m_x, m_y)
  else
    EndIntercepts(hwnd)
  end

  -- Release drags / left clicks / right clicks
  local is_moved = false
  if is_left_click or is_right_click or drag_x then
    local mouse_state = reaper.JS_Mouse_GetState(3)
    if mouse_state == 0 then
      if drag_x then
        previous_position[key][Combine(width, 'x', height)] = {
          x = settings[key .. '_bm_x'],
          y = settings[key .. '_bm_y']
        }
        ExtSave('settings', settings)
        is_moved = true
      end
      drag_x = nil
      drag_y = nil
      is_left_click = false
      is_right_click = false
      SetCursor(normal_cursor)
    end
  end
  return is_moved
end

function Main()
  local main_hwnd = reaper.GetMainHwnd()
  if not arrange_view then
    arrange_view = reaper.JS_Window_FindChildByID(main_hwnd, 1000)
  end

  local midi_hwnd = reaper.MIDIEditor_GetActive()
  -- validate the pointer to make sure the midi view is open
  if not reaper.ValidatePtr(midi_hwnd, 'HWND*') then
    midi_view = nil
  else
    midi_view = reaper.JS_Window_FindChildByID(midi_hwnd, 1001)
  end

  local _, a_w, a_h = reaper.JS_Window_GetClientSize(arrange_view)
  local _, m_w, m_h = reaper.JS_Window_GetClientSize(midi_view)

  local a_resized = IsResized(a_w, a_h, 'arrange')
  local m_resized = IsResized(m_w, m_h, 'midi')

  if a_resized and not settings.draggable or not settings.arrange_bm_x then
    CalculateDefaultPosition(a_w, a_h, 'arrange')
  end
  if m_resized and not settings.draggable or midi_view and not settings.midi_bm_x then
    CalculateDefaultPosition(m_w, m_h, 'midi')
  end

  local a_moved = false
  local m_moved = false
  if midi_view then
    -- only intercept mouse events for one view at a time
    m_moved = HandleDrag(midi_view, m_w, m_h, 'midi')
  else
    a_moved = HandleDrag(arrange_view, a_w, a_h, 'arrange')
  end

  if a_moved or a_resized then
    ReturnToPosition(a_w, a_h, 'arrange')
    EnsureBitmapVisible(a_w, a_h, 'arrange')
    reaper.JS_Composite_Delay(arrange_view, 0.03, 0.03, 2)
    reaper.JS_Composite(arrange_view, settings.arrange_bm_x, settings.arrange_bm_y, bm_w, bm_h, arrange_bitmap, 0, 0,
      bm_w, bm_h, false)
    reaper.JS_Window_InvalidateRect(arrange_view, 0, 0, a_w, a_h, false)
  end

  if midi_view and (m_moved or m_resized) then
    ReturnToPosition(m_w, m_h, 'midi')
    EnsureBitmapVisible(m_w, m_h, 'midi')
    reaper.JS_Composite_Delay(midi_view, 0.03, 0.03, 2)
    reaper.JS_Composite(midi_view, settings.midi_bm_x, settings.midi_bm_y, bm_w, bm_h, midi_bitmap, 0, 0, bm_w, bm_h,
      false)
    reaper.JS_Window_InvalidateRect(midi_view, 0, 0, m_w, m_h, false)
  end

  local current_proj = reaper.EnumProjects(-1)
  local _, division, _, swing = reaper.GetSetProjectGrid(current_proj, false)

  local arrange_grid = Combine(division, swing)
  if arrange_grid ~= prev_arrange_grid then
    prev_arrange_grid = arrange_grid
    DrawLICE(arrange_bitmap, division, swing)
    reaper.JS_Window_InvalidateRect(arrange_view, settings.arrange_bm_x - 100, settings.arrange_bm_y,
      settings.arrange_bm_x + bm_w, settings.arrange_bm_y + bm_h, false)
  end

  if midi_view then
    local take = reaper.MIDIEditor_GetTake(midi_hwnd)
    if reaper.ValidatePtr(take, 'MediaItem_Take*') then
      division, swing = reaper.MIDI_GetGrid(take)
      division = division / 4

      local midi_grid = Combine(division, swing)
      if midi_grid ~= prev_midi_grid then
        prev_midi_grid = midi_grid
        DrawLICE(midi_bitmap, division, swing)
        reaper.JS_Window_InvalidateRect(midi_view, settings.midi_bm_x - 100, settings.midi_bm_y,
          settings.midi_bm_x + bm_w, settings.midi_bm_y + bm_h, false)
      end
    end
  end

  -- Refresh window while playing
  if reaper.GetPlayState() == 1 then
    reaper.JS_Window_InvalidateRect(arrange_view, settings.arrange_bm_x - 100, settings.arrange_bm_y,
      settings.arrange_bm_x + bm_w, settings.arrange_bm_y + bm_h, false)
    if midi_view then
      reaper.JS_Window_InvalidateRect(midi_view, settings.midi_bm_x - 100, settings.midi_bm_y, settings.midi_bm_x + bm_w,
        settings.midi_bm_y + bm_h, false)
    end
  end

  reaper.defer(Main)
end

reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)

function Quit()
  reaper.SetToggleCommandState(sec, cmd, 0)
  reaper.RefreshToolbar2(sec, cmd)
  reaper.JS_LICE_DestroyBitmap(arrange_bitmap)
  reaper.JS_LICE_DestroyBitmap(midi_bitmap)
  reaper.JS_LICE_DestroyFont(lice_font)

  EndIntercepts(arrange_view)
end

reaper.atexit(Quit)
reaper.defer(Main)
