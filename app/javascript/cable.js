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

  function open() {
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
        setTimeout(open, Math.min(30000, 500 * Math.pow(2, attempts)) * (0.5 + Math.random() / 2));
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

  setInterval(function () {
    if (socket && lastPing && Date.now() - lastPing > STALE_MS) {
      // Reconnect now: the close event of a dead socket can take minutes. `onclose` ignores the old socket.
      var dead = socket;
      socket = null;
      dead.close();
      open();
    }
  }, 3000);

  open();
}
