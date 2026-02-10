#!/bin/sh


#adb -s RFCW91FV79X shell settings put secure backup_enabled 0
#adb -s RFCW91FV79X shell settings put secure backup_auto_restore 0
##adb -s RFCW91FV79X shell settings get secure backup_enabled
##adb -s RFCW91FV79X shell settings get secure backup_auto_restore

adb -s RFCW91FV79X shell pm clear com.example.memorizer
adb -s RFCW91FV79X shell pm uninstall com.example.memorizer
#adb -s RFCW91FV79X shell bmgr wipe com.example.memorizer
