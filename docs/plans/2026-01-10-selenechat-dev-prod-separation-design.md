# SeleneChat Dev/Prod Database Separation

**Status:** Ready for Implementation
**Created:** 2026-01-10

---

## Problem

SeleneChat has a single hardcoded default database path (`~/selene/data/selene.db`), which contains Claude's test data. The user's real notes are in `/Users/chaseeasterling/selene-data/selene.db`.

This causes:
- Production app shows fake/test notes instead of real notes
- No clear separation between dev testing and production use
- User must manually change path in Settings every time

## Solution

Auto-detect runtime environment and select appropriate database:

| Run Method | Detection | Database |
|------------|-----------|----------|
| `/Applications/SeleneChat.app` | Executable path contains `.app/Contents/MacOS` | `/Users/chaseeasterling/selene-data/selene.db` |
| `swift run` | Executable path in `.build/` | `~/selene/data/selene.db` |

## Implementation

### 1. DatabaseService.swift

Add detection methods and update init:

```swift
init() {
    self.databasePath = UserDefaults.standard.string(forKey: "databasePath")
        ?? Self.defaultDatabasePath()
    connect()
}

private static func isRunningFromAppBundle() -> Bool {
    let executablePath = Bundle.main.executablePath ?? ""
    return executablePath.contains(".app/Contents/MacOS")
}

private static func defaultDatabasePath() -> String {
    if isRunningFromAppBundle() {
        return "/Users/chaseeasterling/selene-data/selene.db"
    } else {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("selene/data/selene.db")
            .path
    }
}
```

### 2. SettingsView.swift

Add visual mode indicator in Database section:

```swift
Section("Database") {
    HStack {
        Text(DatabaseService.isRunningFromAppBundle() ? "Production" : "Development")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(DatabaseService.isRunningFromAppBundle()
                ? Color.green.opacity(0.2)
                : Color.orange.opacity(0.2))
            .foregroundColor(DatabaseService.isRunningFromAppBundle() ? .green : .orange)
            .cornerRadius(4)
        Spacer()
    }
    // ... existing UI
}
```

### 3. Debug Logging

In `connect()` method:

```swift
#if DEBUG
DebugLogger.shared.log(.state, "DatabaseService.mode: \(Self.isRunningFromAppBundle() ? "PRODUCTION" : "DEVELOPMENT")")
DebugLogger.shared.log(.state, "DatabaseService.defaultPath: \(Self.defaultDatabasePath())")
#endif
```

## Files Changed

| File | Changes |
|------|---------|
| `SeleneChat/Sources/Services/DatabaseService.swift` | Add detection methods, update init, add logging |
| `SeleneChat/Sources/Views/SettingsView.swift` | Add mode badge |

## Testing

1. Run `swift run` from `SeleneChat/` directory
2. Open Settings, verify orange "Development" badge
3. Verify database path shows `selene/data/selene.db`
4. Build and install: `./build-app.sh && cp -R .build/release/SeleneChat.app /Applications/`
5. Open `/Applications/SeleneChat.app`
6. Verify green "Production" badge
7. Verify database path shows `selene-data/selene.db`
8. Verify real notes appear

## Backwards Compatibility

- UserDefaults override still works (Settings → Browse)
- Existing installations will use new default on next launch
- No migration needed
