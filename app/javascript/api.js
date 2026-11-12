// GET a JSON path of the API with the session cookie. A 401 means the session is gone: sign in again.
export function getJSON(path) {
  return fetch(path, { credentials: "same-origin", headers: { Accept: "application/json" } }).then(function (res) {
    if (res.status === 401) {
      location.assign("/login");
      return new Promise(function () {});
    }
    if (!res.ok) {
      throw new Error(path + " answered " + res.status);
    }
    return res.json();
  });
}
