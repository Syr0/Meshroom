import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Controls 1.4 as Controls1 // For SplitView
import QtQuick.Layouts 1.11
import Qt.labs.platform 1.0 as Platform
import ImageGallery 1.0
import Viewer 1.0
import MaterialIcons 2.2
import Controls 1.0
import Utils 1.0


/**
 * WorkspaceView is an aggregation of Meshroom's main modules.
 *
 * It contains an ImageGallery, a 2D and a 3D viewer to manipulate and visualize reconstruction data.
 */
Item {
    id: root

    property variant reconstruction: _reconstruction
    readonly property variant cameraInits: _reconstruction ? _reconstruction.cameraInits : null
    property bool readOnly: false
    readonly property Viewer2D viewer2D: viewer2D
    readonly property alias imageGallery: imageGallery

    implicitWidth: 300
    implicitHeight: 400


    Connections {
        target: reconstruction

        function onSfmChanged() { viewSfM() }
        function onSfmReportChanged() { viewSfM() }
    }
    Component.onCompleted: viewSfM()

    // Load reconstruction's current SfM file
    function viewSfM() {
        var activeNode = _reconstruction.activeNodes ? _reconstruction.activeNodes.get('sfm').node : null
        if (!activeNode)
            return
    }

    SystemPalette { id: activePalette }

    Controls1.SplitView {
        anchors.fill: parent

        Controls1.SplitView {
            orientation: Qt.Vertical
            Layout.fillHeight: true
            implicitWidth: Math.round(parent.width * 0.2)
            Layout.minimumWidth: imageGallery.defaultCellSize

            ImageGallery {
                id: imageGallery
                Layout.fillHeight: true
                readOnly: root.readOnly
                cameraInits: root.cameraInits
                cameraInit: reconstruction ? reconstruction.cameraInit : null
                tempCameraInit: reconstruction ? reconstruction.tempCameraInit : null
                cameraInitIndex: reconstruction ? reconstruction.cameraInitIndex : -1
                onRemoveImageRequest: reconstruction.removeAttribute(attribute)
                onAllViewpointsCleared: { reconstruction.removeAllImages(); reconstruction.selectedViewId = "-1" }
                onFilesDropped: reconstruction.handleFilesDrop(drop, augmentSfm ? null : cameraInit)
            }
        }

        Panel {
            title: "Image Viewer"
            visible: settings_UILayout.showImageViewer
            implicitWidth: Math.round(parent.width * 0.35)
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.minimumWidth: 50
            loading: viewer2D.loadingModules.length > 0
            loadingText: loading ? "Loading " + viewer2D.loadingModules : ""

            headerBar: RowLayout {
                MaterialToolButton {
                    text: MaterialIcons.more_vert
                    font.pointSize: 11
                    padding: 2
                    checkable: true
                    checked: imageViewerMenu.visible
                    onClicked: imageViewerMenu.open()
                    Menu {
                        id: imageViewerMenu
                        y: parent.height
                        x: -width + parent.width
                        Action {
                            id: displayImageToolBarAction
                            text: "Display HDR Toolbar"
                            checkable: true
                            checked: true
                            enabled: viewer2D.useFloatImageViewer
                        }
                        Action {
                            id: displayLensDistortionToolBarAction
                            text: "Display Lens Distortion Toolbar"
                            checkable: true
                            checked: true
                            enabled: viewer2D.useLensDistortionViewer
                        }
                        Action {
                            id: enable8bitViewerAction
                            text: "Enable 8-bit Viewer"
                            checkable: true
                            checked: MeshroomApp.default8bitViewerEnabled
                        }
                    }
                }
            }

            Viewer2D {
                id: viewer2D
                anchors.fill: parent

                viewIn3D: root.load3DMedia

                DropArea {
                    anchors.fill: parent
                    keys: ["text/uri-list"]
                    onDropped: {
                        viewer2D.loadExternal(drop.urls[0]);
                    }
                }
                Rectangle {
                    z: -1
                    anchors.fill: parent
                    color: Qt.darker(activePalette.base, 1.1)
                }
            }
        }


    }
}
