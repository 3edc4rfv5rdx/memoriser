#!/bin/sh

dst="${1%x}"

cp "$1" "$dst"

echo $dst
adb -s RFCW91FV79X install -r $dst

rm -f "$dst"
