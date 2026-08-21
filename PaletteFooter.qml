import QtQuick
import qs.Commons

Item {
  id: root

  property string marketplaceLabel: "Marketplace"
  property color foreground: Color.menu.text
  property color shortcutColor: Color.accent
  // Off while a modal is up, matching the result rows.
  property bool pointerInteractive: true

  // The entries look like buttons, so they behave like buttons. The action
  // name is dispatched by the palette to the same code its Ctrl shortcut
  // runs, so the two paths cannot drift apart.
  signal activated(string action)
  readonly property bool compact: width < Style.space(690)
  readonly property int footerFontSize: Math.max(9,
    Style.font.caption - (compact ? 1 : 0))

  Rectangle {
    anchors.top: parent.top
    width: parent.width
    height: 1
    color: Util.alpha(root.foreground, 0.16)
  }

  Row {
    id: footerRow
    anchors.fill: parent
    anchors.topMargin: Style.space(6)

    Repeater {
      model: [
        { keyLabel: "[Ctrl+u]", label: "Check for plugin updates",
          action: "updates" },
        { keyLabel: "[Ctrl+i]", label: "Plugin info", action: "info" },
        { keyLabel: "[Ctrl+w]", label: root.marketplaceLabel,
          action: "marketplace" },
        { keyLabel: "[Ctrl+g]", label: "GitHub plugin source",
          action: "github" },
        { keyLabel: "[Ctrl+r]", label: "Refresh cache", action: "refresh" },
        { keyLabel: "[Ctrl+s]", label: "Settings", action: "settings" }
      ]

      delegate: Item {
        required property var modelData
        width: footerRow.width / 6
        height: footerRow.height

        Column {
          width: parent.width
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: keyText.implicitWidth + Style.spacing.sm
            height: Style.space(22)
            radius: Style.space(4)
            color: Util.alpha(root.shortcutColor, 0.10)
            border.width: 1
            border.color: Util.alpha(root.shortcutColor, 0.70)

            Text {
              id: keyText
              anchors.centerIn: parent
              text: modelData.keyLabel
              textFormat: Text.PlainText
              color: root.shortcutColor
              font.family: Style.font.family
              font.pixelSize: root.footerFontSize
              font.bold: true
            }
          }

          Text {
            width: parent.width - Style.space(4)
            text: modelData.label
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.72
            horizontalAlignment: Text.AlignHCenter
            font.family: Style.font.menuFamily
            font.pixelSize: root.footerFontSize
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Math.max(8, root.footerFontSize - 2)
          }
        }

        MouseArea {
          anchors.fill: parent
          enabled: root.pointerInteractive
          cursorShape: Qt.PointingHandCursor
          onClicked: root.activated(modelData.action)
        }
      }
    }
  }
}
