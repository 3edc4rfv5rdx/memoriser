# Memorizer Project Notes

## IMPORTANT: Work Rules
**CRITICAL - MUST FOLLOW:**
1. **Git is READ-ONLY** - Never use git commands (commit, push, etc.)
2. **Version numbers/tags are USER-ONLY** - Never create or modify version numbers in:
   - `lib/ToDo.txt` (e.g., `# v0.9.260130+78`)
   - `lib/globals.dart` (version constants)
   - `pubspec.yaml` (version field)
3. **Only add tasks** with markers `o`/`+`/`?` without version tags
4. **Don't check build** - Never run `gradlew assembleDebug` or similar build commands (saves time/tokens, user rebuilds anyway)

## ToDo.txt Structure
Location: `lib/ToDo.txt`

### Task markers:
- `o` or `>` — new/current tasks
- `?` — possible/maybe tasks
- `+` — completed tasks
- `#` — tag version

### Sections:
- `===TODO:` — tasks to do
- `===TOFIX:` — bugs to fix
- `===ERRORS:` — known errors
- Tags/releases are also recorded here

### Important: 
New entries are added at the TOP of each section (right after ===XXX:)

### Done.txt
Location: `lib/Done.txt`
Detailed descriptions of completed features go here.

## Photo Storage Structure
```
Documents/Memorizer/
├── Photo/
│   ├── item_{ID}/     — photos for item with ID
│   └── temp_{timestamp}/ — temp folder for new items (deleted on cancel or after 1 day)
├── mem-{date}/        — backup folder
│   ├── memorizer-{date}.db
│   ├── items-{date}.csv
│   └── Photo/         — photo backup
```

## Database
- Current version: 11
- Main DB: `mainDb` (items table)
- Settings DB: `settDb`

## Code Style
- All code comments must be in English. Translate any non-English comments to English.
- ToDo.txt and Done.txt entries should also be in English.

## Localization Rules
**CRITICAL - Localization Best Practices:**
- **Clean strings only** in `assets/locales.json` - no punctuation marks
- **Punctuation added programmatically** in code
- Example:
  - ❌ WRONG: `"Reminder:": {"ru": "Напоминание:"}`
  - ✅ CORRECT: `"Reminder": {"ru": "Напоминание"}` + add ":" in code
- Reason: Different languages may use different punctuation, same word used in different contexts
- Native Android code reads from `flutter_assets/assets/locales.json` using `context.assets.open()`
