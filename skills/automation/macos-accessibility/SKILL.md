---
name: macos-accessibility
description: macOS Accessibility API (AXUIElement) automation for building AI agents that control Mac apps. Covers element discovery, fallback strategies, CJK input, and common API failures with auto-fixes.
author: Jope Miler, Claude
version: 1.0.0
tags: [macos, accessibility, axuielement, automation, swift, agent, ui]
---

# macOS Accessibility API Automation

Build AI agents that control macOS applications using the Accessibility API (AXUIElement). Includes battle-tested fallback strategies for apps with poor accessibility support, CJK text input solutions, and comprehensive error handling.

## When to use

- Building an AI agent that needs to interact with macOS GUI applications
- Automating tasks that require clicking buttons, typing text, reading UI state
- Creating tools that read screen content from specific applications
- Debugging Accessibility API failures (many popular apps don't expose elements properly)

## Prerequisites

```bash
# 1. Accessibility permission (REQUIRED)
# System Settings → Privacy & Security → Accessibility → Add your app

# 2. Apple Events permission (for AppleScript fallback)
# System Settings → Privacy & Security → Automation → Allow your app to control others

# 3. Screen Recording permission (for screenshot-based fallback)
# System Settings → Privacy & Security → Screen Recording → Add your app
```

## Architecture: Defense in Depth

Never rely on a single automation method. The reliable approach is a 3-layer fallback:

```
Layer 1: Accessibility API (AXUIElement)
    ↓ fails?
Layer 2: Keyboard Shortcuts (CGEvent)
    ↓ fails?
Layer 3: Screenshot + Visual Positioning (CGWindowListCreateImage)
```

### Why This Matters

Many popular macOS apps (WeChat, QQ, Electron-based apps) don't properly expose UI elements through the Accessibility API. If your agent only uses AX API, it will get stuck in a retry loop.

## Layer 1: Accessibility API (AXUIElement)

### Reading UI Elements

```swift
import ApplicationServices

// Get the focused application
let app = AXUIElementCreateSystemWide()
var focusedApp: AnyObject?
AXUIElementCopyAttributeValue(app, kAXFocusedApplicationAttribute as CFString, &focusedApp)

// Get all windows
var windows: AnyObject?
AXUIElementCopyAttributeValue(focusedApp as! AXUIElement, kAXWindowsAttribute as CFString, &windows)

// Read window title
var title: AnyObject?
AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
print("Window: \(title as? String ?? "untitled")")
```

### Finding Elements by Role/Title

```swift
func findElement(root: AXUIElement, role: String, title: String?) -> AXUIElement? {
    var roleValue: AnyObject?
    AXUIElementCopyAttributeValue(root, kAXRoleAttribute as CFString, &roleValue)

    var titleValue: AnyObject?
    AXUIElementCopyAttributeValue(root, kAXTitleAttribute as CFString, &titleValue)

    if (roleValue as? String) == role {
        if title == nil || (titleValue as? String) == title {
            return root
        }
    }

    // Recursively search children
    var children: AnyObject?
    AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &children)

    if let childArray = children as? [AXUIElement] {
        for child in childArray {
            if let found = findElement(root: child, role: role, title: title) {
                return found
            }
        }
    }
    return nil
}
```

### Performing Actions

```swift
// Click a button
AXUIElementPerformAction(button, kAXPressAction as CFString)

// Set text field value
AXUIElementSetAttributeValue(textField, kAXValueAttribute as CFString, "Hello" as CFString)

// Get element position and size
var position: AnyObject?
var size: AnyObject?
AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position)
AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size)
```

## Layer 2: Keyboard Shortcuts (CGEvent)

When AX API fails, fall back to keyboard shortcuts:

```swift
import CoreGraphics

// Press a key combination (e.g., Cmd+F for Find)
func pressKeyCombo(keyCode: CGKeyCode, flags: CGEventFlags) {
    let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
    keyDown.flags = flags
    keyDown.post(tap: .cghidEventTap)

    let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)!
    keyUp.flags = flags
    keyUp.post(tap: .cghidEventTap)
}

// Common shortcuts
pressKeyCombo(keyCode: 3, flags: .maskCommand)     // Cmd+F (Find)
pressKeyCombo(keyCode: 0, flags: .maskCommand)     // Cmd+A (Select All)
pressKeyCombo(keyCode: 36, flags: [])               // Return/Enter
pressKeyCombo(keyCode: 48, flags: [])               // Tab
```

### Mouse Events via CGEvent

```swift
func clickAt(x: CGFloat, y: CGFloat) {
    let point = CGPoint(x: x, y: y)

    let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                           mouseCursorPosition: point, mouseButton: .left)!
    let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                         mouseCursorPosition: point, mouseButton: .left)!

    mouseDown.post(tap: .cghidEventTap)
    mouseUp.post(tap: .cghidEventTap)
}
```

## Layer 3: Screenshot + Visual Positioning

When both AX API and keyboard shortcuts fail:

```swift
import ScreenCaptureKit

// Capture a window screenshot
func captureWindow(windowID: CGWindowID) -> CGImage? {
    let imageRef = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        windowID,
        [.boundsIgnoreFraming, .bestResolution]
    )
    return imageRef
}

// Send screenshot to AI for visual element location
// Then use CGEvent to click at the identified coordinates
```

## CJK Text Input (Critical)

### The Problem

macOS `CGEvent` keyboard events can only type ASCII characters. AppleScript `keystroke` also cannot handle CJK (Chinese/Japanese/Korean) characters.

### The Solution: Clipboard Paste

```swift
import AppKit

func typeCJKText(_ text: String) {
    // 1. Save current clipboard
    let pasteboard = NSPasteboard.general
    let savedItems = pasteboard.pasteboardItems?.compactMap { item -> (String, Data)? in
        guard let type = item.types.first,
              let data = item.data(forType: type) else { return nil }
        return (type.rawValue, data)
    }

    // 2. Set text to clipboard
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)

    // 3. Cmd+V to paste
    pressKeyCombo(keyCode: 9, flags: .maskCommand)  // Cmd+V

    // 4. Wait and restore clipboard
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        if let items = savedItems {
            pasteboard.clearContents()
            for (type, data) in items {
                pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
        }
    }
}

// Usage:
typeCJKText("你好世界")  // Works for Chinese
typeCJKText("こんにちは")  // Works for Japanese
typeCJKText("안녕하세요")  // Works for Korean
```

## Agent Loop Design

### The Orchestrator Pattern

```swift
// Core agent loop with fallback strategy
func executeAction(_ action: AgentAction) async -> ActionResult {
    // Try Layer 1: Accessibility API
    if let result = try? await executeViaAX(action) {
        return result
    }

    // Try Layer 2: Keyboard shortcuts
    if let result = try? await executeViaKeyboard(action) {
        return result
    }

    // Try Layer 3: Screenshot + click
    if let result = try? await executeViaScreenshot(action) {
        return result
    }

    // All layers failed — return actionable error
    return ActionResult.failure(
        error: "All automation methods failed",
        suggestions: [
            "Try using keyboard shortcut: Cmd+F to find the element",
            "Grant Accessibility permission in System Settings",
            "The app may not support automation — try a different approach"
        ]
    )
}
```

### Max Iterations Guard

```swift
let maxIterations = 10
var iteration = 0

while iteration < maxIterations {
    let response = await callAI(conversation: history)

    guard let toolCalls = response.toolCalls, !toolCalls.isEmpty else {
        // AI responded with text only — task complete
        break
    }

    for toolCall in toolCalls {
        let result = await executeAction(toolCall)
        history.append(.toolResult(id: toolCall.id, content: result))
    }

    iteration += 1
}
```

## Auto-Fix: Common Issues

### "AXError.apiDisabled" — Missing Permission

```swift
// Detection
let trusted = AXIsProcessTrusted()
if !trusted {
    // Auto-prompt for permission
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
    // App will appear in System Settings → Accessibility
}
```

### "AXError.noValue" — Element Not Found

```bash
# Symptom: AXUIElementCopyAttributeValue returns .noValue
# Cause: App doesn't expose this element via Accessibility

# Fix: Fall back to keyboard shortcuts or screenshot
# NEVER retry the same AX call in a loop — it will fail every time
# Instead, suggest alternatives in the error response
```

### Agent Stuck in Retry Loop

```swift
// Anti-pattern: retrying the same failed action
// ❌ WRONG
while !success {
    success = tryAXAction()  // Will loop forever
}

// ✅ CORRECT: Try once, then fall back
if !tryAXAction() {
    if !tryKeyboardAction() {
        if !tryScreenshotAction() {
            return .failure(suggestions: [...])
        }
    }
}
```

### SPM SwiftUI App — No Window on Launch

```swift
// Symptom: swift run launches but no window appears
// Cause: SPM apps don't set activation policy automatically

// Fix: Set activation policy before creating window
import AppKit

@main
struct MyApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }
    // ...
}
```

### SPM App — Notification Center Crash

```swift
// Symptom: UNUserNotificationCenter causes crash in SPM app
// Cause: SPM apps don't have proper bundle identifier for notifications

// Fix: Use NSUserNotification (deprecated but works) or
// add Info.plist with CFBundleIdentifier to your SPM target

// Or avoid UNUserNotificationCenter entirely and use NSAlert for user-facing messages
```

### Swift Concurrency — Actor Isolation

```swift
// Symptom: "cannot call non-isolated method from actor"
// Using Swift 5.10 with strict concurrency

// Fix: Use @MainActor for UI-related actors
@MainActor
class UIController {
    func updateUI() {
        // Safe to access UI elements here
    }
}

// For background work, use a regular actor:
actor DataProcessor {
    func process() async -> Result {
        // Background processing
    }
}

// Bridge between them:
let result = await processor.process()
await MainActor.run {
    controller.updateUI(with: result)
}
```

## Design Principles

1. **Never rely solely on AX API** — many apps don't support it properly
2. **Always provide fallback suggestions** — when an action fails, tell the AI what to try next
3. **Use CGEvent for mouse/keyboard** — more reliable than AppleScript
4. **Clipboard for CJK** — the only reliable method for non-ASCII text
5. **Max iteration guard** — prevent infinite loops (recommended: 10 iterations)
6. **Actor isolation** — use `@MainActor` for UI, regular actors for background work
7. **Error messages should be actionable** — include concrete alternatives, not just "failed"

## Key Codes Reference

| Key | Code | Key | Code |
|-----|------|-----|------|
| A | 0 | Return | 36 |
| S | 1 | Tab | 48 |
| D | 2 | Space | 49 |
| F | 3 | Delete | 51 |
| V | 9 | Escape | 53 |
| C | 8 | Up | 126 |
| X | 7 | Down | 125 |
| Z | 6 | Left | 123 |
| N | 45 | Right | 124 |

| Modifier | CGEventFlags |
|----------|-------------|
| Command | `.maskCommand` |
| Shift | `.maskShift` |
| Option/Alt | `.maskAlternate` |
| Control | `.maskControl` |
