
def registerTypes():
    from PySide2.QtQml import qmlRegisterType
    from meshroom.ui.components.clipboard import ClipboardHelper
    from meshroom.ui.components.edge import EdgeMouseArea
    from meshroom.ui.components.filepath import FilepathHelper
    from meshroom.ui.components.csvData import CsvData

    qmlRegisterType(EdgeMouseArea, "GraphEditor", 1, 0, "EdgeMouseArea")
    qmlRegisterType(ClipboardHelper, "Meshroom.Helpers", 1, 0, "ClipboardHelper")  # TODO: uncreatable
    qmlRegisterType(FilepathHelper, "Meshroom.Helpers", 1, 0, "FilepathHelper")  # TODO: uncreatable
    qmlRegisterType(CsvData, "DataObjects", 1, 0, "CsvData")
