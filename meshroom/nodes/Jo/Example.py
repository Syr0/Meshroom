__version__ = "1.0"

from meshroom.core import desc
import os.path

class Example(desc.AVCommandLineNode):
    commandLine = 'Example {allParams}'
    size = desc.DynamicNodeSize('input')

    category = 'Utils'
    documentation = '''
Assumes the input SfMData describes a set of cameras capturing a scene at a common time. Transformd the set of cameras into a rig of cameras.
'''

    inputs = [
        desc.File(
            name="input",
            label="SfMData",
            description="Input SfMData file.",
            value="",
            uid=[0],
        ),
        desc.ChoiceParam(
            name="verboseLevel",
            label="Verbose Level",
            description="Verbosity level (fatal, error, warning, info, debug, trace).",
            value="info",
            values=["fatal", "error", "warning", "info", "debug", "trace"],
            exclusive=True,
            uid=[],
        )
    ]

    outputs = [
        desc.File(
            name="output",
            label="SfMData",
            description="Path to the output SfM file (in SfMData format).",
            value=lambda attr: desc.Node.internalFolder + "sfmData.sfm",
            uid=[],
        ),
    ]
