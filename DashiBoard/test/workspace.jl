using DashiBoard, Test

@testset "resolving a workspace" begin
    mktempdir() do ws
        mkpath(joinpath(ws, "data")); mkpath(joinpath(ws, "model"))
        # flag → file → conventional folder → root
        r = DashiBoard.resolve_pointers(ws, Dict("directories" => Dict("model" => "cfg/models")), Dict("training_dir" => "/abs/trainings"))
        @test r.dirs[:data] == normpath(joinpath(ws, "data"))
        @test r.dirs[:model] == normpath(joinpath(ws, "cfg", "models"))          # the file wins over the folder
        @test r.dirs[:training] == "/abs/trainings"                               # the flag wins over everything
        @test r.dirs[:pipeline] == normpath(ws) && r.dirs[:filter] == normpath(ws) # nothing said: the root
        @test Set(r.fell_back) == Set([:pipeline, :filter])
        # an absolute entry in the file is taken as it is
        r = DashiBoard.resolve_pointers(ws, Dict("directories" => Dict("data" => "/mnt/tables")), Dict())
        @test r.dirs[:data] == "/mnt/tables"
        # an unknown key in the file is refused, so a typo does not silently fall back
        @test_throws ArgumentError DashiBoard.resolve_pointers(ws, Dict("directories" => Dict("models" => "x")), Dict())
        @test isempty(DashiBoard.read_workspace_file(ws))
        write(joinpath(ws, "dashiboard.toml"), "[server]\nport = 9000\n[extensions]\nX = { path = \"/opt/X\" }\n")
        file = DashiBoard.read_workspace_file(ws)
        @test DashiBoard.server_defaults(file) == (host = nothing, port = 9000)
        @test DashiBoard.extension_sources(file, Dict()) == Dict("X" => Dict{String, Any}("path" => "/opt/X"))
        # the command line names an extension as Name=path or Name=url@rev
        @test DashiBoard.extension_sources(file, Dict("extensions" => "Y=/opt/Y,Z=https://h/Z.jl@main")) ==
            Dict("Y" => Dict{String, Any}("path" => "/opt/Y"), "Z" => Dict{String, Any}("url" => "https://h/Z.jl", "rev" => "main"))
    end
end
