-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false
--
-- Or disable only bindings for Omarchy's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- omarchy_preinstalled_bindings = false

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Écrans gérés par le widget Display (projection, position, résolution...).
require("hypr.display")

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })

-- Window rules ported from dotfiles-hypr (configs/tags.conf, windowrules.conf).
-- File/save dialogs are already floated by Omarchy's portal rules.
o.window("^([Mm]pv|vlc)$", { tag = "+multimedia_video" })
o.window("^(nm-applet|nm-connection-editor|blueman-manager|org.gnome.FileRoller|org.gnome.DiskUtility|wihotspot(-gui)?)$", { tag = "+settings" })
o.window("^(org.gnome.SystemMonitor|org.gnome.Evince|eog|org.gnome.Loupe)$", { tag = "+viewer" })

o.window({ tag = "multimedia_video" }, { float = true, no_blur = true, opacity = "1 1", size = { 900, 506 } })
o.window({ tag = "settings" }, { float = true, opacity = "0.8" })
o.window({ tag = "viewer" }, { float = true })

o.window("^(org.pulseaudio.pavucontrol)$", { float = true, opacity = "0.9", size = { "(monitor_w*0.5)", "(monitor_h*0.6)" } })
o.window("^(org.gnome.Nautilus)$", { opacity = "0.8" })
o.window("^(gedit|org.gnome.TextEditor|mousepad)$", { opacity = "0.9" })
o.window("^(kitty)$", { opacity = "0.9" })

o.window("^(discord|vesktop|org.telegram.desktop)$", { tag = "-default-opacity", opacity = "0.85 override 0.7 override 1 override" })
o.window("^(Spotify|spotify)$", { tag = "-default-opacity", opacity = "0.8 override 0.6 override 1 override" })
o.window("^(zen)$", { tag = "-default-opacity", opacity = "0.9 override 0.7 override 1 override" })

-- Empêche la mise en veille quand un onglet YouTube ou Anime-Sama est au premier plan dans Firefox ou Zen.
o.window({ class = "^(firefox|zen)$", title = ".*(YouTube|Anime-Sama).*" }, { idle_inhibit = "focus" })
