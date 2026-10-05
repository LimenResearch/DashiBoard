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

using JSON: JSON

@testset "sorting a plain folder into a workspace" begin
    mktempdir() do dir
        cards = Dict("nodes" => [], "groups" => Dict{String, Any}())
        filters = Dict("numerical" => Dict(), "categorical" => Dict())
        write(joinpath(dir, "t.csv"), "a,b\n1,2\n")
        write(joinpath(dir, "p.json"), JSON.json(cards))
        write(joinpath(dir, "f.json"), JSON.json(filters))
        write(joinpath(dir, "tbl.json"), JSON.json([Dict("a" => 1)]))
        write(joinpath(dir, "m.toml"), "name = \"m\"\n[components]\nmodel = []\n")
        write(joinpath(dir, "tr.toml"), "iterations = 3\n[optimizer]\nname = \"Adam\"\n")
        write(joinpath(dir, "odd.toml"), "just = 1\n")
        write(joinpath(dir, "note.md"), "neither")
        write(joinpath(dir, ".hidden"), "left alone")
        mkpath(joinpath(dir, "stuff")); write(joinpath(dir, "stuff", "x.bin"), "stray folder")
        write(joinpath(dir, "pipeline"), "a file where the folder must go")
        mkpath(joinpath(dir, "data")); write(joinpath(dir, "data", "t.csv"), "already,here\n")

        io = IOBuffer()
        report = DashiBoard.init_workspace(dir; io)
        at(parts...) = joinpath(dir, parts...)
        @test isfile(at("pipeline", "p.json")) && isfile(at("filter", "f.json"))
        @test isfile(at("data", "tbl.json")) && isfile(at("model", "m.toml")) && isfile(at("training", "tr.toml"))
        # What cannot be placed is kept, in quarantine, with its name.
        @test isfile(at("quarantine", "odd.toml")) && isfile(at("quarantine", "note.md"))
        @test isfile(at("quarantine", "stuff", "x.bin")) && isfile(at("quarantine", "pipeline"))
        @test read(at("data", "t.csv"), String) == "already,here\n"          # the one there first stays
        @test isfile(at("quarantine", "t.csv"))                               # the clash is quarantined
        @test isfile(at(".hidden")) && isdir(at("pipeline"))
        @test sort(readdir(dir)) == [".hidden", "dashiboard.toml", "data", "filter", "model", "pipeline", "quarantine", "training"]
        @test DashiBoard.read_workspace_file(dir)["directories"] == Dict(k => k for k in ("data", "pipeline", "filter", "model", "training"))
        @test Set(first.(report.placed)) == Set(["p.json", "f.json", "tbl.json", "m.toml", "tr.toml"])
        @test Set(first.(report.quarantined)) == Set(["odd.toml", "note.md", "stuff", "pipeline", "t.csv"])
        text = String(take!(io))
        @test occursin("p.json", text) && occursin("quarantine", text) && occursin("odd.toml", text)

        # A second run finds nothing loose and moves nothing.
        again = DashiBoard.init_workspace(dir; io = devnull)
        @test isempty(again.placed) && isempty(again.quarantined)
        # A clash inside quarantine keeps both.
        write(joinpath(dir, "odd.toml"), "again = 2\n")
        DashiBoard.init_workspace(dir; io = devnull)
        @test isfile(at("quarantine", "odd-2.toml"))
    end
end
