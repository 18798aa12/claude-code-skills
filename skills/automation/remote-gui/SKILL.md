---
name: remote-gui
description: Operate GUI applications on headless Linux servers via SSH using virtual display, screenshots, and xdotool automation. Auto-detects and fixes common issues.
author: Jope Miler, Claude
version: 1.0.0
tags: [gui, remote, ssh, xvfb, xdotool, automation, headless]
---

# Remote GUI Operation

Enables Claude Code to see and interact with GUI applications on remote headless Linux servers.

## When to use

- You need to operate a desktop application on a server that has no monitor
- Examples: VPN clients, IDEs, database GUIs, file managers, browser-based tools
- The application has no CLI alternative

## Auto-Setup Flow

When this skill is triggered, Claude should automatically:

1. **Check and install dependencies** (if missing):
```bash
# Check what's installed
which Xvfb xdotool scrot fluxbox 2>/dev/null

# Install missing packages (auto-detect package manager)
if command -v apt &>/dev/null; then
    echo 'PASSWORD' | sudo -S apt install -y xvfb fluxbox scrot xdotool imagemagick
elif command -v yum &>/dev/null; then
    echo 'PASSWORD' | sudo -S yum install -y xorg-x11-server-Xvfb fluxbox scrot xdotool ImageMagick
fi
```

2. **Check if virtual display is already running** (don't start duplicates):
```bash
# Check existing Xvfb
ps aux | grep Xvfb | grep -v grep
# If not running, start it:
Xvfb :99 -screen 0 1280x720x24 &>/dev/null &
export DISPLAY=:99
```

3. **Check if window manager is running** (fixes black screenshot):
```bash
# If fluxbox not running → screenshots will be black!
ps aux | grep fluxbox | grep -v grep || fluxbox &>/dev/null &
sleep 2
```

4. **Launch the target GUI app**
5. **Enter screenshot-action loop**

## Auto-Fix: Black Screenshot

If screenshot is all black, Claude should automatically:
```bash
# 1. Check if fluxbox is running
if ! pgrep -x fluxbox > /dev/null; then
    export DISPLAY=:99
    fluxbox &>/dev/null &
    sleep 2
fi

# 2. Check if the app window exists
xdotool search --name "" | head -5
# If no windows → app didn't start, re-launch it

# 3. Retry screenshot
scrot /tmp/screen.png
```

## Auto-Fix: App Won't Launch

```bash
# Check DISPLAY is set
echo $DISPLAY  # Should be :99

# Check Xvfb is running
pgrep Xvfb || (Xvfb :99 -screen 0 1280x720x24 &>/dev/null &)

# Check app error output
/path/to/app 2>&1 | head -20
# Fix missing libraries, permissions, etc.
```

## Auto-Fix: Click Misses Target

```bash
# Window may have moved. Take fresh screenshot and recalculate coordinates.
scrot /tmp/screen_fresh.png
# Re-read screenshot and find new button position
```

## Commands Reference

### Setup
```bash
Xvfb :99 -screen 0 1280x720x24 &>/dev/null &
export DISPLAY=:99
fluxbox &>/dev/null &
```

### Screenshot
```bash
scrot /tmp/screenshot.png
scp server:/tmp/screenshot.png /local/path/
```

### Mouse
```bash
xdotool mousemove X Y          # Move to coordinates
xdotool click 1                # Left click
xdotool click 3                # Right click
xdotool click --repeat 2 1     # Double click
xdotool mousemove X Y click 1  # Move and click in one command
xdotool click 4                # Scroll up
xdotool click 5                # Scroll down
```

### Keyboard
```bash
xdotool type 'text'                  # Type text
xdotool type --delay 50 'slow text'  # Type with delay (for slow apps)
xdotool key Return                    # Enter
xdotool key Tab                       # Tab
xdotool key ctrl+a                    # Select all
xdotool key ctrl+c                    # Copy
xdotool key ctrl+v                    # Paste
xdotool key Escape                    # Escape
xdotool key BackSpace                 # Backspace
```

### Window Management
```bash
xdotool search --name "Window Title"  # Find window by title
xdotool windowactivate WINDOW_ID      # Focus window
xdotool getactivewindow                # Get current window ID
```

## Limitations

- ~3-5 seconds per action cycle
- Requires sudo for initial package installation
- No audio support
- Very small text may be hard to read (use higher resolution: `1920x1080x24`)
