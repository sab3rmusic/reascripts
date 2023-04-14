-- @description Grid Widget 2
-- @author Krisz Kosa
-- @version 2.0.2
-- @provides [main=main,midi_editor] .
-- @about Adds a widget to the arrangement and midi editor views that displays the current grid size
-- @changelog
--   # Check for js_ReaScriptAPI sooner


local widget_height = 40
local font_size = widget_height - 4

-- Check if js_ReaScriptAPI extension is installed
if not reaper.JS_Window_SetPosition then
  reaper.MB('Please install js_ReaScriptAPI extension', 'Error', 0)
  return
end

local arrange_view
local midi_view

local prev_arrange_view_width, prev_arrange_view_height, prev_midi_view_width, prev_midi_view_height
local prev_arrange_grid, prev_midi_grid

local os = reaper.GetOS()
local is_windows = os:match('Win')

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

-- https://github.com/reaper-oss/sws/blob/419b8fc467f6cb3cab66a55994f6f1536cb85d6e/Misc/Adam.cpp
function IsTriplet(division)
  if division < 1e-8 then
    return false
  end
  local n = 1 / division

  while n < 3 do
    n = n * 2
  end

  local r = n % 3
  return r < 0.000001 or r > 2.99999
end

function IsDotted(division)
  if division < 1e-8 then
    return false
  end
  local n = 1 / division

  while n < 2 / 3 do
    n = n * 2
  end
  while n > 4 / 3 do
    n = n / 2
  end

  local r = n % (2 / 3)
  return r < 0.000001 or r > 0.66666
end

function DrawLICE(bitmap, division, swing)
  local alpha = 0xFF000000
  local text_color = reaper.GetThemeColor('col_main_text', 0) | alpha

  local fractional = false
  local triplet = IsTriplet(division)
  local dotted = IsDotted(division)

  if triplet then
    division = division * 3 / 2
  elseif dotted then
    division = division * 2 / 3
  end

  if division < 1 then
    fractional = true
    division = 1 / division
  end

  local grid = 'error'
  local ok, err = pcall(function()
    if fractional and division > 1 then
      grid = string.format('1/%d', division)
    else
      grid = string.format('%d/1', division)
    end
  end)
  if not ok then
    print(err)
  end

  if triplet then
    grid = grid .. 'T'
  elseif dotted then
    grid = grid .. '.'
  end

  if swing ~= 0 then
    grid = grid .. string.format(' %+d%%', math.floor(swing * 100 + 0.5))
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

local force_midi_redraw = false

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
    force_midi_redraw = true
  end

  local _, arrange_view_width, arrange_view_height = reaper.JS_Window_GetClientSize(arrange_view)
  if arrange_view_width ~= prev_arrange_view_width or arrange_view_height ~= prev_arrange_view_height then
    prev_arrange_view_width = arrange_view_width
    prev_arrange_view_height = arrange_view_height

    a_bm_x = arrange_view_width - bm_w - 5
    a_bm_y = arrange_view_height - bm_h - 5

    reaper.JS_Composite(arrange_view, a_bm_x, a_bm_y, bm_w, bm_h, arrange_bitmap, 0, 0, bm_w, bm_h, false)
    reaper.JS_Window_InvalidateRect(arrange_view, 0, 0, arrange_view_width, arrange_view_height, false)
  end

  if midi_view then
    local _, midi_view_width, midi_view_height = reaper.JS_Window_GetClientSize(midi_view)
    if midi_view_width ~= prev_midi_view_width or midi_view_height ~= prev_midi_view_height or force_midi_redraw then
      prev_midi_view_width = midi_view_width
      prev_midi_view_height = midi_view_height

      m_bm_x = midi_view_width - bm_w - 5
      m_bm_y = midi_view_height - bm_h - 5

      reaper.JS_Composite(midi_view, m_bm_x, m_bm_y, bm_w, bm_h, midi_bitmap, 0, 0, bm_w, bm_h, false)
    end
  end

  local current_proj = reaper.EnumProjects(-1)
  local _, division, _, swing = reaper.GetSetProjectGrid(current_proj, false)

  local arrange_grid = Combine(division, swing)
  if arrange_grid ~= prev_arrange_grid then
    prev_arrange_grid = arrange_grid
    DrawLICE(arrange_bitmap, division, swing)
    reaper.JS_Window_InvalidateRect(arrange_view, a_bm_x, a_bm_y, a_bm_x + bm_w, a_bm_y + bm_h, false)
  end

  if midi_view then
    local take = reaper.MIDIEditor_GetTake(midi_hwnd)
    if reaper.ValidatePtr(take, 'MediaItem_Take*') then
      division, swing = reaper.MIDI_GetGrid(take)
      division = division / 4

      local midi_grid = Combine(division, swing)
      if midi_grid ~= prev_midi_grid or force_midi_redraw then
        prev_midi_grid = midi_grid
        DrawLICE(midi_bitmap, division, swing)
        reaper.JS_Window_InvalidateRect(midi_view, m_bm_x, m_bm_y, m_bm_x + bm_w, m_bm_y + bm_h, false)
        force_midi_redraw = false
      end
    end
  end

  -- Refresh window while playing
  if reaper.GetPlayState() == 1 then
    reaper.JS_Window_InvalidateRect(arrange_view, a_bm_x, a_bm_y, a_bm_x + bm_w, a_bm_y + bm_h, false)
    if midi_view then
      reaper.JS_Window_InvalidateRect(midi_view, m_bm_x, m_bm_y, m_bm_x + bm_w, m_bm_y + bm_h, false)
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
end

reaper.atexit(Quit)
reaper.defer(Main)
