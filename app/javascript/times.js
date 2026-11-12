// The time in each column, as `Times.lines` of src/kanban/times.agc writes it for `kanban card show`; keep the two
// alike. `elapsed` is the time since the answer: the current column of an open card counts on.
var MINUTE = 60000;
var HOUR = 3600000;
var DAY = 86400000;

export function human(ms) {
  if (ms < MINUTE) {
    return "< 1 min";
  }
  if (ms >= DAY) {
    var hours = Math.floor((ms % DAY) / HOUR);
    return Math.floor(ms / DAY) + " d" + (hours ? " " + hours + " h" : "");
  }
  var minutes = Math.floor((ms % HOUR) / MINUTE);
  if (ms < HOUR) {
    return minutes + " min";
  }
  return Math.floor(ms / HOUR) + " h" + (minutes ? " " + minutes + " min" : "");
}

export function lines(times, elapsed) {
  if (!times.column) {
    return [];
  }
  var live = times.done ? 0 : elapsed;
  var stays = times.stays.map(function (stay) {
    return stay.name + " " + human(stay.ms + (stay.column_id === times.column_id ? live : 0));
  });
  var last = times.total_ms !== null ? "total " + human(times.total_ms) : human(Math.max(0, times.now - times.since) + live) + " in " + times.column;
  if (stays.length === 0 || (!times.done && stays.length === 1)) {
    return [last];
  }
  return [stays.join(" · "), last];
}
