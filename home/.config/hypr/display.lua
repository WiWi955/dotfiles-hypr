-- Généré par le widget Display (~/.config/omarchy/plugins/will.monitor/display-ctl).
-- Ne pas éditer à la main : utilise le widget, ou supprime ce fichier pour revenir aux défauts.

-- Écran du portable fermé (clamshell Omarchy) : on ne le rallume pas.
local function omarchy_flag(name)
  local f = io.open(os.getenv("HOME") .. "/.local/state/omarchy/toggles/hypr/" .. name .. ".lua")
  if f then f:close() return true end
  return false
end
local laptop_closed = omarchy_flag("internal-monitor-clamshell")

if not laptop_closed then
  hl.monitor({ output = "eDP-1", mode = "1920x1200@60.00", position = "3456x280", scale = 1.5 })
end
hl.monitor({ output = "desc:Microstep MPG271QX OLED 0x01010101", mode = "2560x1440@59.95", position = "0x216", scale = 1.6667 })
hl.monitor({ output = "desc:AOC 25G3ZM WKRQ3HA007190", mode = "1920x1080@60.00", position = "1536x0", scale = 1 })
