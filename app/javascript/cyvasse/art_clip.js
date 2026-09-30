// The outline a piece's art is clipped to on the board.
//
// Alex, September 29, 2026 (task cyvasse-piece-art-overlap): a piece stands
// on its tile, so its art may rise over the tiles behind it (up and to the
// left) but is cut cleanly along its own tile's front edges. Of the six sides
// of the board's pointy-top hex, the art is clipped at the right, lower-right
// and lower-left ones and may overflow the upper-right, upper-left and left
// ones.
//
// The corners run as the board draws them (cyvasse_game_controller buildBoard),
// clockwise from the top, and side i runs from corner i to corner i + 1, the
// numbering cyvasse/edges uses for a hex's six sides.
export const HEX_SIDES = Object.freeze(["upper-right", "right", "lower-right", "lower-left", "left", "upper-left"]);
export const CLIPPED_SIDES = Object.freeze(["right", "lower-right", "lower-left"]);
export const FREE_SIDES = Object.freeze(["upper-right", "left", "upper-left"]);

// How far past a free side the art may reach, as a share of the hex's height.
// The largest piece (game.css, the large tier) rises well inside it.
export const ART_REACH = 0.4;

// The six corners of a pointy-top hex of this width and height, centred on
// the origin and scaled about it.
export function hexCorners(width, height, scale = 1) {
  return [
    [0, -height / 2], [width / 2, -height / 4], [width / 2, height / 4],
    [0, height / 2], [-width / 2, height / 4], [-width / 2, -height / 4]
  ].map(([x, y]) => [x * scale, y * scale]);
}

// The art's clip polygon around the hex's centre. It follows the hex's right,
// lower-right and lower-left sides exactly, from the upper-right corner round
// to the left corner. Past those two corners it runs on along the lines of
// the neighbours' sides that meet there (the right neighbour's upper-left
// side, the left neighbour's lower-right side), so the art never enters the
// hex to the right or the hexes below, and then closes in a box `reach`
// beyond the hex: over the upper-right, upper-left and left sides the art is
// free.
export function artClipCorners(width, height, { scale = 1, reach = ART_REACH } = {}) {
  const [top, upperRight, lowerRight, bottom, lowerLeft] = hexCorners(width, height, scale);
  const out = reach * height;
  // Along a slanted side, height changes by (height / 4) for every (width / 2)
  // across.
  const rise = out * height / (2 * width);
  const left = [lowerLeft[0] - out, lowerLeft[1] - rise];
  const right = [upperRight[0] + out, upperRight[1] - rise];
  const ceiling = top[1] - out;
  return [upperRight, lowerRight, bottom, lowerLeft, left, [left[0], ceiling], [right[0], ceiling], right];
}

// The same polygon as an SVG points attribute.
export function pointsAttribute(corners) {
  return corners.map(([x, y]) => `${x.toFixed(2)},${y.toFixed(2)}`).join(" ");
}
