using DashiBoard: DashiBoard
using TestExtension:TestExtension
extensions = [TestExtension]
plugins = [ext.DEFAULT_PARSER for ext in extensions]
handlers, _, _ = DashiBoard.get_handlers(
    ws;
    parser = DashiBoard.Pipelines.default_parser(; plugins),
    extension_of = DashiBoard.provenance(extensions),
)
