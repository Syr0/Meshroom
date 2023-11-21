# Multiview pipeline version
__version__ = "2.2"

import os

from meshroom.core.graph import Graph, GraphModification

class FilesByType:
    def __init__(self):
        self.audio = []
        self.binary = []
        self.ascii_binary = []
        self.other = []

    def __bool__(self):
        return self.audio or self.binary or self.ascii_binary

    def extend(self, other):
        self.audio.extend(other.audio)
        self.binary.extend(other.binary)
        self.ascii_binary.extend(other.ascii_binary)
        self.other.extend(other.other)

    def addFile(self, file):
            self.other.append(file)

    def addFiles(self, files):
        for file in files:
            self.addFile(file)


def findFilesByTypeInFolder(folder, recursive=False):
    """
    Return all files that are images in 'folder' based on their extensions.

    Args:
        folder (str): folder to look into or list of folder/files

    Returns:
        list: the list of image files with a supported extension.
    """
    inputFolders = []
    if isinstance(folder, (list, tuple)):
        inputFolders = folder
    else:
        inputFolders.append(folder)

    output = FilesByType()
    for currentFolder in inputFolders:
        if os.path.isfile(currentFolder):
            output.addFile(currentFolder)
            continue
        elif os.path.isdir(currentFolder):
            if recursive:
                for root, directories, files in os.walk(currentFolder):
                    for filename in files:
                        output.addFile(os.path.join(root, filename))
            else:
                output.addFiles([os.path.join(currentFolder, filename) for filename in os.listdir(currentFolder)])
        else:
            # if not a directory or a file, it may be an expression
            import glob
            paths = glob.glob(currentFolder)
            filesByType = findFilesByTypeInFolder(paths, recursive=recursive)
            output.extend(filesByType)

    return output


def mvsPipeline(graph, sfm=None):
    """
    Instantiate a MVS pipeline inside 'graph'.

    Args:
        graph (Graph/UIGraph): the graph in which nodes should be instantiated
        sfm (Node, optional): if specified, connect the MVS pipeline to this StructureFromMotion node

    Returns:
        list of Node: the created nodes
    """
    if sfm and not sfm.nodeType == "StructureFromMotion":
        raise ValueError("Invalid node type. Expected StructureFromMotion, got {}.".format(sfm.nodeType))

    prepareDenseScene = graph.addNewNode('PrepareDenseScene',
                                         input=sfm.output if sfm else "")
    depthMap = graph.addNewNode('DepthMap',
                                input=prepareDenseScene.input,
                                imagesFolder=prepareDenseScene.output)
    depthMapFilter = graph.addNewNode('DepthMapFilter',
                                      input=depthMap.input,
                                      depthMapsFolder=depthMap.output)
    meshing = graph.addNewNode('Meshing',
                               input=depthMapFilter.input,
                               depthMapsFolder=depthMapFilter.output)
    meshFiltering = graph.addNewNode('MeshFiltering',
                                     inputMesh=meshing.outputMesh)
    texturing = graph.addNewNode('Texturing',
                                 input=meshing.output,
                                 imagesFolder=depthMap.imagesFolder,
                                 inputMesh=meshFiltering.outputMesh)

    return [
        prepareDenseScene,
        depthMap,
        depthMapFilter,
        meshing,
        meshFiltering,
        texturing
    ]


def sfmAugmentation(graph, sourceSfm, withMVS=False):
    """
    Create a SfM augmentation inside 'graph'.

    Args:
        graph (Graph/UIGraph): the graph in which nodes should be instantiated
        sourceSfm (Node, optional): if specified, connect the MVS pipeline to this StructureFromMotion node
        withMVS (bool): whether to create a MVS pipeline after the augmented SfM branch

    Returns:
        tuple: the created nodes (sfmNodes, mvsNodes)
    """
    cameraInit = graph.addNewNode('CameraInit')

    featureExtraction = graph.addNewNode('FeatureExtraction',
                                         input=cameraInit.output)
    imageMatchingMulti = graph.addNewNode('ImageMatchingMultiSfM',
                                          input=featureExtraction.input,
                                          featuresFolders=[featureExtraction.output]
                                          )
    featureMatching = graph.addNewNode('FeatureMatching',
                                       input=imageMatchingMulti.outputCombinedSfM,
                                       featuresFolders=imageMatchingMulti.featuresFolders,
                                       imagePairsList=imageMatchingMulti.output,
                                       describerTypes=featureExtraction.describerTypes)
    structureFromMotion = graph.addNewNode('StructureFromMotion',
                                           input=featureMatching.input,
                                           featuresFolders=featureMatching.featuresFolders,
                                           matchesFolders=[featureMatching.output],
                                           describerTypes=featureMatching.describerTypes)
    graph.addEdge(sourceSfm.output, imageMatchingMulti.inputB)

    sfmNodes = [
        cameraInit,
        featureExtraction,
        imageMatchingMulti,
        featureMatching,
        structureFromMotion
    ]

    mvsNodes = []

    if withMVS:
        mvsNodes = mvsPipeline(graph, structureFromMotion)

    return sfmNodes, mvsNodes
