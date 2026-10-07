-- Keep only your personal input overrides here. Uncommented settings below
-- replace Omarchy's defaults.
-- See https://wiki.hypr.land/Configuring/Basics/Variables/#input

-- Ported from dotfiles-hypr (configs/input.conf).
hl.config({
  input = {
    kb_layout = "fr",

    follow_mouse = 1,

    -- No mouse acceleration.
    sensitivity = 0,
    accel_profile = "flat",
    force_no_accel = true,

    touchpad = {
      natural_scroll = true,

      -- Right-click by pressing the bottom-right corner (libinput default),
      -- instead of Omarchy's two-finger click.
      clickfinger_behavior = false,
    },
  },
})

-- App-specific touchpad scroll speeds.
-- o.window("(Alacritty|kitty|foot)", { scroll_touchpad = 1.5 })

-- Enable touchpad gestures for changing workspaces.
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/
-- hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
