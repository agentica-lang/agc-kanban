// A small Action Cable client (protocol `actioncable-v1-json`): one subscription, reconnect with backoff, a watch on
// the server ping. `onSubscribed(again)` runs when the subscription is confirmed (again: after a reconnect, so the
// caller fetches what it missed), `onMessage` gets what the channel broadcasts. Nobody is signed in: go to /login.
var STALE_MS = 12000; // the server pings every 3 s: a socket silent for this long is dead
var PROTOCOL = "actioncable-v1-json";

export function subscribe(params, onMessage, onSubscribed) {
  var identifier = JSON.stringify(params);
  var socket = null;
  var attempts = 0;
  var lastPing = 0;
  var confirmedOnce = false;

  function open() {
    var ws = new WebSocket((location.protocol === "https:" ? "wss://" : "ws://") + location.host + "/cable", PROTOCOL);
    socket = ws;
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
      onSubscribed(confirmedOnce);
      confirmedOnce = true;
    } else if (frame.identifier === identifier && frame.message !== undefined) {
      onMessage(frame.message);
    }
  }

  setInterval(function () {
    if (socket && lastPing && Date.now() - lastPing > STALE_MS) {
      socket.close();
    }
  }, 3000);

  open();
}
