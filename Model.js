function sameColor(a, b) {
  return !!a && !!b && a.r === b.r && a.g === b.g && a.b === b.b
}

function average(a, b) {
  return {
    r: Math.round(((a && a.r) || 0) + ((b && b.r) || 0)) / 2,
    g: Math.round(((a && a.g) || 0) + ((b && b.g) || 0)) / 2,
    b: Math.round(((a && a.b) || 0) + ((b && b.b) || 0)) / 2
  }
}

// Zone colors are stored in the original 0-15-per-channel scale this swatch
// row was designed around: it keeps swatch painting (value / 15), the bar
// icon preview, and "which swatch is active" comparison all working on one
// scale, and the row is a 16-step quick-pick anyway. The scale is a UI-only
// convention now -- the alienfx-lightd daemon speaks full 8-bit, so
// toDaemonColor() rescales at the moment a value is about to be sent
// (15 * 17 = 255). Nothing outside this file and Panel.qml's send path
// should ever see 0-255 values.
//
// (Historically the 0-15 scale existed because the dead alienware-wmi sysfs
// driver masked each channel to its low nibble. That driver is no longer
// used anywhere in this plugin -- see README.md.)
//
// AlienFX's iconic blue/magenta lead the list since they're what the brand is
// known for; the rest round out a small, clearly-distinct set rather than a
// full color wheel -- this is a quick-pick row, not a picker.
var presets = [
  { name: "Off", r: 0, g: 0, b: 0 },
  { name: "AlienFX Blue", r: 0, g: 8, b: 15 },
  { name: "Magenta", r: 15, g: 0, b: 10 },
  { name: "Red", r: 15, g: 0, b: 0 },
  { name: "Green", r: 0, g: 15, b: 0 },
  { name: "Amber", r: 15, g: 9, b: 0 },
  { name: "Cyan", r: 7, g: 14, b: 15 },
  // Blue drowns out green on this hardware once both run near full --
  // naive (15,15,15) reads as lavender on the real lights, eye-calibrated
  // 2026-11-08 by sending raw values and checking the physical panel. The
  // corrected b:2 makes the swatch *preview* read as yellow on screen even
  // though the real lights come out white, so `swatch` overrides just the
  // on-screen preview color -- it's never sent to the daemon.
  { name: "White", r: 15, g: 15, b: 2, swatch: { r: 15, g: 15, b: 15 } }
]

// Scale a 0-15 UI color to the daemon's full 8-bit (0-255) wire range.
// Called only on the send path; results are always whole numbers.
function toDaemonColor(r, g, b) {
  return {
    r: Math.round(r) * 17,
    g: Math.round(g) * 17,
    b: Math.round(b) * 17
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    sameColor: sameColor,
    average: average,
    presets: presets,
    toDaemonColor: toDaemonColor
  }
}
