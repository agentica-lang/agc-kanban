// GET a JSON path of the API with the session cookie. A 401 means the session is gone: sign in again.
export function getJSON(path) {
  return fetch(path, { credentials: "same-origin", headers: { Accept: "application/json" } }).then(function (res) {
    if (res.status === 401) {
      location.assign("/login");
      return new Promise(function () {});
    }
    if (!res.ok) {
      var error = new Error(path + " answered " + res.status);
      error.status = res.status;
      throw error;
    }
    return res.json();
  });
}

// Wraps a GET that runs again and again (a snapshot after each event) so that the answers apply in order. An answer
// is applied when it is newer than the one shown, so only an answer that a newer one overtook is dropped. `onAnswer`
// gets `fresh` false when a newer request already failed: the answer is shown, the error of that failure stays.
// `onError` runs for a failure newer than the answer shown.
export function latest(request, onAnswer, onError) {
  var sent = 0;
  var applied = 0;
  var failed = 0;
  return function () {
    var mine = ++sent;
    return request().then(function (answer) {
      if (applied < mine) {
        applied = mine;
        onAnswer(answer, mine > failed);
      }
    }, function (error) {
      if (applied < mine) {
        failed = Math.max(failed, mine);
        onError(error);
      }
    });
  };
}
