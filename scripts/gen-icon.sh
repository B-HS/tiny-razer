#!/usr/bin/env bash
set -euo pipefail

# Generate Resources/AppIcon.icns from an SF Symbol.
# Re-run whenever you want to refresh the app icon.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_ICNS="$ROOT_DIR/Resources/AppIcon.icns"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

MASTER="$TMP/AppIcon.png"

echo "==> Rendering 1024×1024 master"
swift - "$MASTER" <<'SWIFT'
import Cocoa

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("missing output path\n".utf8))
    exit(1)
}
let outPath = CommandLine.arguments[1]
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// macOS app icons use a rounded-rect mask; 180 pt radius ≈ native shape.
let background = NSBezierPath(
    roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
    xRadius: 180,
    yRadius: 180
)
NSColor.white.setFill()
background.fill()

// -----------------------------------------------------------------------
// Tri-serpent glyph. Three curved "tadpole" shapes rotated 120° apart
// around the canvas centre — visually reminiscent of Razer's trinity logo
// without reproducing it.
// -----------------------------------------------------------------------
let razerGreen = NSColor(srgbRed: 68.0/255, green: 214.0/255, blue: 44.0/255, alpha: 1)
let center = NSPoint(x: size / 2, y: size / 2)
razerGreen.setFill()

for i in 0..<3 {
    NSGraphicsContext.current?.saveGraphicsState()

    // Translate to icon centre, rotate 120° per blade, offset 90° so the
    // first blade points up.
    let transform = NSAffineTransform()
    transform.translateX(by: center.x, yBy: center.y)
    transform.rotate(byDegrees: CGFloat(i) * 120 + 90)
    transform.concat()

    let len: CGFloat = size * 0.42      // tip radius from centre
    let baseWidth: CGFloat = size * 0.16 // thickness at the base (centre)
    let tipInset: CGFloat = size * 0.02  // how rounded the tip is

    let path = NSBezierPath()
    // Base arc around the centre
    path.move(to: NSPoint(x: -baseWidth * 0.5, y: 0))

    // Left edge curves outward to tip (creating a comma/serpent silhouette)
    path.curve(
        to: NSPoint(x: -tipInset, y: len),
        controlPoint1: NSPoint(x: -baseWidth * 1.4, y: len * 0.45),
        controlPoint2: NSPoint(x: -baseWidth * 0.35, y: len * 0.95)
    )

    // Rounded tip
    path.curve(
        to: NSPoint(x: tipInset, y: len),
        controlPoint1: NSPoint(x: -tipInset * 0.3, y: len + tipInset * 1.2),
        controlPoint2: NSPoint(x: tipInset * 0.3, y: len + tipInset * 1.2)
    )

    // Right edge curls back with a slight counter-curve for a hook look
    path.curve(
        to: NSPoint(x: baseWidth * 0.5, y: 0),
        controlPoint1: NSPoint(x: baseWidth * 0.15, y: len * 0.85),
        controlPoint2: NSPoint(x: baseWidth * 0.2, y: len * 0.35)
    )

    // Close across the base with a small inner cut-out to create the
    // pinched centre that makes the trio look interlocked.
    path.curve(
        to: NSPoint(x: -baseWidth * 0.5, y: 0),
        controlPoint1: NSPoint(x: baseWidth * 0.18, y: -baseWidth * 0.35),
        controlPoint2: NSPoint(x: -baseWidth * 0.18, y: -baseWidth * 0.35)
    )
    path.close()
    path.fill()

    NSGraphicsContext.current?.restoreGraphicsState()
}

// Small centred dot to tie the three shapes together visually.
let dotRadius: CGFloat = size * 0.05
let dot = NSBezierPath(ovalIn: NSRect(
    x: center.x - dotRadius,
    y: center.y - dotRadius,
    width: dotRadius * 2,
    height: dotRadius * 2
))
razerGreen.setFill()
dot.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("failed to encode PNG\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outPath))
SWIFT

echo "==> Building iconset"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"

render() {
    local size="$1"
    local out="$2"
    sips -z "$size" "$size" "$MASTER" --out "$ICONSET/$out" >/dev/null
}

render 16   "icon_16x16.png"
render 32   "icon_16x16@2x.png"
render 32   "icon_32x32.png"
render 64   "icon_32x32@2x.png"
render 128  "icon_128x128.png"
render 256  "icon_128x128@2x.png"
render 256  "icon_256x256.png"
render 512  "icon_256x256@2x.png"
render 512  "icon_512x512.png"
render 1024 "icon_512x512@2x.png"

echo "==> Converting to .icns"
iconutil --convert icns "$ICONSET" --output "$OUT_ICNS"

echo "✓ Wrote $OUT_ICNS"
