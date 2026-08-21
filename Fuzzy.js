function text(value) {
  return value === undefined || value === null ? "" : String(value)
}

function normalize(value) {
  return text(value).toLowerCase().replace(/\s+/g, " ").trim()
}

function commandRecord(name, operation, description) {
  return {
    name: name + ":",
    description: description,
    author: "Plugin Control",
    kind: "Command",
    stateLabel: "TAB / ENTER",
    sourceLabel: "Command",
    commandCompletion: name + ": ",
    commandName: name + ":",
    operation: operation
  }
}

var COMMANDS = [
  commandRecord("plug-add", "add", "Search available plugins to add"),
  commandRecord("plug-remove", "remove", "Search removable local plugins"),
  commandRecord("plug-enable", "enable", "Search disabled plugins"),
  commandRecord("plug-disable", "disable", "Search enabled plugins"),
  commandRecord("plug-update", "update", "Check for plugin updates"),
  commandRecord("plug-builtin", "builtin",
    "Search built-in Omarchy plugins"),
  commandRecord("plug-mine", "mine",
    "Search plugins you installed or cloned yourself"),
  commandRecord("plug-disabled", "disabled",
    "Search plugins that are switched off"),
  commandRecord("plug-type", "type",
    "Filter by kind: bar widget, panel, service, overlay")
]

function parseQuery(value) {
  var raw = text(value)
  // "disabled" must precede "disable": alternation is ordered, and the
  // shorter name would otherwise swallow the prefix of the longer one.
  var match =
    /^\s*plug-(add|remove|enable|disabled|disable|update|builtin|mine|type)\s*:\s*([\s\S]*)$/i
      .exec(raw)
  if (!match) return { mode: "browse", query: raw.trim() }

  return {
    mode: match[1].toLowerCase(),
    query: match[2].trim()
  }
}

function tokenBoundaryIndex(haystack, needle) {
  var offset = 0
  while (offset <= haystack.length - needle.length) {
    var index = haystack.indexOf(needle, offset)
    if (index < 0) return -1
    if (index === 0 || /[\s._\-/]/.test(haystack.charAt(index - 1))) return index
    offset = index + 1
  }
  return -1
}

function subsequenceCost(haystack, needle) {
  var position = 0
  var start = -1
  var previous = -1
  var gaps = 0

  for (var i = 0; i < needle.length; i++) {
    var found = haystack.indexOf(needle.charAt(i), position)
    if (found < 0) return -1
    if (start < 0) start = found
    if (previous >= 0) gaps += found - previous - 1
    previous = found
    position = found + 1
  }
  return start * 4 + gaps
}

function fieldScore(haystack, query, priority, exactEligible) {
  if (!haystack || !query) return -1

  if (exactEligible && haystack === query) return 100000 + priority
  if (haystack.indexOf(query) === 0) return 80000 + priority - haystack.length

  var boundary = tokenBoundaryIndex(haystack, query)
  if (boundary >= 0) return 60000 + priority - boundary

  var contiguous = haystack.indexOf(query)
  if (contiguous >= 0) return 40000 + priority - contiguous

  var cost = subsequenceCost(haystack, query)
  return cost >= 0 ? 20000 + priority - cost : -1
}

function scoreRecord(record, rawQuery) {
  var query = normalize(rawQuery)
  if (!query) return 0
  var fields = record.searchFields
  if (!Array.isArray(fields) || fields.length !== 9) return -1
  var priorities = [900, 850, 420, 320, 260, 240, 220, 180, 100]

  var primary = -1
  for (var i = 0; i < 2; i++) {
    var primaryScore = fieldScore(fields[i], query, priorities[i], true)
    if (primaryScore > primary) primary = primaryScore
  }
  if (primary >= 0) return 200000 + primary

  var best = -1
  for (var j = 2; j < fields.length; j++) {
    var candidate = fieldScore(fields[j], query, priorities[j], false)
    if (candidate > best) best = candidate
  }
  return best
}

