---
name: remote-gui
description: Operate GUI applications on headless Linux servers via SSH using virtual display, screenshots, and xdotool automation
author: Zhou Qishun, Claude
version: 1.0.0
tags: [gui, remote, ssh, xvfb, xdotool, automation, headless]
---

# Remote GUI Operation

Enables Claude Code to see and interact with GUI applications on remote headless Linux servers.

## When to use

- You need to operate a desktop application on a server that has no monitor
- Examples: VPN clients, IDEs, database GUIs, file managers, browser-based tools
- The application has no CLI alternative

## Prerequisites

The skill will auto-install these on the remote server (requires `sudo`):

- `Xvfb` — Virtual framebuffer (fake display)
- `fluxbox` — Lightweight window manager
- `scrot` — Screenshot tool
- `xdotool` — Mouse/keyboard automation
- `imagemagick` — Image processing (optional)

## How it works

```
1. SSH to server
2. Start Xvfb virtual display on :99
3. Start fluxbox window manager
4. Launch target GUI application
5. Loop:
   a. scrot takes screenshot → SCP to local
   b. Claude reads screenshot (multimodal vision)
   c. Claude determines action (click coordinates, text to type)
   d. xdotool executes the action
   e. Back to (a) to verify
```

## Commands Reference

### Setup virtual display
```bash
# Start virtual framebuffer (1280x720, 24-bit color)
Xvfb :99 -screen 0 1280x720x24 &>/dev/null &
export DISPLAY=:99

# Start window manager (required for proper window rendering)
fluxbox &>/dev/null &
```

### Launch and interact
```bash
# Launch GUI app
/path/to/app &>/dev/null &
sleep 3

# Take screenshot
scrot /tmp/screenshot.png

# Mouse operations
xdotool mousemove X Y          # Move mouse to coordinates
xdotool click 1                # Left click
xdotool click 3                # Right click
xdotool mousemove X Y click 1  # Move and click

# Keyboard operations
xdotool type 'text to type'              # Type text
xdotool type --delay 50 'slow typing'    # Type with delay between keys
xdotool key Return                        # Press Enter
xdotool key Tab                           # Press Tab
xdotool key ctrl+a                        # Ctrl+A (select all)
xdotool key ctrl+c                        # Ctrl+C (copy)

# Window operations
xdotool search --name "Window Title"      # Find window by title
xdotool windowactivate WINDOW_ID          # Bring window to front
```

### Transfer screenshot
```bash
# Download screenshot to local for Claude to read
scp server:/tmp/screenshot.png /local/path/screenshot.png
```

## Limitations

- Screenshot-based: ~3-5 seconds per action cycle (screenshot + transfer + process)
- Cannot read text that's too small in the screenshot (increase resolution if needed)
- Requires `sudo` for initial package installation
- Window manager must be running for proper widget rendering
- No audio support

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Black screenshot | Start `fluxbox` window manager |
| App doesn't launch | Check `DISPLAY=:99` is exported |
| Click misses target | Take fresh screenshot, coordinates may have shifted |
| No packages available | Server needs internet access or pre-installed packages |
