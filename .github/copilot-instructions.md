# Copilot Instructions for sm-plugin-StopSound

## Repository Overview

This repository contains a SourceMod plugin for Counter-Strike: Source that allows players to toggle weapon sounds and map music on/off. The plugin provides persistent client preferences through SourceMod's cookie system and includes a menu interface for easy configuration.

**Key Features:**
- Toggle weapon sounds (shooting, reload, hit sounds)
- Toggle map ambient music  
- Persistent client preferences via cookies
- Multi-language support (English/Russian)
- Integration with SourceMod's cookie menu system

## Technical Environment

- **Language**: SourcePawn (.sp files)
- **Platform**: SourceMod 1.12+ (minimum required version)
- **Target Game**: Counter-Strike: Source only
- **Build Tool**: SourceKnight (configured via `sourceknight.yaml`)
- **Dependencies**:
  - SourceMod 1.11.0-git6917+ (build dependency)
  - MultiColors plugin (for colored chat messages)

## Project Structure

```
addons/sourcemod/
├── scripting/
│   └── StopSound.sp          # Main plugin source code
└── translations/
    └── plugin.stopsound.phrases.txt  # Translation strings (EN/RU)

.github/
├── workflows/
│   └── ci.yml               # GitHub Actions CI/CD pipeline
└── dependabot.yml          # Dependency updates

sourceknight.yaml           # Build configuration
```

## Code Style & Standards

### SourcePawn Specific Rules
- Use `#pragma semicolon 1` and `#pragma newdecls required` at file top
- Indentation: 4 spaces (represented as tabs in editor)
- camelCase for local variables and function parameters
- PascalCase for function names and global variables  
- Prefix global variables with `g_`
- Use descriptive variable and function names
- Remove trailing whitespace

### Memory Management (Critical)
- **NEVER** use `.Clear()` on StringMap/ArrayList - causes memory leaks
- Use `delete` instead of `CloseHandle()` - it's more modern and safe
- Always use `delete` directly without null checks (SourceMod handles this)
- For StringMap/ArrayList: `delete mapName; mapName = new StringMap();`
- Use methodmaps for cleaner object-oriented code

### Database Operations
- All SQL queries MUST be asynchronous (use SQL methodmap)
- Always escape strings and prevent SQL injection
- Use transactions when performing multiple related queries
- Handle database errors gracefully

### Best Practices for This Plugin
- Hook events and sounds conditionally based on client preferences
- Use fake hook toggles to avoid server instability 
- Cache expensive operations (avoid O(n) loops in frequently called functions)
- Use translation files for all user-facing messages
- Implement proper error handling for all API calls

## Build Process

The project uses SourceKnight for building:

1. **Local Development**: Install SourceKnight and run `sourceknight build`
2. **CI/CD**: GitHub Actions automatically builds on push/PR
3. **Dependencies**: Auto-downloaded via SourceKnight configuration
4. **Output**: Compiled `.smx` files in `addons/sourcemod/plugins/`

### Build Configuration (`sourceknight.yaml`)
- Downloads SourceMod 1.11.0-git6917 build tools
- Pulls MultiColors dependency from GitHub
- Targets: StopSound plugin compilation

## Key Architecture Patterns

### Event-Driven Design
- Hook game events (`round_end`, `player_spawn`)
- Hook sound systems (`NormalSound`, `AmbientSound`, `TempEnt`)
- Use conditional hooking to optimize performance

### Client State Management
```sourcepawn
bool g_bStopWeaponSounds[MAXPLAYERS+1];  // Per-client weapon sound preference
bool g_bStopMapMusic[MAXPLAYERS+1];      // Per-client music preference
```

### Persistent Storage
- Single cookie stores both preferences: format `"[0|1][0|1]"` (weapon:music)
- Cookie integration with SourceMod's native menu system
- Automatic loading on client connect and cookie cache

