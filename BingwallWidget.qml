import QtQuick
import QtQuick.Effects
import Quickshell.Io
import qs.Common
import qs.Services
import qs.DCommon.Widgets
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

    // Consecutive watcher failures; reset whenever the watcher reports an event
    property int    watcherRestarts:      0
    readonly property int maxWatcherRestarts: 5

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
    // Directory watcher — catches both normal and atomic writes from the daemon.
    // The directory is created first so the watcher works even if the daemon
    // has never run; if inotifywait exits anyway, it is restarted after a delay,
    // giving up after maxWatcherRestarts consecutive failures (e.g. not installed).
    // -------------------------------------------------------------------------
    Process {
        id: bingwallDirWatcher
        running: true
        command: ["sh", "-c",
                  "mkdir -p \"$1\" && exec inotifywait -q -m -e close_write,moved_to --format %f \"$1\"",
                  "sh", Paths.strip(Paths.cache + "/bingwall/")]
        onExited: (exitCode, exitStatus) => {
            if (++root.watcherRestarts > root.maxWatcherRestarts) {
                console.error("Wallpaper of the day: directory watcher keeps failing (is inotify-tools installed?) - giving up")
                return
            }
            console.warn("Wallpaper of the day: directory watcher exited with code", exitCode, "- restarting")
            watcherRestartTimer.restart()
        }
        stdout: SplitParser {
            onRead: line => {
                root.watcherRestarts = 0
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

    Timer {
        id: watcherRestartTimer
        interval: 5000
        repeat: false
        onTriggered: {
            // Files may have changed while the watcher was down
            root.reloadAll()
            bingwallDirWatcher.running = true
        }
    }

    Component.onCompleted: reloadAll()

    function reloadAll() {
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

            DIcon {
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

            DIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "wallpaper"
                size: Theme.iconSize - 7
                color: Theme.surfaceText
            }
        }
    }

    // -------------------------------------------------------------------------
    // Popout — height follows content; Escape and padding are handled by the host
    // -------------------------------------------------------------------------
    popoutWidth: 420
    popoutContent: Component {
        PopoutComponent {
            headerText: I18n.tr("Wallpaper of the Day")
            headerActions: Component {
                DRefreshButton {
                    buttonSize: 32
                    iconSize: 18
                    iconColor: Theme.surfaceText
                    busy: root.isDownloading
                    onClicked: root.requestForceDownload()
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // Hero image with title overlay
                Item {
                    width: parent.width
                    height: width * 9 / 16

                    Rectangle {
                        id: heroMask
                        anchors.fill: parent
                        radius: Theme.cornerRadius
                        color: "black"
                        visible: false
                        layer.enabled: true
                    }

                    Item {
                        anchors.fill: parent
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: heroMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: Theme.surfaceContainerHigh
                        }

                        DIcon {
                            anchors.centerIn: parent
                            visible: !root.currentImageSavePath
                            name: "wallpaper"
                            size: 48
                            color: Theme.surfaceVariantText
                        }

                        CachingImage {
                            anchors.fill: parent
                            imagePath: root.currentImageSavePath
                            fillMode: Image.PreserveAspectCrop
                            maxCacheSize: 512
                            opacity: root.isDownloading ? 0.5 : 1.0

                            Behavior on opacity {
                                NumberAnimation { duration: Theme.shortDuration }
                            }
                        }

                        // Bottom scrim keeps the title readable on bright images
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: heroTitle.implicitHeight + Theme.spacingL * 2
                            visible: root.currentTitle !== ""
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.75) }
                            }

                            StyledText {
                                id: heroTitle
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: Theme.spacingM
                                text: root.currentTitle
                                color: "white"
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.DemiBold
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }
                    }

                    DSpinner {
                        anchors.centerIn: parent
                        size: 40
                        running: root.isDownloading
                        visible: root.isDownloading
                    }
                }

                StyledText {
                    width: parent.width
                    text: root.currentDescription
                          || (root.currentImageSavePath ? "" : I18n.tr("No wallpaper downloaded yet"))
                    visible: text !== ""
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    maximumLineCount: 8
                    elide: Text.ElideRight
                }
            }
        }
    }
}
