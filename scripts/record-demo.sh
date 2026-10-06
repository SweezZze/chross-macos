#!/bin/zsh
# Records the README animations from the Debug build's demo mode (sample data only — the
# real store and widget are never touched). Takes over the mouse: don't use the Mac meanwhile.
#
#   ./scripts/record-demo.sh [scenario…]      scenarios: live timeline retime sidebar onboarding
#
# Needs: a Debug build in build/ (xcodebuild … -configuration Debug -derivedDataPath build),
# the Accessibility permission for chross, Screen Recording for the terminal, and ffmpeg.
set -u
cd "$(dirname "$0")/.."
APP=$PWD/build/Build/Products/Debug/chross.app
WORK=$(mktemp -d)
DOMAIN=com.louismenthonnex.chross
SCENARIOS=(${@:-live timeline retime sidebar onboarding})

defaults export $DOMAIN $WORK/defaults.plist        # restored at the end
osascript -e "quit app id \"$DOMAIN\"" 2>/dev/null; sleep 1.5

for SCN in $SCENARIOS; do
  OUT=$WORK/$SCN; mkdir -p $OUT
  ONB=YES; [ "$SCN" = onboarding ] && ONB=NO
  defaults delete $DOMAIN sidebarOrder 2>/dev/null; defaults delete $DOMAIN sidebarHidden 2>/dev/null
  open -n "$APP" --args -ChrossDemo -ChrossDemoScenario $SCN -ChrossDemoOutput $OUT \
    -hasCompletedOnboarding $ONB -workReminderEnabled NO -showMenuBarExtra NO \
    -dailyGoalHours 7 -ApplePersistenceIgnoreState YES
  # macOS sometimes starts the app windowless; a second `open` (a reopen event) brings one up.
  sleep 3; [ -f $OUT/rect ] || open "$APP"
  for i in {1..400}; do [ -f $OUT/rect ] && break; sleep 0.1; done
  if [ ! -f $OUT/rect ]; then echo "$SCN: no window"; pkill -f "Debug/chross.app/Contents/MacOS/chross"; continue; fi

  screencapture -v -C -R$(cat $OUT/rect) $OUT/video.mov >/dev/null 2>&1 &
  CAPTURE=$!
  sleep 1.2; touch $OUT/go
  for i in {1..900}; do [ -f $OUT/done ] && break; sleep 0.1; done
  sleep 0.4; kill -INT $CAPTURE; wait $CAPTURE 2>/dev/null
  pkill -f "Debug/chross.app/Contents/MacOS/chross"; sleep 1

  ffmpeg -v error -i $OUT/video.mov -vf "crop=iw:ih-24:0:0,fps=12,scale=880:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=160:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
    -loop 0 -y docs/media/$SCN.gif && echo "$SCN → docs/media/$SCN.gif"
done

defaults import $DOMAIN $WORK/defaults.plist
open -a chross 2>/dev/null
