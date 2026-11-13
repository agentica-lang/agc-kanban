// A small Action Cable client (protocol `actioncable-v1-json`): one subscription, reconnect with backoff, a watch on
// the server ping. `onSubscribed()` runs on every confirmation (the first and each reconnect), so the caller fetches
// what it missed since its own fetch, `onMessage` gets what the channel broadcasts. Nobody is signed in: go to /login.
var STALE_MS = 12000; // the server pings every 3 s: a socket silent for this long is dead
var PROTOCOL = "actioncable-v1-json";

export function subscribe(params, onMessage, onSubscribed) {
  var identifier = JSON.stringify(params);
  var socket = null;
  var attempts = 0;
  var lastPing = 0;
  var retry = null;

  function open() {
    retry = null;
    var ws = new WebSocket((location.protocol === "https:" ? "wss://" : "ws://") + location.host + "/cable", PROTOCOL);
    socket = ws;
    lastPing = 0;
    ws.onmessage = function (event) {
      if (ws === socket) {
        receive(ws, JSON.parse(event.data));
      }
    };
    ws.onclose = function () {
      if (ws === socket) {
        socket = null;
        attempts += 1;
        retry = setTimeout(open, Math.min(30000, 500 * Math.pow(2, attempts)) * (0.5 + Math.random() / 2));
      }
    };
  }

  function receive(ws, frame) {
    if (frame.type === "welcome") {
      attempts = 0;
      lastPing = Date.now();
      ws.send(JSON.stringify({ command: "subscribe", identifier: identifier }));
    } else if (frame.type === "ping") {
      lastPing = Date.now();
    } else if (frame.type === "disconnect" && frame.reason === "unauthorized") {
      socket = null;
      location.assign("/login");
    } else if (frame.type === "confirm_subscription") {
      onSubscribed();
    } else if (frame.identifier === identifier && frame.message !== undefined) {
      onMessage(frame.message);
    }
  }

  // Reconnects a socket that is closed or silent for too long and says whether it did. Timers of a hidden tab are
  // throttled (a minute apart or worse) and a sleeping device drops the socket without a close event, so the interval
  // below can be far behind: the caller asks again when the tab is back.
  // `now` is true when the tab is back: then a closed socket (the backoff wait) reconnects at once too. The interval
  // passes false and acts only on a live but silent socket, so a server that is down keeps the backoff.
  function check(now) {
    if (!socket && !now) {
      return false;
    }
    if (socket && (!lastPing || Date.now() - lastPing <= STALE_MS)) {
      return false;
    }
    if (socket) {
      // The close event of a dead socket can take minutes. `onclose` ignores the old socket.
      var dead = socket;
      socket = null;
      dead.close();
    }
    clearTimeout(retry);
    open();
    return true;
  }

  setInterval(function () { check(false); }, 3000);

  open();
  return { check: check };
}
