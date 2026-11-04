using DashiBoard, Test, HTTP
using TOML: TOML

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
        # A flag is what the user typed where they stand, so a relative one is read from there;
        # an entry of the file is read from the file. Neither keeps a trailing separator, which
        # would make one folder look like two.
        cd(ws) do
            r = DashiBoard.resolve_pointers(ws, Dict("directories" => Dict("data" => "data/")), Dict("model_dir" => "model/"))
            @test r.dirs[:model] == joinpath(realpath(ws), "model") || r.dirs[:model] == normpath(joinpath(pwd(), "model"))
            @test r.dirs[:data] == normpath(joinpath(ws, "data"))
            @test !endswith(r.dirs[:model], "/") && !endswith(r.dirs[:data], "/")
        end
        mktempdir() do elsewhere
            cd(elsewhere) do
                r = DashiBoard.resolve_pointers(ws, Dict(), Dict("model_dir" => "static/model"))
                @test r.dirs[:model] == normpath(joinpath(pwd(), "static", "model"))
                # A directory that was named and is not there is said at launch, by name.
                @test DashiBoard.missing_directories(r.dirs) == [:model => r.dirs[:model]]
            end
        end
        @test isempty(DashiBoard.missing_directories(DashiBoard.resolve_pointers(ws, Dict(), Dict()).dirs))
        # an absolute entry in the file is taken as it is
        r = DashiBoard.resolve_pointers(ws, Dict("directories" => Dict("data" => "/mnt/tables")), Dict())
        @test r.dirs[:data] == "/mnt/tables"
        # an unknown key in the file is refused, so a typo does not silently fall back
        @test_throws ArgumentError DashiBoard.resolve_pointers(ws, Dict("directories" => Dict("models" => "x")), Dict())
        @test isempty(DashiBoard.read_workspace_file(ws))
        write(joinpath(ws, "dashiboard.toml"), "[server]\nport = 9000\n[extensions]\nX = { url = \"https://h/X.jl\", rev = \"v1\" }\n")
        file = DashiBoard.read_workspace_file(ws)
        @test DashiBoard.server_defaults(file) == (host = nothing, port = 9000)
        @test DashiBoard.extension_sources(file) == Dict("X" => Dict{String, Any}("url" => "https://h/X.jl", "rev" => "v1"))

        # A workspace file that says something the launcher cannot read is refused by name,
        # rather than half-used: a misspelt table, a value of the wrong kind.
        bad(text) = (write(joinpath(ws, "dashiboard.toml"), text); DashiBoard.read_workspace_file(ws))
        @test_throws ArgumentError bad("[extentions]\nX = { path = \"/x\" }\n")
        @test_throws ArgumentError bad("[server]\nport = \"8080\"\n")
        @test_throws ArgumentError bad("[extensions]\nX = \"/opt/X\"\n")
        @test_throws ArgumentError bad("[extensions]\nX = { branch = \"main\" }\n")
        @test_throws ArgumentError bad("[directories]\ndata = 3\n")
        rm(joinpath(ws, "dashiboard.toml"))
    end

    # A deployment pins every source to a release: DashiBoard and each extension by url and rev,
    # never by a path, whose code could change under a fixed Manifest.
    ok = Dict("dashiboard" => Dict("url" => "https://x/DashiBoard", "rev" => "v2.0.0"))
    @test DashiBoard.dashiboard_source(DashiBoard.WorkspaceUtils.check_workspace_file(ok, "f")) == (; url = "https://x/DashiBoard", rev = "v2.0.0")
    for (bad, says) in (
            Dict("dashiboard" => Dict("path" => "/opt/D")) => "[dashiboard]",
            Dict("dashiboard" => Dict("url" => "https://x/D")) => "rev",
            Dict("extensions" => Dict("E" => Dict("path" => "e"))) => "[extensions].E",
            Dict("extensions" => Dict("E" => Dict("url" => "https://x/E"))) => "rev",
        )
        e = @test_throws ArgumentError DashiBoard.WorkspaceUtils.check_workspace_file(bad, "f")
        @test occursin(says, e.value.msg)
    end
    @test_throws ArgumentError DashiBoard.dashiboard_source(Dict{String, Any}())
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
        @test occursin("odd.toml → quarantine/", text)
        again = DashiBoard.init_workspace(dir; io = devnull)
        @test isempty(again.placed) && isempty(again.quarantined)
        # A clash inside quarantine keeps both.
        write(joinpath(dir, "odd.toml"), "again = 2\n")
        DashiBoard.init_workspace(dir; io = devnull)
        @test isfile(at("quarantine", "odd-2.toml"))
    end
end

@testset "sorting: the awkward cases" begin
    mktempdir() do dir
        # A file named like the quarantine itself, a pipeline written as TOML, and a link.
        write(joinpath(dir, "quarantine"), "a file in the quarantine's place")
        write(joinpath(dir, "p.toml"), "groups = {}\nnodes = []\n")
        write(joinpath(dir, "note.md"), "x")
        symlink("somewhere/else", joinpath(dir, "link"))
        io = IOBuffer()
        report = DashiBoard.init_workspace(dir; io)
        @test isdir(joinpath(dir, "quarantine")) && isfile(joinpath(dir, "quarantine", "quarantine"))
        @test isfile(joinpath(dir, "pipeline", "p.toml"))                 # the Load tab would offer it
        @test islink(joinpath(dir, "link"))                               # moving it would break it
        @test ("link", "a link, left where it is") in report.left
        @test occursin("link", String(take!(io)))
    end
end

@testset "sorting a workspace that names its own folders" begin
    mktempdir() do dir
        # The workspace file already says where the tables are: that folder is the layout's, and
        # a loose table goes there.
        write(joinpath(dir, "dashiboard.toml"), "[directories]\ndata = \"tables\"\n")
        mkpath(joinpath(dir, "tables")); write(joinpath(dir, "tables", "old.csv"), "a\n1\n")
        write(joinpath(dir, "new.csv"), "a\n2\n")
        report = DashiBoard.init_workspace(dir; io = devnull)
        @test isfile(joinpath(dir, "tables", "old.csv")) && isfile(joinpath(dir, "tables", "new.csv"))
        @test !ispath(joinpath(dir, "quarantine")) && !ispath(joinpath(dir, "data"))
        @test DashiBoard.read_workspace_file(dir)["directories"]["data"] == "tables"
        @test report.placed == [("new.csv", "tables")]
    end
    # A folder that is plainly something else — a code project, a home — is not sorted.
    mktempdir() do dir
        write(joinpath(dir, "Project.toml"), "name = \"X\"\n")
        mkpath(joinpath(dir, "src")); write(joinpath(dir, "t.csv"), "a\n1\n")
        @test_throws ArgumentError DashiBoard.init_workspace(dir; io = devnull)
        @test isdir(joinpath(dir, "src")) && isfile(joinpath(dir, "t.csv"))
    end
    # A home is refused by being the home, whatever it holds: a throwaway folder stands in for it.
    mktempdir() do dir
        write(joinpath(dir, "t.csv"), "a\n1\n")
        withenv("HOME" => dir, "USERPROFILE" => dir) do
            @test_throws ArgumentError DashiBoard.init_workspace(dir; io = devnull)
        end
        @test readdir(dir) == ["t.csv"]
    end
end
