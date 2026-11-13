using DashiBoard: DashiBoard

const WORKSPACE = @__DIR__
const CONFIG = DashiBoard.read_workspace_file(WORKSPACE)
DashiBoard.init_workspace(WORKSPACE, CONFIG)

module Extensions
    for ext in keys(parentmodule(@__MODULE__).CONFIG.extensions)
        @eval using $(Symbol(ext)): $(Symbol(ext))
    end
end

const SERVER = DashiBoard.launch(Extensions, WORKSPACE, CONFIG; async = true)
