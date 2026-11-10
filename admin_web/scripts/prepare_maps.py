"""Generate the ignored, public browser Maps configuration. Never reads credentials."""
import json
import pathlib
import sys
import urllib.parse

config = json.loads(pathlib.Path(sys.argv[1]).read_text())
enabled = str(config.get("MAPS_ENABLED", False)).lower() == "true"
key = config.get("GOOGLE_MAPS_WEB_API_KEY", "")
script = "window.postcheckMapsReady = Promise.resolve();\n"
if enabled:
    if not key:
        raise SystemExit("MAPS_ENABLED requires GOOGLE_MAPS_WEB_API_KEY in the local configuration.")
    url = "https://maps.googleapis.com/maps/api/js?" + urllib.parse.urlencode({"key": key, "loading": "async", "callback": "postcheckMapsLoaded"})
    script = """window.postcheckMapsReady = new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error('Maps timeout')), 20000);
  window.postcheckMapsLoaded = () => { clearTimeout(timer); resolve(); };
  const script = document.createElement('script');
  script.src = %s;
  script.onerror = () => { clearTimeout(timer); reject(new Error('Maps unavailable')); };
  document.head.appendChild(script);
});
""" % json.dumps(url)
pathlib.Path("web/maps.local.js").write_text(script)
