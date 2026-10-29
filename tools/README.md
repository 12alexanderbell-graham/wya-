# Simulator tools

In a Debug build on the simulator, the app writes what is on screen to `snaps/latest.jpg` and reads test commands from `snaps/cmd.txt` (`app/wya/Design/Snap.swift`, `TestDriver.swift`). The app uses `WYA_SNAPS` if that is set, else `Claude outputs/night-2026-10-22/snaps` next to the project folder; set `WYA_SNAPS` to the same folder for these scripts (without it they use `snaps/` beside themselves). Neither runs in a phone build.

    ./snapcmd.sh <name> <seconds> "<command>" ...   # runs commands in the app, waits, saves snaps/<name>.jpg
    ./strip.sh <name> <WxH+X+Y> [columns]           # lays the last burst's frames side by side, cropped

Commands include `water closed|quarter|half|full`, `pull ai|off|<points>`, `gear <0..1>`, `settings on|off`, `search <text>|off`, `tools on|off`, `look <lon> <lat> <zoom>`, `maptap`, `streak <weeks>` and `burst <ms>`; the full list is in `TestDriver.swift`.
