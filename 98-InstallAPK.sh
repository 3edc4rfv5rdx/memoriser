#!/bin/sh


src=$(ls -t Mem* | head -n1)
dst="${src%x}"
cp "$src" "$dst"
echo "$dst"
adb -s RFCW91FV79X install -r $dst
rm -f "$dst"
