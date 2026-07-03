# MCGA Mode 13h Timing Choice

The initial mode `13h` timing block uses an EGA-compatible logical raster rather
than a full VGA 70 Hz model.

- Active area: `320x200`.
- Horizontal total: `400` logical pixel clocks.
- Horizontal sync: `48` logical pixel clocks after a `16` clock front porch.
- Vertical total: `249` lines.
- Vertical sync: `2` lines after a `12` line front porch.
- Sync polarity is active high inside the MCGA timing block.

This keeps the first renderer path simple and stable while reusing the existing
core video output and scaler plumbing. If later DOS/game smoke tests show that
software or MiSTer scaling depends on exact VGA mode `13h` 70 Hz timings, this
block should be replaced with explicit VGA-compatible totals and documented in
the final compatibility notes.
