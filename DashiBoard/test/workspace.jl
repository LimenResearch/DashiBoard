using DashiBoard, Test

mktempdir() do ws
    static_dir = joinpath(@__DIR__, "static")
    cp(joinpath(static_dir, "workspace", "dashiboard.toml"), joinpath(ws, "dashiboard.toml"))
    DashiBoard.init_workspace(ws)

    @testset "resolving a workspace" begin
        r = DashiBoard.read_workspace_file(ws)
        @test r.directories.data == "data"
        @test r.directories.model == "cfg/model"
        @test r.directories.training == "trainings"
        @test r.directories.pipeline == "pipeline"
        @test r.directories.filter == "filter"

        for k in (:data, :model, :training, :pipeline, :filter)
            @test isdir(joinpath(ws, getproperty(r.directories, k)))
        end

        @test isnothing(r.server.host)
        @test r.server.port == 9000
        @test r.extensions == Dict("TestExtension" => "7b1f0c3e-5d2a-4f6b-9e8c-1a2b3c4d5e6f")
    end

    DashiBoard.generate_launcher(ws)
    @test read(joinpath(ws, "main.jl"), String) == read(joinpath(static_dir, "workspace", "launcher.jl"), String)

    include("static/workspace/launcher.jl")
    # handlers are defined in the above file
    params = Dict("cols" => ["a"], "nodes" => String[], "groups" => String[], "include" => ["cards"])
    req = DashiBoard.DashiBase.JSONRequest(; method = "get-card-ir", params, id = 1)
    ir = JSON.parse(JSON.json(DashiBoard.DashiBase.apply_handlers(handlers, req)))["result"]
    funnel = only(p for p in ir["cards"]["streamliner"]["properties"] if p["key"] == "funnel")
    transforms = only(p for p in funnel["value"]["objects"][""]["properties"] if p["key"] == "input_transforms")
    @test "double" in transforms["value"]["values"]["enum"]
    # A method the extension defined is what the form describes.
    @test [p["key"] for p in funnel["value"]["objects"]["test"]["properties"]] == ["marker"]
end
