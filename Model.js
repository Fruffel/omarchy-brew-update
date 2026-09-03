// Foamy mug (md-glass-mug-variant). Never use the refresh glyph — that is Omarchy's updater.
function icon() {
  return "󱄖"
}

function emptyStatus() {
  return {
    ok: true,
    checkedAt: 0,
    checking: false,
    updating: false,
    error: "",
    brewPrefix: "",
    formulae: [],
    casks: [],
    installed: []
  }
}

function asList(value) {
  if (!value || typeof value.length !== "number") return []
  var out = []
  for (var i = 0; i < value.length; i++) out.push(value[i])
  return out
}

function parseStatus(raw) {
  var fallback = emptyStatus()
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return fallback
    fallback.ok = data.ok !== false
    fallback.checkedAt = Number(data.checkedAt || 0)
    fallback.checking = data.checking === true
    fallback.updating = data.updating === true
    fallback.error = typeof data.error === "string" ? data.error : ""
    fallback.brewPrefix = typeof data.brewPrefix === "string" ? data.brewPrefix : ""
    fallback.formulae = asList(data.formulae)
    fallback.casks = asList(data.casks)
    fallback.installed = asList(data.installed)
    return fallback
  } catch (e) {
    fallback.ok = false
    fallback.error = "Could not read Homebrew status"
    return fallback
  }
}

function packageCount(status) {
  if (!status) return 0
  return asList(status.formulae).length + asList(status.casks).length
}

function formatCheckedAt(ts) {
  var n = Number(ts || 0)
  if (!n) return "Not checked yet"
  var date = new Date(n * 1000)
  if (isNaN(date.getTime())) return "Not checked yet"
  return Qt.formatDateTime(date, "ddd HH:mm")
}

function versionLine(pkg) {
  if (!pkg) return ""
  var installed = String(pkg.installed || "")
  var current = String(pkg.current || "")
  if (installed && current) return installed + " → " + current
  return current || installed
}

function scriptFlags(includeCasks, greedyCasks) {
  var flags = []
  flags.push(includeCasks ? "--casks" : "--no-casks")
  if (greedyCasks) flags.push("--greedy")
  return flags
}
