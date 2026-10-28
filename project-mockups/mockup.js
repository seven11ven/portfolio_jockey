// Portfolio Jockey v2 mockups: shows each screen in a desktop (Linux) window and a
// phone (Android) frame, and adds light/dark and desktop/phone toggles.
// Static design preview only, not app code. No network requests, no storage.
(function () {
  "use strict";

  function frame(kind, screen) {
    var wrap = document.createElement("div");
    wrap.className = "frame-" + kind;
    var label = document.createElement("div");
    label.className = "frame-label";
    label.textContent = kind === "desktop" ? "Desktop (Linux)" : "Phone (Android)";
    var box = document.createElement("div");
    box.className = "frame";
    var bar = document.createElement("div");
    if (kind === "desktop") {
      bar.className = "titlebar";
      bar.innerHTML = "<span>Portfolio Jockey</span><span class=\"dots\">– ▢ ✕</span>";
    } else {
      bar.className = "statusbar";
      bar.innerHTML = "<span>9:41</span><span>▂▄▆ 🔋</span>";
    }
    var copy = screen.cloneNode(true);
    copy.hidden = false;
    box.appendChild(bar);
    box.appendChild(copy);
    wrap.appendChild(label);
    wrap.appendChild(box);
    return wrap;
  }

  document.querySelectorAll(".scene").forEach(function (scene) {
    var screen = scene.querySelector(".screen");
    if (!screen) return;
    var frames = document.createElement("div");
    frames.className = "frames";
    frames.appendChild(frame("desktop", screen));
    frames.appendChild(frame("phone", screen));
    screen.replaceWith(frames);
  });

  // Toggle buttons use data-set-theme / data-set-view, so they never pick up the
  // [data-theme] color tokens themselves.
  function setPressed(group, value) {
    document.querySelectorAll("button[data-set-" + group + "]").forEach(function (b) {
      b.setAttribute("aria-pressed", String(b.getAttribute("data-set-" + group) === value));
    });
  }
  function setTheme(t) { document.documentElement.setAttribute("data-theme", t); setPressed("theme", t); }
  function setView(v) { document.body.setAttribute("data-view", v); setPressed("view", v); }

  document.querySelectorAll("button[data-set-theme]").forEach(function (b) {
    b.addEventListener("click", function () { setTheme(b.getAttribute("data-set-theme")); });
  });
  document.querySelectorAll("button[data-set-view]").forEach(function (b) {
    b.addEventListener("click", function () { setView(b.getAttribute("data-set-view")); });
  });

  document.querySelectorAll(".move-toast").forEach(function (toast) {
    toast.addEventListener("click", function () { toast.remove(); });
  });

  var dark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
  setTheme(dark ? "dark" : "light");
  setView("both");
})();