function compareRows(left, right) {
  if (left.score !== right.score) return right.score - left.score
  var leftName = left.record.searchFields[0]
  var rightName = right.record.searchFields[0]
  if (leftName < rightName) return -1
  if (leftName > rightName) return 1
  var leftId = left.record.searchFields[1]
  var rightId = right.record.searchFields[1]
  return leftId < rightId ? -1 : (leftId > rightId ? 1 : 0)
}

// fieldScore separates match quality into fixed 20000-wide bands (exact,
// prefix, token boundary, contiguous, subsequence) and varies the remainder by
// haystack length. Commands all share the "plug-" prefix, so that remainder
// would rank them by name length; comparing bands keeps the declared order
// (actions before filters) as the tie-break instead.
var SCORE_BAND = 20000

function scoreBand(score) {
  return Math.floor(score / SCORE_BAND)
}

function commandIntent(value) {
  var query = normalize(value)
  if (query.length < 3 || query.indexOf(":") >= 0) return false
  return "plug-".indexOf(query) === 0
    || query.indexOf("plug-") === 0
    || query.indexOf("plg-") === 0
}

function commandSuggestions(value) {
  if (!commandIntent(value)) return null
  var query = normalize(value)
  var scored = []
  for (var i = 0; i < COMMANDS.length; i++) {
    var command = COMMANDS[i]
    var canonicalScore = fieldScore(command.commandName, query, 900, true)
    var operationScore = fieldScore(command.operation, query, 850, true)
    var best = Math.max(canonicalScore, operationScore)
    if (best >= 0)
      scored.push({ command: command, band: scoreBand(best), order: i })
  }
  scored.sort(function (left, right) {
    if (left.band !== right.band) return right.band - left.band
    return left.order - right.order
  })
  var results = []
  for (var j = 0; j < scored.length; j++) results.push(scored[j].command)
  return results
}

function operationIntent(operation, value) {
  var query = normalize(value)
  if (!query) return false
  if (operation.indexOf(query) === 0) return true
  return query.length >= 3
    && query.charAt(0) === operation.charAt(0)
    && subsequenceCost(operation, query) >= 0
}

function eligible(record, mode) {
  if (!record || !record.id) return false
  if (mode === "add")
    return record.installable === true && record.installed !== true
  if (mode === "remove")
    return record.removable === true
  if (mode === "update")
    return record.installed === true && record.builtIn !== true
      && record.updateAvailable === true
  var present = record.builtIn === true || record.installed === true
  if (mode === "enable")
    return present && record.enabled === false
      && (record.canDisable === true || record.fullBar === true)
  if (mode === "disable")
    return present && record.canDisable === true && record.enabled === true
  if (mode === "builtin")
    return record.builtIn === true
  if (mode === "mine")
    return record.installed === true && record.builtIn !== true
  if (mode === "disabled")
    return record.enabled === false
  return true
}

function normalizeKind(value) {
  return normalize(value).replace(/[-_]+/g, " ")
}

function matchesKind(record, query) {
  var needle = normalizeKind(query)
  if (!needle) return true
  return normalizeKind(record.kind).indexOf(needle) >= 0
}

// A sort is deliberately not one of the plug- commands: those replace each
// other, while an order has to combine with whichever filter and query are
// already active. "Mine, most starred" is a reasonable thing to ask for.
// Takes rows, not records, so it can stand in for compareRows directly. The
// id breaks a name tie so the order is stable rather than engine-dependent.
function compareNames(left, right) {
  var leftName = left.record.searchFields[0]
  var rightName = right.record.searchFields[0]
  if (leftName < rightName) return -1
  if (leftName > rightName) return 1
  var leftId = left.record.searchFields[1]
  var rightId = right.record.searchFields[1]
  return leftId < rightId ? -1 : (leftId > rightId ? 1 : 0)
}

function countField(record, field) {
  var value = Number(record && record[field])
  return isFinite(value) ? value : 0
}

function highestFirst(field) {
  return function (left, right) {
    var difference = countField(right.record, field)
      - countField(left.record, field)
    return difference !== 0 ? difference : compareNames(left, right)
  }
}

