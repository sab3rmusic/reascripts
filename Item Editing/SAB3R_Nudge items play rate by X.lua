-- @description Nudge Items Play Rate
-- @author Krisz Kosa
-- @version 1.0
-- @provides
--   [main] . > SAB3R_Nudge items play rate by +1 semitones.lua
--   [main] . > SAB3R_Nudge items play rate by -1 semitones.lua
--   [main] . > SAB3R_Nudge items play rate by +25 cents.lua
--   [main] . > SAB3R_Nudge items play rate by -25 cents.lua
-- @about Nudges all selected media items' play rate by the specified increment
-- @changelog
--   # Initial release

local script_name = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local increment = tonumber(string.match(script_name, "[%d.]+"))
if string.match(script_name, "-") then
  increment = increment * -1
end
if string.match(script_name, "cents") then
  increment = increment / 100.0
end

local count = reaper.CountSelectedMediaItems(0)
if count > 0 then
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(111)
  for i = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local take = reaper.GetActiveTake(item)
    local playRate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    -- Thanks SWS: https://github.com/reaper-oss/sws/blob/master/Misc/ItemParams.cpp#L324
    reaper.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 0)
    reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", playRate * 2^(1.0 / 12.0 * increment))
    reaper.UpdateItemInProject(item)
  end
  reaper.PreventUIRefresh(-111)
  local sign = string.match(script_name, "-") and "-" or "+"
  local unit = string.match(script_name, "cents") and " cents" or " semitones"
  reaper.Undo_EndBlock("Nudge items play rate " .. sign .. increment .. unit, -1)
else
  reaper.MB("No item selected!", "Error", 0)
end
