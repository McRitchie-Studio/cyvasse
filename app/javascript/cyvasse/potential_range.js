// Every hex a unit could reach if nothing stood in the way.
//
// A line-for-line port of the legacy walk, amcritchie/Cyvasse
// app/assets/javascripts/hexRange/potentialRange.js. It traces concentric
// rings out from the unit, one "horizontal" step at a time, reading each
// row's width to know which way the rows lean. For every unit but the dragon
// the result is the full hex disc of the given radius; for the dragon it is
// the six straight lines out from its hex. The unit tests hold the port to
// both shapes against an independent cube-coordinate oracle.

import { hexAtXY } from "cyvasse/board";

// Hex indices within `range` of `origin` (a board hex), excluding the origin.
export function potentialRange(origin, range, { dragon = false } = {}) {
  const found = new Set();
  const xPos = origin.x;
  const yPos = origin.y;
  const sizeAt = (x, y) => hexAtXY(x, y)?.size;
  const mark = (x, y) => {
    const hex = hexAtXY(x, y);
    if (hex) found.add(hex.index);
  };

  for (let horizontal = 1; horizontal <= range; horizontal++) {
    let constantUp = 0;
    let constantDown = 0;
    let initialSizeDown = sizeAt(xPos, yPos);
    let initialSizeUp = sizeAt(xPos, yPos);

    mark(xPos - horizontal, yPos);
    mark(xPos + horizontal, yPos);

    for (let vertical = 1; horizontal >= vertical; vertical++) {
      const finalSizeDown = sizeAt(xPos, yPos + vertical);
      const finalSizeUp = sizeAt(xPos, yPos - vertical);

      // An undefined size (off the board) compares false, as it did in jQuery.
      if (initialSizeDown < finalSizeDown) constantDown += 1;
      if (initialSizeUp < finalSizeUp) constantUp += 1;

      for (const [constant, up] of [[constantDown, vertical], [constantUp, -vertical]]) {
        if (dragon) {
          if (horizontal <= vertical) {
            const xx = xPos - (horizontal - vertical - constant);
            mark(xx, yPos + up);
            mark(xx - horizontal, yPos + up);
          }
        } else if (horizontal <= vertical) {
          for (let row = 0; row <= horizontal; row++) {
            mark(xPos - (horizontal + row - vertical - constant), yPos + up);
          }
        } else {
          mark(xPos - (horizontal - constant), yPos + up);
          mark(xPos + (horizontal + constant - vertical), yPos + up);
        }
      }

      initialSizeDown = finalSizeDown;
      initialSizeUp = finalSizeUp;
    }
  }
  return found;
}
