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

// Builds an element: `h("div", { class: "x" }, child, [children], "text")`. Text goes in as text, so nothing is parsed
// as HTML.
export function h(tag, attrs) {
  var el = document.createElement(tag);
  Object.keys(attrs || {}).forEach(function (name) {
    if (typeof attrs[name] === "function") {
      el[name] = attrs[name]; // an event handler: `onclick`
    } else if (attrs[name] !== null && attrs[name] !== false) {
      el.setAttribute(name, attrs[name]);
    }
  });
  append(el, Array.prototype.slice.call(arguments, 2));
  return el;
}

function append(el, children) {
  children.forEach(function (child) {
    if (Array.isArray(child)) {
      append(el, child);
    } else if (child !== null && child !== undefined && child !== false) {
      el.appendChild(typeof child === "object" ? child : document.createTextNode(String(child)));
    }
  });
}
