# Handoff: Tier B Items and Known Issues

## Completed Tier B Items

1. **Hooks editor drag-and-drop reorder** - Added in SettingsView.swift via `onDrag`/`onDrop` modifiers
2. **Theme editor metadata fields** - Author, Version, Homepage, Preview Image URL added
3. **Test preview button** - 10-second theme preview in UI
4. **Engine enhancements** - `Engine.shared` singleton and `setTheme()` method
5. **DMG build script** - Fixed and improved
6. **New hooks system** - SystemEventRuntime, AgentHookRuntime, AgentMonitor added
7. **SystemVolumeClient** - CoreAudio framework integration
8. **Menu bar icon** - SF Symbol􀇮 keyboard icon

## Resolved Issues

### CLI Commands Requiring Engine Access (RESOLVED)

**Approach:** Enhanced original `KBPulse/main.m` with `set`, `flash`, `off` commands using `NSDistributedNotificationCenter` (via `DistributedNotificationCenter.default()` in Swift).

**Implementation:**
- CLI posts notification `com.ethanrdoesmc.kbpulse.command` with `userInfo: {command: "set"|"flash"|"off", profile: name}`
- App observer in `AppState.swift` calls `Engine.shared` methods
- Unknown profiles: logged and no-op
- App not running: prints error, exit 1

**Status:** Complete. See commits 11ca83f, 477b1c2, 6ec6e39, a85f10f for integration details.

### XCTest Target Integration (RESOLVED)
Test file `KBPulseAppTests/KBPulseAppTests.swift` integrated into Xcode project via commit 6ec6e39. Target `KBPulseAppTests` created as unit-test bundle with proper `TEST_HOST` referencing KBPulseApp. All 13 tests pass.

### Keyboard Settings Restoration (RESOLVED)
App restores user-selected keyboard settings (auto-brightness, idle-dim time, brightness level) on quit via `NSApplication.willTerminateNotification` handler in AppState.swift.

## Future Work

### DMG Distribution
`build-dmg.sh` script exists and works. Consider adding:
- Notarization handling for releases
- Automatic version bumping
- DMG background/branding

## Build Instructions

```bash
# Build both targets
xcodebuild -project KBPulse.xcodeproj -scheme KBPulseApp -configuration Debug build CODE_SIGNING_ALLOWED=NO
xcodebuild -project KBPulse.xcodeproj -scheme KBPulse -configuration Debug build CODE_SIGNING_ALLOWED=NO

# Create DMG
./build-dmg.sh release
```

## Git History

Last 11 commits on fork:
```
a85f10f Use SF Symbol􀇮 for menu bar icon instead of LOGO image asset
94f04fd Update handoff.md: add CLI commit, fix git history line count
11ca83f Add CLI set/flash/off commands via distributed notifications
6ec6e39 Integrate XCTest target and default missing Hook fields on decode
a2f3399 Finalize Tier B implementation
09d5fe5 Tier B enhancements: drag-and-drop hooks, reactive toggle, CLI framework
a36d8f7 Fix DMG build script
3f41300 Theme editor: add metadata fields and test preview
c5d8d67 Add music volume sync hook and DMG build script
4ce36c9 Show last-fired time and skip count for hooks
5c61dac Add frontmost-app, screen-lock, screen-unlock, and idle-threshold hooks
```

Commits locally on fork. Push pending - permission issue with remote origin.