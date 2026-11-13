using DashiBoard, Test
using DashiBase: DashiBase
using JSON: JSON
using HTTP: HTTP

@testset "resolving workspace" begin
    ws = joinpath(@__DIR__, "static", "workspace")
    r = DashiBoard.read_workspace_file(ws)
    @test r.directories.data == "data"
    @test r.directories.model == "cfg/model"
    @test r.directories.training == "trainings"
    @test r.directories.pipeline == "pipeline"
    @test r.directories.filter == "filter"

    DashiBoard.init_workspace(ws)
    for k in (:data, :model, :training, :pipeline, :filter)
        @test isdir(joinpath("static", "workspace", getproperty(r.directories, k)))
    end

    @test r.server.host == "127.0.0.1"
    @test r.server.port == 9000
    @test r.extensions == Dict("TestExtension" => DashiBoard.ExtensionConfig(is_plugin = true))
end

@testset "launching workspace" begin
    # `Extensions`, `WORKSPACE`, `CONFIG`, `SERVER` are defined in this file
    include("static/workspace/launch.jl")

    try
        handlers, _, _ = DashiBoard.get_handlers(Extensions, WORKSPACE, CONFIG)

        params = Dict("cols" => ["a"], "nodes" => String[], "groups" => String[], "include" => ["cards"])
        req = DashiBase.JSONRequest(; method = "get-card-ir", params, id = 1)
        ir = JSON.parse(JSON.json(DashiBase.apply_handlers(handlers, req)))["result"]
        funnel = only(p for p in ir["cards"]["streamliner"]["properties"] if p["key"] == "funnel")
        transforms = only(p for p in funnel["value"]["objects"][""]["properties"] if p["key"] == "input_transforms")
        @test "double" in transforms["value"]["values"]["enum"]
        # A method the extension defined is what the form describes.
        @test [p["key"] for p in funnel["value"]["objects"]["test"]["properties"]] == ["marker"]

        # test that server is running with extensions
        params = (; cols = ["a"], nodes = String[], groups = String[], include = ["cards"])
        r = HTTP.post("http://127.0.0.1:9000/rpc"; body = JSON.json((; jsonrpc = "2.0", id = 1, method = "get-card-ir", params)))
        funnel = only(p for p in JSON.parse(r.body)["result"]["cards"]["streamliner"]["properties"] if p["key"] == "funnel")
        @test haskey(funnel["value"]["objects"], "test")
    finally
        close(SERVER)
    end
end
