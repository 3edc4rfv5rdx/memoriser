# Memorizer Project Notes

## ToDo.txt Structure
Location: `lib/ToDo.txt`

### Task markers:
- `o` or `>` — new/current tasks
- `?` — possible/maybe tasks
- `+` — completed tasks

### Sections:
- `===TODO:` — tasks to do
- `===TOFIX:` — bugs to fix
- `===ERRORS:` — known errors
- Tags/releases are also recorded here

### Important: New entries are added at the TOP of each section (right after ===XXX:)

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
- Current version: 9
- Main DB: `mainDb` (items table)
- Settings DB: `settDb`

## Code Style
- All code comments must be in English. Translate any non-English comments to English.
- ToDo.txt and Done.txt entries should also be in English.
