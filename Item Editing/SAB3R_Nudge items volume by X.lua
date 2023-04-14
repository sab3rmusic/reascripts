-- @description Nudge Items Volume
-- @author Krisz Kosa
-- @version 1.0
-- @provides
--   [main] . > SAB3R_Nudge items volume by +1.5 decibels.lua
--   [main] . > SAB3R_Nudge items volume by -1.5 decibels.lua
--   [main] . > SAB3R_Nudge items volume by +0.25 decibels.lua
--   [main] . > SAB3R_Nudge items volume by -0.25 decibels.lua
-- @about Nudges all selected media items' volume by the specified increment
-- @changelog
--   # Initial release

local script_name = ({reaper.get_action_context()})[2]:match("([^/\\_]+)%.lua$")
local increment = tonumber(string.match(script_name, "[%d.]+"))
if string.match(script_name, "-") then
  increment = increment * -1
end

local count = reaper.CountSelectedMediaItems(0)
if count > 0 then
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(111)
  for i = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local vol = reaper.GetMediaItemInfo_Value(item, "D_VOL")
    reaper.SetMediaItemInfo_Value(item, "D_VOL", vol * 10^(1 / 20 * increment))
    reaper.UpdateItemInProject(item)
  end
  reaper.PreventUIRefresh(-111)
  local sign = string.match(script_name, "-") and "-" or "+"
  reaper.Undo_EndBlock("Nudge items volume " .. sign .. increment .. " decibels", -1)
else
  reaper.MB("No item selected!", "Error", 0)
end
