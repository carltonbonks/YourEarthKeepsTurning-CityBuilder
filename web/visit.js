// Counts a visit to the playtest page, before the game has loaded, with no id and nothing stored in the
// browser: just the build, screen size, language and the referring site's domain. Players' runs are sent
// by the game itself, and only if they say yes (game/telemetry.gd). Copied next to index.html by CI.
(function () {
  try {
    var q = new URLSearchParams(window.location.search);
    var host = window.location.hostname;
    if (q.get("dev") === "1" || host === "localhost" || host.indexOf("127.") === 0 || host === "") return;
    Promise.all([
      fetch("telemetry.json").then(function (r) { return r.json(); }),
      fetch("build_info.txt").then(function (r) { return r.ok ? r.text() : "dev build"; }).catch(function () { return "dev build"; })
    ]).then(function (got) {
      var cfg = got[0];
      if (!cfg.url || !cfg.key) return;
      var ref = "";
      try { ref = document.referrer ? new URL(document.referrer).hostname : ""; } catch (e) {}
      fetch(cfg.url.replace(/\/$/, "") + "/rest/v1/rpc/log_visit", {
        method: "POST", keepalive: true,
        headers: { "Content-Type": "application/json", "apikey": cfg.key, "Authorization": "Bearer " + cfg.key },
        body: JSON.stringify({ p: { build: got[1].trim(), screen: screen.width + "x" + screen.height,
          language: (navigator.language || "").slice(0, 2), referrer: ref, seeded: q.has("seed") } })
      }).catch(function () {});
    }).catch(function () {});
  } catch (e) {}
})();
