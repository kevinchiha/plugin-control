import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var record: null
  property var service: null
  property bool opened: false
  property color scrim: Color.menu.scrim
  property color foreground: Color.menu.text
  property string imagePath: ""

  readonly property string fullUrl: record && record.previewImage
    ? String(record.previewImage) : ""
  readonly property bool available: fullUrl !== ""

  signal dismissed()

  visible: opened && available

  function refresh() {
    imagePath = service && fullUrl ? service.previewPathFor(fullUrl) : ""
    if (!imagePath && fullUrl && opened) service.requestPreview(fullUrl)
  }

  onOpenedChanged: refresh()
  onFullUrlChanged: refresh()

  Connections {
    target: root.service
    function onPreviewReady(url, path) {
      if (url === root.fullUrl) root.imagePath = path
    }
  }

  Rectangle {
    anchors.fill: parent
    color: root.scrim
    opacity: 0.92

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismissed()
    }
  }

  Image {
    id: fullImage
    anchors.centerIn: parent
    width: Math.min(parent.width * 0.9, implicitWidth)
    height: Math.min(parent.height * 0.9, implicitHeight)
    source: root.imagePath ? "file://" + root.imagePath : ""
    visible: root.imagePath !== "" && status === Image.Ready
    asynchronous: true
    fillMode: Image.PreserveAspectFit
  }

  Text {
    anchors.centerIn: parent
    width: parent.width * 0.6
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    visible: root.imagePath === "" || fullImage.status === Image.Error
    text: root.imagePath === "" ? "Loading…"
      : "This image format isn't supported by the Qt image plugins installed on this system."
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.65
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
  }
}
