import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.11
import MaterialIcons 2.2
import Controls 1.0

FocusScope {
    id: root

    clip: true

    property var displayedNode: null

    property bool useExternal: false
    property url sourceExternal

    property url source
    property var viewIn3D

    property Component floatViewerComp: Qt.createComponent("FloatImage.qml")
    property var useFloatImageViewer: displayHDR.checked
    property alias useLensDistortionViewer: displayLensDistortionViewer.checked // needed
    property bool enable8bitViewer: enable8bitViewerAction.checked // needed

    QtObject {
        id: m
        property variant viewpointMetadata: {
            // Metadata from viewpoint attribute
            // Read from the reconstruction object
            if (_reconstruction) {
                let vp = getViewpoint(_reconstruction.selectedViewId)
                if (vp) {
                    return JSON.parse(vp.childAttribute("metadata").value)
                }
            }
            return {}
        }
        property variant imgMetadata: {
            // Metadata from FloatImage viewer
            // Directly read from the image file on disk
            if (floatImageViewerLoader.active) {
                return floatImageViewerLoader.item.metadata
            }
            // Use viewpoint metadata for the special case of the 8-bit viewer
            if (qtImageViewerLoader.active) {
                return viewpointMetadata
            }
            return {}
        }
    }

    Loader {
        id: aliceVisionPluginLoader
        active: true
        source: "TestAliceVisionPlugin.qml"
    }

    readonly property bool aliceVisionPluginAvailable: aliceVisionPluginLoader.status === Component.Ready

    Component.onCompleted: {
        if (!aliceVisionPluginAvailable) {
            console.warn("Missing plugin qtAliceVision.")
            displayHDR.checked = false
        }
    }

    property string loadingModules: {
        if (!imgContainer.image)
            return ""
        var res = ""
        if (imgContainer.image.status === Image.Loading) {
            res += " Image"
        }
        if (mfeaturesLoader.status === Loader.Ready) {
            if (mfeaturesLoader.item && mfeaturesLoader.item.status === MFeatures.Loading)
                res += " Features"
        }
        if (mtracksLoader.status === Loader.Ready) {
            if (mtracksLoader.item && mtracksLoader.item.status === MTracks.Loading)
                res += " Tracks"
        }
        if (msfmDataLoader.status === Loader.Ready) {
            if (msfmDataLoader.item && msfmDataLoader.item.status === MSfMData.Loading)
                res += " SfMData"
        }
        return res
    }

    function clear() {
        source = ''
    }

    // slots
    Keys.onPressed: {
        if (event.key === Qt.Key_F) {
            root.fit()
            event.accepted = true
        }
    }

    // mouse area
    MouseArea {
        anchors.fill: parent
        property double factor: 1.2
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: {
            imgContainer.forceActiveFocus()
            if (mouse.button & Qt.MiddleButton || (mouse.button & Qt.LeftButton && mouse.modifiers & Qt.ShiftModifier))
                drag.target = imgContainer // start drag
        }
        onReleased: {
            drag.target = undefined // stop drag
            if (mouse.button & Qt.RightButton) {
                var menu = contextMenu.createObject(root)
                menu.x = mouse.x
                menu.y = mouse.y
                menu.open()
            }
        }
        onWheel: {
            var zoomFactor = wheel.angleDelta.y > 0 ? factor : 1 / factor

            if (Math.min(imgContainer.width, imgContainer.image.height) * imgContainer.scale * zoomFactor < 10)
                return
            var point = mapToItem(imgContainer, wheel.x, wheel.y)
            imgContainer.x += (1-zoomFactor) * point.x * imgContainer.scale
            imgContainer.y += (1-zoomFactor) * point.y * imgContainer.scale
            imgContainer.scale *= zoomFactor
        }
    }

    onEnable8bitViewerChanged: {
        if (!enable8bitViewer) {
            displayHDR.checked = true
        }
    }

    // functions
    function fit() {
        // make sure the image is ready for use
        if (!imgContainer.image)
            return

        // for Exif orientation tags 5 to 8, a 90 degrees rotation is applied
        // therefore image dimensions must be inverted
        let dimensionsInverted = ["5", "6", "7", "8"].includes(imgContainer.orientationTag)
        let orientedWidth = dimensionsInverted ? imgContainer.image.height : imgContainer.image.width
        let orientedHeight = dimensionsInverted ? imgContainer.image.width : imgContainer.image.height

        // fit oriented image
        imgContainer.scale = Math.min(imgLayout.width / orientedWidth, root.height / orientedHeight)
        imgContainer.x = Math.max((imgLayout.width - orientedWidth * imgContainer.scale) * 0.5, 0)
        imgContainer.y = Math.max((imgLayout.height - orientedHeight * imgContainer.scale) * 0.5, 0)

        // correct position when image dimensions are inverted
        // so that container center corresponds to image center
        imgContainer.x += (orientedWidth - imgContainer.image.width) * 0.5 * imgContainer.scale
        imgContainer.y += (orientedHeight - imgContainer.image.height) * 0.5 * imgContainer.scale
    }

    function tryLoadNode(node) {
        useExternal = false

        // safety check
        if (!node) {
            return false
        }

        // node must be computed or at least running
        if (!node.isPartiallyFinished()) {
            return false
        }

        // node must have at least one output attribute with the image semantic
        if (!node.hasImageOutput) {
            return false
        }

        displayedNode = node
        return true
    }

    function loadExternal(path) {
        useExternal = true
        sourceExternal = path
        displayedNode = null
    }

    function getViewpoint(viewId) {
        // Get viewpoint from cameraInit with matching id
        // This requires to loop over all viewpoints

        for (var i = 0; i < _reconstruction.viewpoints.count; i++) {
            var vp = _reconstruction.viewpoints.at(i)
            if (vp.childAttribute("viewId").value == viewId) {
                return vp
            }
        }

        return undefined
    }

    function getAttributeByName(node, attrName) {
        // Get attribute from given node by name
        // This requires to loop over all atributes

        for (var i = 0; i < node.attributes.count; i++) {
            var attr = node.attributes.at(i)
            if (attr.name == attrName) {
                return attr
            }
        }

        return undefined
    }

    function resolve(path, vp) {
        // Resolve dynamic path that depends on viewpoint

        let replacements = {
            "<VIEW_ID>": vp.childAttribute("viewId").value,
            "<INTRINSIC_ID>": vp.childAttribute("intrinsicId").value,
            "<POSE_ID>": vp.childAttribute("poseId").value,
            "<PATH>": vp.childAttribute("path").value,
            "<FILENAME>": Filepath.removeExtension(Filepath.basename(vp.childAttribute("path").value)),
        }

        let resolved = path;
        for (let key in replacements) {
            resolved = resolved.replace(key, replacements[key])
        }

        return resolved;
    }

    function getImageFile() {
        // Entry point for getting the image file URL

        if (useExternal) {
            return sourceExternal
        }

        if (_reconstruction && (!displayedNode || outputAttribute.name == "gallery")) {
            let vp = getViewpoint(_reconstruction.pickedViewId)
            let path = vp ? vp.childAttribute("path").value : ""
            return Filepath.stringToUrl(path)
        }

        if (_reconstruction) {
            let vp = getViewpoint(_reconstruction.pickedViewId)
            let attr = getAttributeByName(displayedNode, outputAttribute.name)
            let path = attr ? attr.value : ""
            let resolved = vp ? resolve(path, vp) : ""
            return Filepath.stringToUrl(resolved)
        }

        return undefined
    }

    onDisplayedNodeChanged: {
        if (!displayedNode) {
            root.source = ""
        }

        // update output attribute names
        var names = []
        if (displayedNode) {
            // store attr name for output attributes that represent images
            for (var i = 0; i < displayedNode.attributes.count; i++) {
                var attr = displayedNode.attributes.at(i)
                if (attr.isOutput && attr.desc.semantic === "image" && attr.enabled) {
                    names.push(attr.name)
                }
            }
        }
        names.push("gallery")
        outputAttribute.names = names

        root.source = getImageFile()
    }

    Connections {
        target: _reconstruction
        function onSelectedViewIdChanged() {
            root.source = getImageFile()
            if (useExternal)
                useExternal = false
        }
    }

    Connections {
        target: displayedNode
        function onOutputAttrEnabledChanged() {
            tryLoadNode(displayedNode)
        }
    }

    // context menu
    property Component contextMenu: Menu {
        MenuItem {
            text: "Fit"
            onTriggered: fit()
        }
        MenuItem {
            text: "Zoom 100%"
            onTriggered: {
                imgContainer.scale = 1
                imgContainer.x = Math.max((imgLayout.width - imgContainer.width * imgContainer.scale) * 0.5, 0)
                imgContainer.y = Math.max((imgLayout.height - imgContainer.height * imgContainer.scale) * 0.5, 0)
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent

        // Image
        Item {
            id: imgLayout
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            Image {
                id: alphaBackground
                anchors.fill: parent
                visible: displayAlphaBackground.checked
                fillMode: Image.Tile
                horizontalAlignment: Image.AlignLeft
                verticalAlignment: Image.AlignTop
                source: "../../img/checkerboard_light.png"
                scale: 4
                smooth: false
            }

            Item {
                id: imgContainer
                transformOrigin: Item.TopLeft
                property var orientationTag: m.imgMetadata ? m.imgMetadata["Orientation"] : 0

                // qtAliceVision Image Viewer
                ExifOrientedViewer {
                    id: floatImageViewerLoader
                    active: root.aliceVisionPluginAvailable && (root.useFloatImageViewer || root.useLensDistortionViewer)
                    visible: (floatImageViewerLoader.status === Loader.Ready) && active
                    anchors.centerIn: parent
                    orientationTag: imgContainer.orientationTag
                    xOrigin: imgContainer.width / 2
                    yOrigin: imgContainer.height / 2
                    property bool fittedOnce: false
                    property int previousWidth: 0
                    property int previousHeight: 0
                    property real targetSize: Math.max(width, height) * imgContainer.scale
                    onHeightChanged: {
                        /* Image size is not updated through a single signal with the floatImage viewer, unlike
                         * the simple QML image viewer: instead of updating straight away the width and height to x and
                         * y, the emitted signals look like:
                         * - width = -1, height = -1
                         * - width = x, height = -1
                         * - width = x, height = y
                         * We want to do the auto-fit on the first display of an image from the group, and then keep its
                         * scale when displaying another image from the group, so we need to know if an image in the
                         * group has already been auto-fitted. If we change the group of images (when another project is
                         * opened, for example, and the images have a different size), then another auto-fit needs to be
                         * performed */
                        if ((!fittedOnce && imgContainer.image && imgContainer.image.height > 0) ||
                            (fittedOnce && ((width > 1 && previousWidth != width) || (height > 1 && previousHeight != height)))) {
                            fit()
                            fittedOnce = true
                            previousWidth = width
                            previousHeight = height
                        }
                    }

                    onActiveChanged: {
                        if (active) {
                            // Instantiate and initialize a FLoatImage component dynamically using Loader.setSource
                            // Note: It does not work to use previously created component, so we re-create it with setSource.
                            setSource("FloatImage.qml", {
                                'source':  Qt.binding(function() { return getImageFile() }),
                                'viewerTypeString': Qt.binding(function() { return displayLensDistortionViewer.checked ? "distortion" : "hdr" }),
                                'sfmRequired': Qt.binding(function() { return displayLensDistortionViewer.checked ? true : false }),
                                'surface.msfmData': Qt.binding(function() { return (msfmDataLoader.status === Loader.Ready && msfmDataLoader.item != null && msfmDataLoader.item.status === 2) ? msfmDataLoader.item : null }),
                                'canBeHovered': false,
                                'idView': Qt.binding(function() { return (_reconstruction ? _reconstruction.selectedViewId : -1) }),
                                'cropFisheye': false,
                                'targetSize': Qt.binding(function() { return floatImageViewerLoader.targetSize }),
                            })
                        } else {
                            setSource("", {})
                            fittedOnce = false
                        }
                    }
                }

                ExifOrientedViewer {
                    id: qtImageViewerLoader
                    active: !floatImageViewerLoader.active
                    anchors.centerIn: parent
                    orientationTag: imgContainer.orientationTag
                    xOrigin: imgContainer.width / 2
                    yOrigin: imgContainer.height / 2
                    sourceComponent: Image {
                        id: qtImageViewer
                        asynchronous: true
                        smooth: false
                        fillMode: Image.PreserveAspectFit
                        onWidthChanged: if (status==Image.Ready) fit()
                        source: getImageFile()
                        onStatusChanged: {
                            // update cache source when image is loaded
                            if (status === Image.Ready)
                                qtImageViewerCache.source = source
                        }

                        // Image cache of the last loaded image
                        // Only visible when the main one is loading, to maintain a displayed image for smoother transitions
                        Image {
                            id: qtImageViewerCache

                            anchors.fill: parent
                            asynchronous: true
                            smooth: parent.smooth
                            fillMode: parent.fillMode

                            visible: qtImageViewer.status === Image.Loading
                        }
                    }
                }

                property var image: {
                    if (floatImageViewerLoader.active)
                        floatImageViewerLoader.item
                    else
                        qtImageViewerLoader.item
                }
                width: image ? (image.width > 0 ? image.width : 1) : 1
                height: image ? (image.height > 0 ? image.height : 1) : 1
                scale: 1.0

                // FeatureViewer: display view extracted feature points
                // note: requires QtAliceVision plugin - use a Loader to evaluate plugin availability at runtime
                ExifOrientedViewer {
                    id: featuresViewerLoader
                    active: displayFeatures.checked
                    property var activeNode: _reconstruction ? _reconstruction.activeNodes.get("featureProvider").node : null
                    width: imgContainer.width
                    height: imgContainer.height
                    anchors.centerIn: parent
                    orientationTag: imgContainer.orientationTag
                    xOrigin: imgContainer.width / 2
                    yOrigin: imgContainer.height / 2

                    onActiveChanged: {
                        if (active) {
                            // Instantiate and initialize a FeaturesViewer component dynamically using Loader.setSource
                            setSource("FeaturesViewer.qml", {
                                'model': Qt.binding(function() { return activeNode ? activeNode.attribute("describerTypes").value : "" }),
                                'currentViewId': Qt.binding(function() { return _reconstruction.selectedViewId }),
                                'features': Qt.binding(function() { return mfeaturesLoader.status === Loader.Ready ? mfeaturesLoader.item : null }),
                                'tracks': Qt.binding(function() { return mtracksLoader.status === Loader.Ready ? mtracksLoader.item : null }),
                                'sfmData': Qt.binding(function() { return msfmDataLoader.status === Loader.Ready ? msfmDataLoader.item : null }),
                            })
                        } else {
                            // Forcing the unload (instead of using Component.onCompleted to load it once and for all) is necessary since Qt 5.14
                            setSource("", {})
                        }
                    }
                }

            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                FloatingPane {
                    id: imagePathToolbar
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: childrenRect.height
                    visible: displayImagePathAction.checked

                    RowLayout {
                        width: parent.width
                        height: childrenRect.height

                        // selectable filepath to source image
                        TextField {
                            padding: 0
                            background: Item {}
                            horizontalAlignment: TextInput.AlignLeft
                            Layout.fillWidth: true
                            height: contentHeight
                            font.pointSize: 8
                            readOnly: true
                            selectByMouse: true
                            text: Filepath.urlToString(getImageFile())
                        }

                        // write which node is being displayed
                        Label {
                            id: displayedNodeName
                            text: root.displayedNode ? root.displayedNode.label : ""
                            font.pointSize: 8

                            horizontalAlignment: TextInput.AlignLeft
                            Layout.fillWidth: false
                            Layout.preferredWidth: contentWidth
                            height: contentHeight
                        }

                        // button to clear currently displayed node
                        MaterialToolButton {
                            id: clearDisplayedNode
                            text: MaterialIcons.close
                            ToolTip.text: "Clear node"
                            enabled: root.displayedNode
                            visible: root.displayedNode
                            onClicked: {
                                root.displayedNode = null
                            }
                        }
                    }
                }

                FloatingPane {
                    id: bottomToolbar
                    padding: 4
                    Layout.fillWidth: true
                    Layout.preferredHeight: childrenRect.height

                    RowLayout {
                        anchors.fill: parent

                        // Label for the number field
                        Label {
                            text: "Umlauflänge"
                            Layout.alignment: Qt.AlignVCenter
                        }

                        SpinBox {
                            id: umlaufLaengeSpinBox
                            from: 0
                            to: 99999
                            stepSize: 1
                            editable: true

                            MouseArea {
                                id: dragMouseArea
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton

                                property int initialX: 0
                                property int initialY: 0
                                property bool isDragging: false

                                onPressed: {
                                    initialX = mouseX
                                    initialY = mouseY
                                    isDragging = false // Initially false until movement is detected
                                }

                                onPositionChanged: {
                                    if (Math.abs(mouseX - initialX) > 5 || Math.abs(mouseY - initialY) > 5) { // Threshold to start drag
                                        isDragging = true
                                    }

                                    if (isDragging) {
                                        var deltaX = mouseX - initialX
                                        var deltaY = mouseY - initialY

                                        // Adjust value based on horizontal movement
                                        umlaufLaengeSpinBox.value += deltaX > 0 ? 1 : -1

                                        // Reset initial positions for continuous movement
                                        initialX = mouseX
                                        initialY = mouseY
                                    }
                                }

                                onReleased: {
                                    isDragging = false
                                }
                            }

                            onValueChanged: alphaChange()
                        }


                        // zoom label
                        MLabel {
                            text: ((imgContainer.image && (imgContainer.image.status === Image.Ready)) ? imgContainer.scale.toFixed(2) : "1.00") + "x"
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: {
                                    if (mouse.button & Qt.LeftButton) {
                                        fit()
                                    } else if (mouse.button & Qt.RightButton) {
                                        var menu = contextMenu.createObject(root)
                                        var point = mapToItem(root, mouse.x, mouse.y)
                                        menu.x = point.x
                                        menu.y = point.y
                                        menu.open()
                                    }
                                }
                            }
                            ToolTip.text: "Zoom"
                        }
                        MaterialToolButton {
                            id: displayAlphaBackground
                            ToolTip.text: "Alpha Background"
                            text: MaterialIcons.texture
                            font.pointSize: 11
                            Layout.minimumWidth: 0
                            checkable: true
                        }
                        MaterialToolButton
                        {
                            id: displayHDR
                            ToolTip.text: "High-Dynamic-Range Image Viewer"
                            text: MaterialIcons.hdr_on
                            // larger font but smaller padding,
                            // so it is visually similar.
                            font.pointSize: 20
                            padding: 0
                            Layout.minimumWidth: 0
                            checkable: true
                            checked: root.aliceVisionPluginAvailable
                            enabled: root.aliceVisionPluginAvailable
                            visible: root.enable8bitViewer
                            onCheckedChanged : {
                                if (displayLensDistortionViewer.checked && checked) {
                                    displayLensDistortionViewer.checked = false
                                }
                                root.useFloatImageViewer = !root.useFloatImageViewer
                            }
                        }
                        MaterialToolButton {
                            id: displayLensDistortionViewer
                            property var activeNode: root.aliceVisionPluginAvailable && _reconstruction ? _reconstruction.activeNodes.get('sfmData').node : null
                            property bool isComputed: {
                                if (!activeNode)
                                    return false
                                if (activeNode.isComputed)
                                    return true
                                if (!activeNode.hasAttribute("input"))
                                    return false
                                var inputAttr = activeNode.attribute("input")
                                var inputAttrLink = inputAttr.rootLinkParam
                                if (!inputAttrLink)
                                    return false
                                return inputAttrLink.node.isComputed
                            }

                            ToolTip.text: "Lens Distortion Viewer" + (isComputed ? (": " + activeNode.label) : "")
                            text: MaterialIcons.panorama_horizontal
                            font.pointSize: 16
                            padding: 0
                            Layout.minimumWidth: 0
                            checkable: true
                            checked: false
                            enabled: activeNode && isComputed
                            onCheckedChanged : {
                                if ((displayHDR.checked) && checked) {
                                    displayHDR.checked = false
                                } else if (!checked) {
                                    displayHDR.checked = true
                                }
                            }
                        }

                        MaterialToolButton {
                            id: displayFeatures
                            ToolTip.text: "Display Features"
                            text: MaterialIcons.scatter_plot
                            font.pointSize: 11
                            Layout.minimumWidth: 0
                            checkable: true
                            checked: false
                            enabled: root.aliceVisionPluginAvailable
                            onEnabledChanged : {
                                if (enabled == false) checked = false
                            }
                        }

                        Label {
                            id: resolutionLabel
                            Layout.fillWidth: true
                            text: (imgContainer.image && imgContainer.image.sourceSize.width > 0) ? (imgContainer.image.sourceSize.width + "x" + imgContainer.image.sourceSize.height) : ""

                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }

                        ComboBox {
                            id: outputAttribute
                            clip: true
                            Layout.minimumWidth: 0
                            flat: true

                            property var names: ["gallery"]
                            property string name: names[currentIndex]

                            model: names.map(n => (n === "gallery") ? "Image Gallery" : displayedNode.attributes.get(n).label)
                            enabled: count > 1

                            FontMetrics {
                                id: fontMetrics
                            }
                            Layout.preferredWidth: model.reduce((acc, label) => Math.max(acc, fontMetrics.boundingRect(label).width), 0) + 3.0 * Qt.application.font.pixelSize

                            onNameChanged: {
                                root.source = getImageFile()
                            }
                        }

                        MaterialToolButton {
                            id: displayImageOutputIn3D
                            enabled: root.aliceVisionPluginAvailable && _reconstruction && displayedNode && Filepath.basename(root.source).includes("depthMap")
                            ToolTip.text: "View Depth Map in 3D"
                            text: MaterialIcons.input
                            font.pointSize: 11
                            Layout.minimumWidth: 0

                            onClicked: {
                                root.viewIn3D(
                                    root.source,
                                    displayedNode.name + ":" + outputAttribute.name + " " + String(_reconstruction.selectedViewId)
                                )
                            }
                        }

                        MaterialToolButton {
                            id: displaySfmStatsView
                            property var activeNode: root.aliceVisionPluginAvailable && _reconstruction ? _reconstruction.activeNodes.get('sfm').node : null
                            property bool isComputed: activeNode && activeNode.isComputed

                            font.family: MaterialIcons.fontFamily
                            text: MaterialIcons.assessment

                            ToolTip.text: "StructureFromMotion Statistics" + (isComputed ? (": " + activeNode.label) : "")
                            ToolTip.visible: hovered

                            font.pointSize: 14
                            padding: 2
                            smooth: false
                            flat: true
                            checkable: enabled
                            enabled: activeNode && activeNode.isComputed && _reconstruction.selectedViewId >= 0
                            onCheckedChanged: {
                                if (checked == true) {
                                    displaySfmDataGlobalStats.checked = false
                                    metadataCB.checked = false
                                    displayColorCheckerViewerLoader.checked = false
                                }
                            }
                        }

                        MaterialToolButton {
                            id: displaySfmDataGlobalStats
                            property var activeNode: root.aliceVisionPluginAvailable && _reconstruction ? _reconstruction.activeNodes.get('sfm').node : null
                            property bool isComputed: activeNode && activeNode.isComputed

                            font.family: MaterialIcons.fontFamily
                            text: MaterialIcons.language

                            ToolTip.text: "StructureFromMotion Global Statistics" + (isComputed ? (": " + activeNode.label) : "")
                            ToolTip.visible: hovered

                            font.pointSize: 14
                            padding: 2
                            smooth: false
                            flat: true
                            checkable: enabled
                            enabled: activeNode && activeNode.isComputed
                            onCheckedChanged: {
                                if (checked == true) {
                                    displaySfmStatsView.checked = false
                                    metadataCB.checked = false
                                    displayColorCheckerViewerLoader.checked = false
                                }
                            }
                        }
                        MaterialToolButton {
                            id: metadataCB

                            font.family: MaterialIcons.fontFamily
                            text: MaterialIcons.info_outline

                            ToolTip.text: "Image Metadata"
                            ToolTip.visible: hovered

                            font.pointSize: 14
                            padding: 2
                            smooth: false
                            flat: true
                            checkable: enabled
                            onCheckedChanged: {
                                if (checked == true) {
                                    displaySfmDataGlobalStats.checked = false
                                    displaySfmStatsView.checked = false
                                    displayColorCheckerViewerLoader.checked = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Busy indicator
    BusyIndicator {
        anchors.centerIn: parent
        // running property binding seems broken, only dynamic binding assignment works
        Component.onCompleted: {
            running = Qt.binding(function() {
                return (imgContainer.image && imgContainer.image.allImagesLoaded === false)
                    || (imgContainer.image && imgContainer.image.status === Image.Loading)
            })
        }
        // disable the visibility when unused to avoid stealing the mouseEvent to the image color picker
        visible: running
    }
}
