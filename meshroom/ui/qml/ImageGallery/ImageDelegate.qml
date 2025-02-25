import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.11
import Utils 1.0


/**
 * ImageDelegate for a Viewpoint object.
 */
Item {
    id: root

    property variant viewpoint
    property int cellID: -1
    property bool isCurrentItem: false
    property alias source: _viewpoint.source
    property alias metadata: _viewpoint.metadata
    property bool readOnly: false
    property bool displayViewId: false

    signal pressed(var mouse)
    signal removeRequest()
    signal removeAllImagesRequest()

    default property alias children: imageMA.children

    // retrieve viewpoints inner data
    QtObject {
        id: _viewpoint
        property url source: viewpoint ? Filepath.stringToUrl(viewpoint.get("path").value) : ''
        property int viewId: viewpoint ? viewpoint.get("viewId").value : -1
        property string metadataStr: viewpoint ? viewpoint.get("metadata").value : ''
        property var metadata: metadataStr ? JSON.parse(viewpoint.get("metadata").value) : {}
    }


    MouseArea {
        id: imageMA
        anchors.fill: parent
        anchors.margins: 6
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: {
            if (mouse.button == Qt.RightButton)
                imageMenu.popup()
            root.pressed(mouse)
        }

        Menu {
            id: imageMenu
            MenuItem {
                text: "Show Containing Folder"
                onClicked: {
                    Qt.openUrlExternally(Filepath.dirname(root.source))
                }
            }
            MenuItem {
                text: "Remove"
                enabled: !root.readOnly
                onClicked: removeRequest()
            }
            MenuItem {
                text: "Remove All Images"
                enabled: !root.readOnly
                onClicked: removeAllImagesRequest()
            }
            MenuItem {
                text: "Define As Center Image"
                property var activeNode: _reconstruction ? _reconstruction.activeNodes.get("SfMTransform").node : null
                enabled: !root.readOnly && _viewpoint.viewId != -1 && _reconstruction && activeNode
                onClicked: _reconstruction.setAttribute(activeNode.attribute("transformation"), _viewpoint.viewId.toString())
            }
            Menu {
                id: sfmSetPairMenu
                title: "SfM: Define Initial Pair"
                property var activeNode: _reconstruction ? _reconstruction.activeNodes.get("StructureFromMotion").node : null
                enabled: !root.readOnly && _viewpoint.viewId != -1 && _reconstruction && activeNode

                MenuItem {
                    text: "A"
                    onClicked: _reconstruction.setAttribute(sfmSetPairMenu.activeNode.attribute("initialPairA"), _viewpoint.viewId.toString())
                }

                MenuItem {
                    text: "B"
                    onClicked: _reconstruction.setAttribute(sfmSetPairMenu.activeNode.attribute("initialPairB"), _viewpoint.viewId.toString())
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Image basename
            Label {
                id: imageLabel
                Layout.fillWidth: true
                padding: 2
                font.pointSize: 8
                elide: Text.ElideMiddle
                horizontalAlignment: Text.AlignHCenter
                text: Filepath.basename(root.source)
                background: Rectangle {
                    color: root.isCurrentItem ? parent.palette.highlight : "transparent"
                }
            }

            // Image viewId
            Loader {
                active: displayViewId
                Layout.fillWidth: true
                visible: active
                sourceComponent: Label {
                    padding: imageLabel.padding
                    font.pointSize: imageLabel.font.pointSize
                    elide: imageLabel.elide
                    horizontalAlignment: imageLabel.horizontalAlignment
                    text: _viewpoint.viewId
                    background: Rectangle {
                        color: imageLabel.background.color
                    }
                }
            }
        }
    }
}