var SORTERS = {
  added: highestFirst("listedTime"),
  updated: highestFirst("updatedTime"),
  stars: highestFirst("stars"),
  views: highestFirst("views"),
  copies: highestFirst("copies"),
  hearts: highestFirst("hearts"),
  name: compareNames
}

function sorterFor(sort) {
  return SORTERS[normalize(sort)] || null
}

// Stars ship with the catalog, but views, copies and hearts come from the
// marketplace's separate counter service. When that service cannot be reached
// those three orders would silently rank everything as zero, so the chip steps
// over them instead of offering an order it cannot honour.
var ENGAGEMENT_SORTS = { views: true, copies: true, hearts: true }

var SORT_OPTIONS = [
  { key: "", label: "Best match" },
  { key: "added", label: "Recently added" },
  { key: "updated", label: "Recent activity" },
  { key: "stars", label: "Most starred" },
  { key: "views", label: "Most viewed" },
  { key: "copies", label: "Most copied" },
  { key: "hearts", label: "Most hearts" },
  { key: "name", label: "A-Z" }
]

function sortIndex(sort) {
  var key = normalize(sort)
  for (var i = 0; i < SORT_OPTIONS.length; i++)
    if (SORT_OPTIONS[i].key === key) return i
  return 0
}

function sortLabel(sort) {
  return SORT_OPTIONS[sortIndex(sort)].label
}

function sortOffered(sort, engagementAvailable) {
  return engagementAvailable !== false || !ENGAGEMENT_SORTS[normalize(sort)]
}

function nextSort(sort, engagementAvailable) {
  var index = sortIndex(sort)
  for (var step = 1; step <= SORT_OPTIONS.length; step++) {
    var candidate = SORT_OPTIONS[(index + step) % SORT_OPTIONS.length]
    if (sortOffered(candidate.key, engagementAvailable)) return candidate.key
  }
  return ""
}

function effectiveSort(sort, engagementAvailable) {
  var key = normalize(sort)
  return sortOffered(key, engagementAvailable) ? key : ""
}

function search(records, input, limit, sort) {
  var parsed = parseQuery(input)
  var values = Array.isArray(records) ? records : []
  var maximum = Number(limit)
  if (!isFinite(maximum)) maximum = 50
  maximum = Math.max(0, Math.min(100, Math.floor(maximum)))
  if (parsed.mode === "browse" && normalize(input).indexOf(":") >= 0)
    return { mode: "command", results: [] }
  var commands = parsed.mode === "browse" ? commandSuggestions(input) : null
  if (commands !== null) {
    return { mode: "command", results: commands.slice(0, maximum) }
  }
  var rows = []

  for (var i = 0; i < values.length; i++) {
    var record = values[i]
    if (!eligible(record, parsed.mode)) continue
    if (parsed.mode === "type") {
      if (matchesKind(record, parsed.query))
        rows.push({ record: record, score: 0 })
      continue
    }
    var score = scoreRecord(record, parsed.query)
    if (parsed.query && score < 0) continue
    rows.push({ record: record, score: score })
  }

  var sorter = sorterFor(sort)
  rows.sort(sorter || compareRows)
  var results = []
  var rawQuery = normalize(input)
  if (parsed.mode === "browse") {
    for (var k = 0; k < COMMANDS.length && results.length < maximum; k++) {
      if (operationIntent(COMMANDS[k].operation, rawQuery))
        results.push(COMMANDS[k])
    }
  }
  for (var j = 0; j < rows.length && results.length < maximum; j++)
    results.push(rows[j].record)
  return { mode: parsed.mode, results: results }
}

if (typeof module !== "undefined") {
  module.exports = {
    parseQuery: parseQuery,
    scoreRecord: scoreRecord,
    search: search,
    SORT_OPTIONS: SORT_OPTIONS,
    sortLabel: sortLabel,
    nextSort: nextSort,
    effectiveSort: effectiveSort
  }
}
