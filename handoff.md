# Handoff: Tier B Items and Known Issues

## Completed Tier B Items

1. **Hooks editor drag-and-drop reorder** - Added in SettingsView.swift via `onDrag`/`onDrop` modifiers
2. **Theme editor metadata fields** - Author, Version, Homepage, Preview Image URL added
3. **Test preview button** - 10-second theme preview in UI
4. **Engine enhancements** - `Engine.shared` singleton and `setTheme()` method
5. **DMG build script** - Fixed and improved
6. **New hooks system** - SystemEventRuntime, AgentHookRuntime, AgentMonitor added
7. **SystemVolumeClient** - CoreAudio framework integration

## Known Issues

### CLI Commands Requiring Engine Access

**Problem:** The CLI subcommands `set`, `flash`, `off` require access to `Engine.shared` which lives in KBPulseApp target. The CLI.swift implementation was removed due to `@main` attribute conflict with KBPulseApp.swift.

**Current State:** 
- KBPulse target builds a CLI tool (main.m)
- ShellScript build phase creates symlink: `KBPulseApp.app/Contents/MacOS/kbpulse`
- Available commands: `list`, `validate`
- Missing commands: `set`, `flash`, `off` (need Engine access)

### Options to Rectify

#### Option 1: Enhance Original main.m (Recommended)
Modify `KBPulse/main.m` to include additional commands:
```c
// Add after existing printf statements
if (strcmp(argv[1], "set") == 0) {
    // Launch app and send command via distributed notifications
    // Or use AppleScript to trigger menu bar action
}
```
**Pros:** Cleanest solution, uses existing architecture
**Cons:** Requires Objective-C, less maintainable than Swift

#### Option 2: Separate CLI Tool Target
Create new target "KBPulseCLI" with CLI.swift (no @main needed, use main from KBPulseApp):
1. Copy CLI.swift content to new file without @main
2. Create new executable target
3. Have it communicate with KBPulseApp via:
   - Distributed notifications
   - Apple Events
   - Shared file in ~/Library/Application Support/

**Pros:** Swift, clean separation
**Cons:** More complex, requires IPC mechanism

#### Option 3: Menu Bar App CLI Handler
Add command-line argument handling to KBPulseApp:
1. Modify KBPulseApp.swift to check CommandLine.arguments
2. On launch, execute command and exit
3. Symlink can work directly with app bundle

**Pros:** Single entry point, full engine access
**Cons:** App behavior changes when launched with args

#### Option 4: Keep CLI.swift Separate Manual Installation
1. Keep CLI.swift as untracked/unintegrated
2. Document: build KBPulseApp, copy CLI.swift, compile standalone with @main
3. Install alongside app for full functionality

**Pros:** Simple to explain, works for power users
**Cons:** Manual process, not integrated into Xcode

## Remaining Work

### XCTest Target Integration
Test file exists at `KBPulseAppTests/KBPulseAppTests.swift` but not integrated into Xcode project.

To integrate:
1. Add PBXFileReference for KBPulseAppTests.swift
2. Add PBXBuildFile entry
3. Create PBXNativeTarget for KBPulseAppTests
4. Add build phases (Sources, Frameworks)
5. Create XCBuildConfiguration entries (Debug, Release)
6. Update PBXProject targets list
7. Add scheme file KBPulseAppTests.xcscheme

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

Last 8 commits:
```
a2f3399 Finalize Tier B implementation
09d5fe5 Tier B enhancements: drag-and-drop hooks, reactive toggle, CLI framework
a36d8f7 Fix DMG build script
3f41300 Theme editor: add metadata fields and test preview
c5d8d67 Add music volume sync hook and DMG build script
4ce36c9 Show last-fired time and skip count for hooks
5c61dac Add frontmost-app, screen-lock, screen-unlock, and idle-threshold hooks
d911ede Add pulse, hold, and fade hook actions
```

All commits pushed to origin/main.