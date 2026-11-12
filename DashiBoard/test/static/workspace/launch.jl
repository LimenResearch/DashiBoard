using DashiBoard: DashiBoard

ws = @__DIR__

DashiBoard.init_workspace(ws)
config = DashiBoard.read_workspace_file(ws)

module Extensions
    for ext in keys(parentmodule(@__MODULE__).config.extensions)
        @eval using $(Symbol(ext)): $(Symbol(ext))
    end
end

extensions = [getglobal(Extensions, Symbol(ext)) for ext in keys(config.extensions)]
plugins = [ext.DEFAULT_PARSER for ext in extensions]

handlers, _, _ = DashiBoard.get_handlers(
    ws;
    parser = DashiBoard.default_parser(; plugins),
    extension_of = DashiBoard.provenance(extensions),
)
