#!/bin/bash
# Build for the simulator, boot an iPhone (Pro Max preferred) and capture screenshots of key screens.
set -x
APP_ID=com.personal.dcdusedcar
OUT=${OUT:-shots}
mkdir -p "$OUT"
xcodebuild -project DCDUsedCar.xcodeproj -scheme DCDUsedCar -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath simbuild \
  CODE_SIGNING_ALLOWED=NO build -quiet || exit 1
APP=simbuild/Build/Products/Debug-iphonesimulator/DCDUsedCar.app
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
d=json.load(sys.stdin)["devices"]
devs=[x for k,v in d.items() if "iOS" in k for x in v]
pref=[x for x in devs if "Pro Max" in x["name"]] or [x for x in devs if x["name"].startswith("iPhone")]
print(pref[-1]["udid"])')
echo "Using $UDID"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 || true
xcrun simctl install "$UDID" "$APP"
# skip the one-time "slide to type" keyboard intro that covers the search page
xcrun simctl spawn "$UDID" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true || true
xcrun simctl spawn "$UDID" defaults write com.apple.Preferences DidShowContinuousPathIntroduction -bool true || true

shot() { # name wait args...
  local name=$1 wait=$2; shift 2
  xcrun simctl terminate "$UDID" $APP_ID 2>/dev/null
  xcrun simctl launch "$UDID" $APP_ID "$@"
  sleep "$wait"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png"
}
# warm-up launch (first launch is slow: caches empty)
shot 00-warmup 25 -city 北京
shot 03-panel-price 10 -city 北京 -panel price
shot 04-panel-more 12 -city 北京 -panel more
shot 01-home 12 -city 北京
shot 02-home-scrolled 12 -city 北京 -scrolled
shot 05-brand-picker 10 -city 北京 -panel brand
shot 06-detail 14 -city 北京 -firstdetail
shot 07-detail-params 14 -city 北京 -firstdetail -scroll params
shot 08-detail-report 14 -city 北京 -firstdetail -scroll report
shot 09-viewer 14 -city 北京 -firstdetail -viewer
shot 10-seed 14 -city 北京 -seed 3
shot 11-mine 10 -mine
shot 12-history 8 -mine -history
shot 13-search 8 -city 北京 -search
shot 14-compare 16 -mine -compare
# 蔚来 电池方案 timing: time to the first 12 matches, written by the app to Documents/battery-timing.txt
# before: live detail reads only (no daily index, empty battery cache)
shot 40-before-rent 90 -city 全国 -brand 112 -battery rent -noindex -resetbattery
shot 41-before-buy 120 -city 全国 -brand 112 -battery buy -noindex -resetbattery
# after: daily index (downloaded fresh: -resetbattery also drops the index file), then warm (index on disk)
shot 30-nio-rent 25 -city 全国 -brand 112 -battery rent -resetbattery
shot 31-nio-buy 25 -city 全国 -brand 112 -battery buy -resetbattery
shot 35-nio-rent-warm 15 -city 全国 -brand 112 -battery rent
shot 36-nio-buy-warm 15 -city 全国 -brand 112 -battery buy
shot 32-nio-all 20 -city 全国 -brand 112 -battery none
shot 33-nio-detail 25 -city 全国 -brand 112 -battery rent -firstdetail
DATA=$(xcrun simctl get_app_container "$UDID" $APP_ID data 2>/dev/null || true)
if [ -n "$DATA" ] && [ -f "$DATA/Documents/battery-timing.txt" ]; then
  cp "$DATA/Documents/battery-timing.txt" "$OUT/battery-timing.txt"
  echo "== battery timing =="; cat "$OUT/battery-timing.txt"
else
  echo "no battery-timing.txt (container: $DATA)"
fi
# home screen with the app icon
xcrun simctl terminate "$UDID" $APP_ID 2>/dev/null
sleep 4
xcrun simctl io "$UDID" screenshot "$OUT/34-homescreen.png"
xcrun simctl ui "$UDID" appearance dark
shot 20-dark-home 10 -city 北京
shot 21-dark-detail 14 -city 北京 -firstdetail
shot 22-dark-mine 8 -mine
ls -la "$OUT"