### Performance Optimizations
- Fake hook states (`g_bStopWeaponSoundsHooked`) to avoid actual hook toggling
- Client filtering in sound hooks to minimize performance impact
- StringMap for tracking ambient sounds by entity reference

## Common Development Tasks

### Adding New Sound Types
1. Identify the sound hook type needed (Normal, Ambient, TempEnt, UserMsg)
2. Add filtering logic in the appropriate hook function
3. Update the client preference system if needed
4. Test on a development server

### Adding Translation Strings
1. Add new phrases to `plugin.stopsound.phrases.txt`
2. Provide both English and Russian translations
3. Use `%t` format in code: `CPrintToChat(client, "%t %t", "Chat Prefix", "New Message");`

### Modifying Client Preferences
1. Update the cookie format if adding new preferences
2. Modify `SaveClientSettings()` and `OnClientCookiesCached()`
3. Update the cookie menu system in `ShowStopSoundsSettingsMenu()`

## Testing & Debugging

### Manual Testing Requirements
- Test on actual CS:S server (plugin is game-specific)
- Verify sound filtering works for all supported sound types
- Test cookie persistence across reconnections
- Verify menu system functionality
- Test with multiple clients to ensure no interference

### Common Issues
- **Performance**: Check for O(n) loops in sound hooks
- **Memory Leaks**: Verify proper use of `delete` vs `.Clear()`
- **Sound Conflicts**: Ensure hooks don't interfere with other sound plugins
- **Client State**: Verify proper cleanup on client disconnect

### Debug Commands
```sourcepawn
// Add these for debugging (remove in production):
RegConsoleCmd("sm_debug_sounds", Command_DebugSounds);  
RegConsoleCmd("sm_debug_hooks", Command_DebugHooks);
```

## Integration Points

### MultiColors Dependency
- Provides colored chat functionality via `CPrintToChat()` and `CReplyToCommand()`
- Must be loaded before this plugin
- Color tags: `{green}`, `{darkred}`, `{default}`

### SourceMod Cookie System
- Integrates with `!settings` menu automatically
- Cookie menu handler: `CookieMenuHandler_StopSounds()`
- Menu display: `ShowStopSoundsSettingsMenu()`

## Version Management

- Use semantic versioning (MAJOR.MINOR.PATCH)
- Update version in plugin info block when making changes
- Current version: 3.2.0
- Maintain compatibility with SourceMod 1.12+

## Common Pitfalls to Avoid

1. **Never use `.Clear()` on StringMap/ArrayList** - Use `delete` and recreate
2. **Don't toggle actual hooks dynamically** - Use fake hook states
3. **Avoid synchronous database operations** - Always use async SQL
4. **Don't forget client bounds checking** - Always validate client indices
5. **Memory management** - Always use `delete` instead of `CloseHandle()`
6. **Translation consistency** - Always use translation files, never hardcoded strings

## File-Specific Notes

### `StopSound.sp`
- Main plugin logic with sound filtering and client preference management
- Critical sections: sound hooks (lines 381-595), cookie management (lines 202-232)
- Performance-sensitive: client filtering loops in sound hooks

### `plugin.stopsound.phrases.txt`
- KeyValues format translation file
- Supports color tags from MultiColors
- When adding new phrases, maintain both EN/RU translations

### `sourceknight.yaml`
- Build configuration defining dependencies and build targets
- Modify carefully as it affects CI/CD pipeline
- Version updates should be coordinated with SourceMod compatibility

## Getting Started for New Contributors

1. **Understand SourceMod**: Familiarize yourself with SourceMod API and SourcePawn syntax
2. **Set up environment**: Install SourceKnight or use VS Code with SourcePawn extension
3. **Test server**: Always test changes on a CS:S development server
4. **Review existing code**: Understand the hook patterns and client state management
5. **Start small**: Begin with translation updates or minor feature additions before major changes

This plugin serves as a good example of SourceMod best practices for sound management, client preferences, and performance optimization in Source engine games.