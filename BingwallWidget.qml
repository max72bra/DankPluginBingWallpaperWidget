import QtQuick
import QtQuick.Effects
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // -------------------------------------------------------------------------
    // Shared paths — must match WallpaperBingDaemon.qml exactly
    // -------------------------------------------------------------------------
    readonly property string currentMetadataPath: Paths.cache + "/bingwall/metadata.json"
    readonly property string statusPath:          Paths.cache + "/bingwall/status.json"
    readonly property string forceTriggerPath:    Paths.cache + "/bingwall/force.trigger"

    // -------------------------------------------------------------------------
    // State read from daemon-written files
    // -------------------------------------------------------------------------
    property string currentImageSavePath: ""
    property string currentTitle:         ""
    property string currentDescription:   ""
    property bool   isDownloading:        false

    // -------------------------------------------------------------------------
    // Force trigger writer
    // -------------------------------------------------------------------------
    FileView {
        id: forceTriggerWriter
        path: root.forceTriggerPath
        blockLoading: true
        atomicWrites: false
    }

    // -------------------------------------------------------------------------
    // Directory watcher — catches both normal and atomic writes from the daemon
    // -------------------------------------------------------------------------
    Process {
        id: bingwallDirWatcher
        running: true
        command: ["inotifywait", "-q", "-m", "-e", "close_write,moved_to",
                  "--format", "%f",
                  Paths.strip(Paths.cache + "/bingwall/")]
        stdout: SplitParser {
            onRead: line => {
                const f = line.trim()
                if (f === "metadata.json") {
                    Proc.runCommand(null, ["cat", Paths.strip(root.currentMetadataPath)],
                        (output, exitCode) => { if (exitCode === 0) readMetadata(output) }, 0)
                } else if (f === "status.json") {
                    Proc.runCommand(null, ["cat", Paths.strip(root.statusPath)],
                        (output, exitCode) => { if (exitCode === 0) readStatus(output) }, 0)
                }
            }
        }
    }

    Component.onCompleted: {
        Proc.runCommand(null, ["cat", Paths.strip(root.currentMetadataPath)],
            (output, exitCode) => { if (exitCode === 0) readMetadata(output) }, 0)
        Proc.runCommand(null, ["cat", Paths.strip(root.statusPath)],
            (output, exitCode) => { if (exitCode === 0) readStatus(output) }, 0)
    }

    // -------------------------------------------------------------------------
    // Trigger a force download on the daemon side
    // -------------------------------------------------------------------------
    function requestForceDownload() {
        if (root.isDownloading) return
        forceTriggerWriter.setText(new Date().getTime().toString())
    }

    // -------------------------------------------------------------------------
    // Parse helpers
    // -------------------------------------------------------------------------
    function readMetadata(content) {
        try {
            if (content && content.trim()) {
                const m = JSON.parse(content)
                root.currentImageSavePath = m.currentImageSavePath ?? ""
                root.currentTitle         = m.currentTitle         ?? ""
                root.currentDescription   = m.currentDescription   ?? ""
            }
        } catch (e) {
            console.error("Wallpaper of the day: Error parsing metadata:", e)
        }
    }

    function readStatus(content) {
        try {
            if (content && content.trim()) {
                const s = JSON.parse(content)
                root.isDownloading = s.isDownloading ?? false
            }
        } catch (e) {
            console.error("Wallpaper of the day: Error parsing status:", e)
        }
    }

    // -------------------------------------------------------------------------
    // Bar pills
    // -------------------------------------------------------------------------
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "wallpaper"
                size: Theme.iconSize - 7
                color: Theme.surfaceText
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            DankIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "wallpaper"
                size: Theme.iconSize - 7
                color: Theme.surfaceText
            }
        }
    }

    // -------------------------------------------------------------------------
    // Popout
    // -------------------------------------------------------------------------
    popoutWidth: 400
    popoutHeight: 400
    popoutContent: Component {
        Column {
            id: contentColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: Theme.spacingM
            bottomPadding: Theme.spacingL
            spacing: Theme.spacingM

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    closePopout()
                    event.accepted = true
                }
            }

            // Header row
            Item {
                width: parent.width
                height: 32

                StyledText {
                    text: I18n.tr("Wallpaper of the Day")
                    font.pixelSize: Theme.fontSizeLarge
                    color: Theme.surfaceText
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: closeArea.containsMouse ? Theme.errorHover : "transparent"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter

                    DankIcon {
                        anchors.centerIn: parent
                        name: "close"
                        size: Theme.iconSize - 4
                        color: closeArea.containsMouse ? Theme.error : Theme.surfaceText
                    }

                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: closePopout()
                    }
                }
            }

            // Detail card
            Rectangle {
                id: bingwallDetail

                width: parent.width
                implicitHeight: detailColumn.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                border.color: Theme.outlineStrong
                border.width: 1
                clip: true

                Column {
                    id: detailColumn

                    anchors.fill: parent
                    anchors.margins: Theme.spacingL
                    spacing: Theme.spacingM

                    // Title + refresh button
                    Item {
                        width: parent.width
                        height: 30

                        StyledText {
                            id: bingwallTitle
                            text: root.currentTitle
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.DemiBold
                            color: Theme.surfaceText
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        DankActionButton {
                            id: refreshButton
                            buttonSize: 28
                            iconName: "refresh"
                            iconSize: 18
                            z: 15
                            anchors.right: parent.right
                            iconColor: Theme.surfaceText
                            enabled: !root.isDownloading
                            opacity: enabled ? 1.0 : 0.5
                            onClicked: root.requestForceDownload()

                            RotationAnimation {
                                target: refreshButton
                                property: "rotation"
                                from: 0
                                to: 360
                                duration: 1000
                                running: root.isDownloading
                                loops: Animation.Infinite
                                onRunningChanged: {
                                    if (!running) refreshButton.rotation = 0
                                }
                            }
                        }
                    }

                    // Wallpaper thumbnail
                    StyledRect {
                        width: parent.width
                        height: parent.width * 9 / 16
                        radius: Theme.cornerRadius
                        color: Theme.surfaceVariant
                        border.color: Theme.outline

                        CachingImage {
                            id: bingwallImage
                            anchors.fill: parent
                            anchors.margins: 1
                            imagePath: root.currentImageSavePath ? "file://" + root.currentImageSavePath : ""
                            fillMode: Image.PreserveAspectCrop
                            maxCacheSize: 160
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: wallpaperMask
                                maskThresholdMin: 0.5
                                maskSpreadAtMin: 1
                            }
                        }

                        Rectangle {
                            id: wallpaperMask
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: Theme.cornerRadius - 1
                            color: "black"
                            visible: false
                            layer.enabled: true
                        }
                    }

                    // Description
                    StyledText {
                        width: parent.width
                        text: root.currentDescription
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                        clip: true
                    }
                }
            }
        }
    }
}