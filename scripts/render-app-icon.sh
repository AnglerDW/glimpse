#!/bin/bash
# Render App/Resources/AppIcon/AppIcon.svg into App/Resources/Assets.xcassets/AppIcon.appiconset
# (16–1024 px, 1x and 2x) for macOS 14 / 15. macOS 26 uses the Icon Composer layers instead
# (App/Resources/AppIcon/layers/README.md).
#
# Needs Google Chrome (headless, renders SVG filters that NSImage's SVG support does not) and sips.
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[ -x "$CHROME" ] || { echo "error: Chrome not found at $CHROME (set CHROME=…)" >&2; exit 1; }

SRC="$PWD/App/Resources/AppIcon/AppIcon.svg"
SET="App/Resources/Assets.xcassets/AppIcon.appiconset"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/wrap.html" <<EOF
<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;background:transparent}img{display:block}</style></head>
<body><img src="file://$SRC" width="1024" height="1024"></body></html>
EOF

# Chrome prints display-link noise on a headless Mac; only its exit status matters.
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
  --window-size=1024,1024 --force-device-scale-factor=1 \
  --screenshot="$TMP/1024.png" "file://$TMP/wrap.html" >/dev/null 2>&1

mkdir -p "$SET"
rm -f "$SET"/*.png
# name:pixels — the macOS app icon set Xcode expects.
for spec in 16x16:16 16x16@2x:32 32x32:32 32x32@2x:64 128x128:128 128x128@2x:256 256x256:256 256x256@2x:512 512x512:512 512x512@2x:1024; do
  name="${spec%%:*}"; px="${spec##*:}"
  sips -s format png -z "$px" "$px" "$TMP/1024.png" --out "$SET/icon_$name.png" >/dev/null
done

cat > "$SET/Contents.json" <<'EOF'
{
  "images" : [
    { "filename" : "icon_16x16.png",      "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png",      "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png",    "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png",    "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png",    "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
echo "wrote $SET"
