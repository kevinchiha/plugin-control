function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function text(value) {
  return value === undefined || value === null ? "" : String(value)
}

function cleanText(value) {
  return text(value).trim()
}

function searchText(value) {
  return cleanText(value).toLowerCase().replace(/\s+/g, " ")
}

function httpsUrl(value) {
  var raw = cleanText(value)
  return raw.indexOf("https://") === 0 ? raw : ""
}

function countNumber(value) {
  var number = Number(value)
  return isFinite(number) && number > 0 ? Math.floor(number) : 0
}

// Sorting by date has to survive a catalog that spells a date wrong or omits
// it, so an unreadable stamp sorts as the oldest possible rather than as NaN.
function timeNumber(value) {
  var parsed = Date.parse(cleanText(value))
  return isFinite(parsed) ? parsed : 0
}

function copy(value) {
  var out = {}
  if (!isRecord(value)) return out
  for (var key in value) out[key] = value[key]
  return out
}

function sourceRank(record) {
  if (record && isFinite(Number(record.sourceRank)))
    return Number(record.sourceRank)
  var source = cleanText(record && record.source)
  if (source === "local") return 50
  if (source === "builtin") return 40
  if (source === "marketplace") return 30
  if (source === "submission") return 20
  return 10
}

function sourceLabel(record) {
  var source = cleanText(record && record.source)
  if (source === "local") return "Local checkout"
  if (source === "builtin") return "Omarchy built-in"
  if (source === "marketplace") return "Marketplace listed"
  if (source === "submission") return "Unlisted submission"
  return cleanText(record && record.sourceName) || "Custom channel"
}

function warningState(record) {
  if (record && record.builtIn === true) return ""
  var state = cleanText(record && record.upstreamCheckStatus).toLowerCase()
  if (record && record.unlisted === true) {
    var security = Array.isArray(record.securityWarnings)
      ? record.securityWarnings.slice(0, 2).map(cleanText).filter(Boolean) : []
    return security.length > 0
      ? "Unlisted - " + security.join(", ") : "Unlisted"
  }
  if (!state || state === "unknown") return "Validation unknown"
  if (state === "passed") {
    var listed = cleanText(record.listingValidatedCommit)
    var upstream = cleanText(record.upstreamObservedCommit)
    return listed && upstream && listed !== upstream ? "Upstream changed" : ""
  }
  return "Validation " + state
}

function stateLabel(record) {
  if (record.builtIn === true) return record.enabled === false ? "Disabled" : "Built-in"
  if (record.installed === true)
    return record.enabled === false ? "Disabled" : "Installed"
  if (record.installable === true) return "Available"
  return "Browse only"
}

function isBarWidget(kind) {
  return cleanText(kind).toLowerCase().replace(/[-_]+/g, " ")
    .indexOf("bar widget") >= 0
}

function normalizeRecord(value) {
  var record = copy(value)
  record.id = cleanText(record.id)
  record.name = cleanText(record.name) || record.id
  record.description = cleanText(record.description)
  record.author = cleanText(record.author)
  record.version = cleanText(record.version)
  record.releaseTag = cleanText(record.releaseTag)
  record.repository = cleanText(record.repository)
  record.category = cleanText(record.category)
  record.kind = cleanText(record.kind)
  record.license = cleanText(record.license)
  record.repositoryUpdatedAt = cleanText(record.repositoryUpdatedAt)
  record.listedAt = cleanText(record.listedAt)
  record.listedTime = timeNumber(record.listedAt)
  record.updatedTime = timeNumber(record.repositoryUpdatedAt)
  record.stars = countNumber(record.stars)
  record.hearts = countNumber(record.hearts)
  record.views = countNumber(record.views)
  record.copies = countNumber(record.copies)
  record.previewThumbnail = httpsUrl(record.previewThumbnail)
  record.previewImage = httpsUrl(record.previewImage)
  record.previewThumbnailWidth = countNumber(record.previewThumbnailWidth)
  record.previewThumbnailHeight = countNumber(record.previewThumbnailHeight)
  record.previewWidth = countNumber(record.previewWidth)
  record.previewHeight = countNumber(record.previewHeight)
  record.source = cleanText(record.source) || "custom"
  record.sourceName = cleanText(record.sourceName)
  record.marketplaceListed = record.marketplaceListed === true
    || record.source === "marketplace"
  record.tags = Array.isArray(record.tags) ? record.tags.map(cleanText) : []
  record.sourceRank = sourceRank(record)
  record.sourceLabel = sourceLabel(record)
  record.warning = warningState(record)
  record.stateLabel = stateLabel(record)
  record.installed = record.installed === true
  record.enabled = record.enabled !== false
  record.canDisable = record.canDisable !== false
  record.installable = record.installable === true && !record.installed
  record.removable = record.removable === true
    && record.builtIn !== true
  record.searchFields = [record.name, record.id, record.repository,
    record.author, record.tags.join(" "), record.category, record.kind,
    record.sourceLabel, record.description].map(searchText)
  return record
}

function prepareRecords(records) {
  var values = Array.isArray(records) ? records : []
  var out = []
  for (var i = 0; i < values.length; i++) {
    var record = normalizeRecord(values[i])
    if (record.id) out.push(record)
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    warningState: warningState,
    isBarWidget: isBarWidget,
    prepareRecords: prepareRecords
  }
}
