## Memorizer
Android memory assistant

## Features
- English, Ukrainian, Russian localization (languages can be easily added)
- Record events with description, priority, tags, photos, dates and times
- Reminder types:
  - One-time reminders (with optional yearly/monthly repeat)
  - Daily reminders (multiple times per day, weekday selection)
  - Period reminders (date range with weekday mask)
- Fullscreen alert with sound looping, snooze (10min to 1 day), drag-to-dismiss
- Customizable sounds per item, always plays through speaker (bypasses Bluetooth)
- Virtual folders: Notes, Daily, Periods, Monthly, Yearly
- Filters by date range, priority, tags, reminder type; tag cloud
- Backup/restore in DB (SQLite) and CSV formats
- Built-in help system for all interface elements
- PIN-protected hidden area (accessed by tapping the header four times)
- Color themes

## Scripts
- `00-Make.sh` — build APK (sets xvDebug=false, restores after)
- `01-PushTag.sh` — git push with version tag
- `02-RelUpload.sh` — upload APK to GitHub release
Partial Vibe coding with Anthropic Claude :)
