// How long the board marks the last move, and when that mark goes.
//
// The last move (the hex a unit left, the hex it reached, and a unit's
// utility move) glows soft orange and fades away over LAST_MOVE_MS, then
// clears (game.css .last-move-glow). The board redraws often, so the mark's
// clock belongs to the MOVE, not to a redraw: every redraw names the move it
// is drawing (`key`), and only a new key starts the clock again. A redraw
// partway through the fade is told how long ago the move landed, so the glow
// carries on from there rather than starting over.

export const LAST_MOVE_MS = 10_000;

export class LastMoveMarker {
  // onExpire runs once per move, when its mark is due to go.
  constructor({ duration = LAST_MOVE_MS, now = () => Date.now(), onExpire = () => {} } = {}) {
    this.duration = duration;
    this.now = now;
    this.onExpire = onExpire;
    this.key = null;
    this.landedAt = null;
    this.expired = false;
    this.timer = null;
  }

  // The hexes to mark for this redraw and the milliseconds since the move
  // landed. `key` names the move (null or "" for none); `hexes` are its hexes.
  mark(key, hexes) {
    if (!key || hexes.length === 0) {
      this.stop();
      this.key = null;
      return { hexes: [], elapsed: 0 };
    }
    if (key !== this.key) {
      this.stop();
      this.key = key;
      this.landedAt = this.now();
      this.expired = false;
      this.timer = setTimeout(() => {
        this.timer = null;
        this.expired = true;
        this.onExpire();
      }, this.duration);
    }
    if (this.expired) return { hexes: [], elapsed: this.duration };
    return { hexes: [...hexes], elapsed: Math.min(this.duration, Math.max(0, this.now() - this.landedAt)) };
  }

  stop() {
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
  }
}

// The key for a game's last move, from its hexes: the same move reads the
// same on every redraw (and every poll of a live match). Not the turn: a side
// that passes leaves the last move as it was, and it should not glow again.
// Two moves in a row cannot share their hexes (the one who moved stands on
// the second), so a new move always reads anew.
export function lastMoveKey({ lastMove = [], utilMove = null }) {
  return [...lastMove, utilMove].filter((hex) => hex != null).join(",");
}
