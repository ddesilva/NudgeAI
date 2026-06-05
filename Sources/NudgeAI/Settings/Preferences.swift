import AppKit

/// A keyboard shortcut described by a virtual key code and a set of modifier flags.
struct Hotkey: Equatable {
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags

    /// Symbol form like `⌘⇧N`, used in menus and the settings UI.
    var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += KeyCodeNames.name(for: keyCode) ?? "·"
        return s
    }
}

/// Persisted user preferences. Backed by `UserDefaults.standard`.
@MainActor
enum Preferences {
    private static let hotkeyKeyCodeKey   = "nudge.hotkey.keyCode"
    private static let hotkeyModifiersKey = "nudge.hotkey.modifiers"
    private static let hotkeyEnabledKey   = "nudge.hotkey.enabled"
    private static let retentionDaysKey   = "nudge.retention.days"
    private static let prioritizeMenuBarKey = "nudge.menubar.prioritize"
    nonisolated static let sessionsFolderKey = "nudge.sessions.folder"

    static let defaultRetentionDays = 7
    static let minRetentionDays = 1
    static let maxRetentionDays = 365

    /// Default global hotkey: ⌘⇧N (N for Nudge).
    static let defaultHotkey = Hotkey(keyCode: 45, modifiers: [.command, .shift])

    /// Built-in fallback location for session folders.
    nonisolated static var defaultSessionsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("NudgeAISessions", isDirectory: true)
    }

    /// Where sessions are actually written — the user's override if set,
    /// otherwise the default. Safe to read off the main actor since it only
    /// touches UserDefaults.
    nonisolated static var sessionsFolderURL: URL {
        sessionsFolderOverrideURL ?? defaultSessionsFolder
    }

    nonisolated static var sessionsFolderOverrideURL: URL? {
        guard let path = UserDefaults.standard.string(forKey: sessionsFolderKey),
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Setter for the override. `nil` clears it and falls back to default.
    static var sessionsFolderOverride: URL? {
        get { sessionsFolderOverrideURL }
        set {
            let ud = UserDefaults.standard
            if let url = newValue {
                ud.set(url.path, forKey: sessionsFolderKey)
            } else {
                ud.removeObject(forKey: sessionsFolderKey)
            }
            NotificationCenter.default.post(name: .nudgePreferencesChanged, object: nil)
            NotificationCenter.default.post(name: .nudgeSessionsChanged, object: nil)
        }
    }

    /// The currently configured hotkey, or `nil` when the user has disabled it.
    static var hotkey: Hotkey? {
        get {
            let ud = UserDefaults.standard
            let enabled = (ud.object(forKey: hotkeyEnabledKey) as? Bool) ?? true
            guard enabled else { return nil }
            if ud.object(forKey: hotkeyKeyCodeKey) == nil { return defaultHotkey }
            let keyCode = UInt32(ud.integer(forKey: hotkeyKeyCodeKey))
            let raw = UInt(bitPattern: ud.integer(forKey: hotkeyModifiersKey))
            let mods = NSEvent.ModifierFlags(rawValue: raw)
                .intersection([.command, .shift, .option, .control])
            return Hotkey(keyCode: keyCode, modifiers: mods)
        }
        set {
            let ud = UserDefaults.standard
            if let v = newValue {
                ud.set(true, forKey: hotkeyEnabledKey)
                ud.set(Int(v.keyCode), forKey: hotkeyKeyCodeKey)
                let mods = v.modifiers
                    .intersection([.command, .shift, .option, .control])
                ud.set(Int(bitPattern: mods.rawValue), forKey: hotkeyModifiersKey)
            } else {
                ud.set(false, forKey: hotkeyEnabledKey)
            }
            NotificationCenter.default.post(name: .nudgePreferencesChanged, object: nil)
        }
    }

    /// How many days a saved session is kept on disk before auto-purge.
    static var retentionDays: Int {
        get {
            let ud = UserDefaults.standard
            if ud.object(forKey: retentionDaysKey) == nil { return defaultRetentionDays }
            let v = ud.integer(forKey: retentionDaysKey)
            return min(max(v, minRetentionDays), maxRetentionDays)
        }
        set {
            let clamped = min(max(newValue, minRetentionDays), maxRetentionDays)
            UserDefaults.standard.set(clamped, forKey: retentionDaysKey)
            NotificationCenter.default.post(name: .nudgePreferencesChanged, object: nil)
        }
    }

    static var retentionMaxAge: TimeInterval {
        TimeInterval(retentionDays) * 24 * 60 * 60
    }

    /// When true, the menu-bar item is re-created on launch (and on demand)
    /// so it lands in the leftmost status-area slot — the position furthest
    /// from the notch / overflow-hide zone. macOS exposes no real "priority"
    /// API; this is the best we can do.
    static var prioritizeMenuBar: Bool {
        get {
            UserDefaults.standard.object(forKey: prioritizeMenuBarKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: prioritizeMenuBarKey)
            NotificationCenter.default.post(name: .nudgePreferencesChanged, object: nil)
        }
    }
}

extension Notification.Name {
    /// Posted whenever any persisted preference changes.
    static let nudgePreferencesChanged = Notification.Name("NudgePreferencesChanged")
    /// Posted when the user asks for the menu-bar item to be re-pinned to
    /// the leftmost status-area slot (Settings button or toggle).
    static let nudgeMenuBarRepinRequested = Notification.Name("NudgeMenuBarRepinRequested")
}

/// Human-readable labels for the macOS virtual key codes we care about.
enum KeyCodeNames {
    static func name(for code: UInt32) -> String? {
        switch Int(code) {
        case 0:  return "A"
        case 1:  return "S"
        case 2:  return "D"
        case 3:  return "F"
        case 4:  return "H"
        case 5:  return "G"
        case 6:  return "Z"
        case 7:  return "X"
        case 8:  return "C"
        case 9:  return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "↩"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "⇥"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "⌫"
        case 53: return "⎋"
        case 76: return "⌤"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 109: return "F10"
        case 111: return "F12"
        case 118: return "F4"
        case 120: return "F2"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return nil
        }
    }
}
