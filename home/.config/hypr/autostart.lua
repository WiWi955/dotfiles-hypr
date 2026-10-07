-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Widget Display : réapplique le profil d'écrans à chaque branchement et
-- rallume le portable s'il ne reste plus d'écran externe.
o.launch_on_start(os.getenv("HOME") .. "/.config/omarchy/plugins/will.monitor/display-ctl watch")
