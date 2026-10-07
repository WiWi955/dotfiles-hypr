-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- Ported from dotfiles-hypr (configs/keybinds.conf). Where a key clashed with
-- an Omarchy default, the old binding wins; the Omarchy action it replaced is
-- noted on the unbind line and moved to a free key when worth keeping.

-- Windows ----------------------------------------------------------------

hl.unbind("SUPER + W") -- was: Close window (now SUPER+Q)
o.bind("SUPER + Q", "Close window", hl.dsp.window.close())
o.bind("SUPER + SHIFT + Q", "Kill active process", "kill -9 $(hyprctl activewindow -j | jq -r .pid)")

hl.unbind("CTRL + ALT + DELETE") -- was: Close all windows
o.bind("CTRL + ALT + DELETE", "Exit Hyprland", "omarchy-system-logout")

-- Move windows (SUPER+CTRL+arrows was: move grouped window focus).
hl.unbind("SUPER + CTRL + LEFT")
hl.unbind("SUPER + CTRL + RIGHT")
o.bind("SUPER + CTRL + LEFT", "Move window left", hl.dsp.window.move({ direction = "l" }))
o.bind("SUPER + CTRL + RIGHT", "Move window right", hl.dsp.window.move({ direction = "r" }))
o.bind("SUPER + CTRL + UP", "Move window up", hl.dsp.window.move({ direction = "u" }))
o.bind("SUPER + CTRL + DOWN", "Move window down", hl.dsp.window.move({ direction = "d" }))

-- Resize windows (SUPER+SHIFT+arrows was: swap window).
hl.unbind("SUPER + SHIFT + LEFT")
hl.unbind("SUPER + SHIFT + RIGHT")
hl.unbind("SUPER + SHIFT + UP")
hl.unbind("SUPER + SHIFT + DOWN")
o.bind("SUPER + SHIFT + LEFT", "Resize window left", hl.dsp.window.resize({ x = -50, y = 0, relative = true }), { repeating = true })
o.bind("SUPER + SHIFT + RIGHT", "Resize window right", hl.dsp.window.resize({ x = 50, y = 0, relative = true }), { repeating = true })
o.bind("SUPER + SHIFT + UP", "Resize window up", hl.dsp.window.resize({ x = 0, y = -50, relative = true }), { repeating = true })
o.bind("SUPER + SHIFT + DOWN", "Resize window down", hl.dsp.window.resize({ x = 0, y = 50, relative = true }), { repeating = true })

-- Launchers --------------------------------------------------------------

o.bind("SUPER + D", "App launcher", "omarchy-menu toggle apps")

hl.unbind("SUPER + SHIFT + RETURN") -- was: Browser (still on SUPER+B / SUPER+SHIFT+B)
o.bind("SUPER + SHIFT + RETURN", "Floating terminal", "xdg-terminal-exec --app-id=TUI.float")

o.bind("SUPER + B", "Browser (workspace 3)", hl.dsp.focus({ workspace = "3" }))
o.bind("SUPER + B", nil, { omarchy = "browser" })

o.bind("SUPER + E", "File manager (workspace 2)", hl.dsp.focus({ workspace = "2" }))
o.bind("SUPER + E", nil, { launch = "nautilus" })

hl.unbind("SUPER + SHIFT + E") -- was: Email web app
o.bind("SUPER + SHIFT + E", "File manager (new window)", { launch = "nautilus --new-window" })

hl.unbind("SUPER + SHIFT + D") -- was: Docker TUI
o.bind("SUPER + SHIFT + D", "Discord (workspace 4)", hl.dsp.focus({ workspace = "4" }))
o.bind("SUPER + SHIFT + D", nil, o.launch_webapp_sole("chrome-discord.com__channels_@me-Default", "https://discord.com/channels/@me"))

hl.unbind("SUPER + O") -- was: Pop window out (float & pin)
o.bind("SUPER + O", "Obsidian", { launch = "obsidian", focus = "^obsidian$" })

hl.unbind("SUPER + CTRL + S") -- was: Share menu
o.bind("SUPER + CTRL + S", "Steam", { launch = "steam" })

o.bind("SUPER + N", "SSH NAS", "xdg-terminal-exec --title=NAS ssh nas")
o.bind("SUPER + I", "SSH serveur IA (réveil auto)", "xdg-terminal-exec --title=IA ia")
o.bind("SUPER + ALT + I", "Widget lab-ia / NAS", "omarchy-shell will.lab-ia toggle")

-- Utilities --------------------------------------------------------------

hl.unbind("SUPER + L") -- was: Toggle workspace layout
o.bind("SUPER + L", "Lock system", "omarchy-system-lock")

hl.unbind("SUPER + SHIFT + S") -- was: Google Maps web app
o.bind("SUPER + SHIFT + S", "Screenshot", "omarchy-capture-screenshot")

o.bind("SUPER + W", "Background switcher", "/home/will/.local/bin/wiwi-bg-switcher")

hl.unbind("SUPER + C") -- was: Universal copy
o.bind("SUPER + C", "Color picker", "pkill hyprpicker || hyprpicker -a")

hl.unbind("SUPER + V") -- was: Universal paste
o.bind("SUPER + V", "Clipboard history", "omarchy-shell shell toggle omarchy.clipboard")

o.bind("SUPER + R", "Restart bar", "omarchy-restart-shell")
o.bind_toggle("SUPER + H", "Hide bar", "bar")
o.bind("SUPER + M", "Toggle display mirroring", "omarchy-hyprland-monitor-internal-mirror toggle")

-- Dictation (voxtype): push-to-talk on CTRL+SHIFT+SPACE instead of F9.
hl.unbind("F9")
o.bind("CTRL + SHIFT + SPACE", "Start dictation (push-to-talk)", "voxtype record start")
o.bind("CTRL + SHIFT + SPACE", "Stop dictation (push-to-talk)", "voxtype record stop", { release = true })
