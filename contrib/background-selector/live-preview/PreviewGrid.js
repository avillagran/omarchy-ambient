// 4x7 physical-pixel units preserve the 8x14 cell ratio without interpolation.
// The grid covers the whole slice, like the image in Omarchy's own picker: what
// passes its edges is cut by the slice's window and skewed mask.

// Daemon limits, which older renderers enforce too.
var maxCols = 260, maxRows = 80

// The grid for a slice of width x height logical pixels, as close to wantCols
// columns as whole units allow.
function cover(width, height, wantCols, dpr) {
  dpr = Math.max(1, dpr || 1)
  var w = width * dpr, h = height * dpr
  var unit = Math.max(1, Math.round(w / (Math.max(1, wantCols) * 4)))
  while (Math.ceil(w / (4 * unit)) > maxCols || Math.ceil(h / (7 * unit)) > maxRows) unit++
  return {cols: Math.max(1, Math.ceil(w / (4 * unit))), rows: Math.max(1, Math.ceil(h / (7 * unit)))}
}

// Where a cols x rows grid draws in that slice: the smallest unit that covers
// it, centred on the slice and aligned to physical pixels.
function metrics(width, height, cols, rows, dpr, globalX, globalY) {
  dpr = Math.max(1, dpr || 1)
  var w = width * dpr, h = height * dpr
  var unit = Math.max(1, Math.ceil(Math.max(w / (cols * 4), h / (rows * 7))))
  var cw = 4 * unit, ch = 7 * unit
  var gx = globalX * dpr, gy = globalY * dpr
  return {cw: cw / dpr, ch: ch / dpr,
    x: (Math.round(gx + (w - cw * cols) / 2) - gx) / dpr,
    y: (Math.round(gy + (h - ch * rows) / 2) - gy) / dpr,
    font: Math.max(2, Math.floor(Math.min(ch * 0.82, cw * 1.55))) / dpr,
    pixelWidth: cw, pixelHeight: ch}
}
