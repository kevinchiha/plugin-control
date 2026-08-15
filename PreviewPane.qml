import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var record: null
  property var service: null
  property color foreground: Color.menu.text
  property string imagePath: ""

  readonly property string thumbnailUrl: record && record.previewThumbnail
    ? String(record.previewThumbnail) : ""
  readonly property bool hasImage: imagePath !== ""

  signal imageActivated()

  function metadataLine() {
    if (!record) return ""
    var parts = []
    if (Number(record.stars) > 0) parts.push("★ " + Number(record.stars))
    if (String(record.license || "")) parts.push(String(record.license))
    if (String(record.category || "")) parts.push(String(record.category))
    return parts.join("  ·  ")
  }

  function updatedLine() {
    var when = Date.parse(String(record && record.repositoryUpdatedAt || ""))
    if (!isFinite(when)) return ""
    var days = Math.floor((Date.now() - when) / 86400000)
    if (days <= 0) return "Updated today"
    if (days === 1) return "Updated yesterday"
    if (days < 30) return "Updated " + days + " days ago"
    if (days < 365) return "Updated " + Math.floor(days / 30) + " months ago"
    return "Updated " + Math.floor(days / 365) + " years ago"
  }

  function refresh() {
    imagePath = service && thumbnailUrl
      ? service.previewPathFor(thumbnailUrl) : ""
    if (!imagePath && thumbnailUrl) fetchDebounce.restart()
    else fetchDebounce.stop()
  }

  onThumbnailUrlChanged: refresh()

  Timer {
    id: fetchDebounce
    interval: 150
    repeat: false
    onTriggered: {
      if (root.service && root.thumbnailUrl)
        root.service.requestPreview(root.thumbnailUrl)
    }
  }

  Connections {
    target: root.service
    function onPreviewReady(url, path) {
      if (url === root.thumbnailUrl) root.imagePath = path
    }
  }

  Column {
    anchors.fill: parent
    spacing: Style.spacing.sm

    Rectangle {
      id: imageFrame
      width: parent.width
      height: Math.round(width * 9 / 16)
      radius: Style.cornerRadius
      color: Util.alpha(root.foreground, 0.06)
      clip: true

      Image {
        id: previewImage
        anchors.fill: parent
        source: root.hasImage ? "file://" + root.imagePath : ""
        visible: root.hasImage && status === Image.Ready
        asynchronous: true
        cache: true
        fillMode: Image.PreserveAspectFit
        sourceSize.width: Math.round(imageFrame.width)
      }

      Text {
        anchors.centerIn: parent
        visible: !root.hasImage || previewImage.status === Image.Error
        text: {
          if (!root.hasImage) return root.thumbnailUrl ? "Loading…" : "No screenshot"
          return "Can't display image"
        }
        color: root.foreground
        opacity: 0.45
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        anchors.fill: parent
        enabled: root.hasImage
        cursorShape: root.hasImage ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.imageActivated()
      }
    }

    Text {
      width: parent.width
      text: root.record ? String(root.record.name || "") : ""
      textFormat: Text.PlainText
      color: root.foreground
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.title
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: text !== ""
      text: {
        if (!root.record) return ""
        var author = String(root.record.author || "")
        var version = String(root.record.version || "")
        return version ? (author ? author + "  ·  v" + version : "v" + version)
          : author
      }
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.70
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: text !== ""
      text: root.metadataLine()
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.60
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: text !== ""
      text: root.updatedLine()
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.50
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
