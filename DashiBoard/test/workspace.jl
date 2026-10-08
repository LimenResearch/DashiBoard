using DashiBoard, Test, HTTP
using Sockets: Sockets
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
        write(joinpath(ws, "dashiboard.toml"), "[server]\nport = 9000\n[extensions]\nX = { path = \"/opt/X\" }\n")
        file = DashiBoard.read_workspace_file(ws)
        @test DashiBoard.server_defaults(file) == (host = nothing, port = 9000)
        @test DashiBoard.extension_sources(file, Dict()) == Dict("X" => Dict{String, Any}("path" => "/opt/X"))
        # The addresses a git remote goes by, with or without a revision; an `@` that is part of
        # the address is not one.
        parsed = DashiBoard.extension_sources(Dict(), Dict("extensions" => "A=ssh://git@github.com/Org/A.jl@v2,B=git@github.com:Org/B.jl,C=https://h/C.jl"))
        @test parsed["A"] == Dict{String, Any}("url" => "ssh://git@github.com/Org/A.jl", "rev" => "v2")
        @test parsed["B"] == Dict{String, Any}("url" => "git@github.com:Org/B.jl")
        @test parsed["C"] == Dict{String, Any}("url" => "https://h/C.jl")
        @test_throws ArgumentError DashiBoard.extension_sources(Dict(), Dict("extensions" => "JustAName"))

        # A workspace file that says something the launcher cannot read is refused by name,
        # rather than half-used: a misspelt table, a value of the wrong kind.
        bad(text) = (write(joinpath(ws, "dashiboard.toml"), text); DashiBoard.read_workspace_file(ws))
        @test_throws ArgumentError bad("[extentions]\nX = { path = \"/x\" }\n")
        @test_throws ArgumentError bad("[server]\nport = \"8080\"\n")
        @test_throws ArgumentError bad("[extensions]\nX = \"/opt/X\"\n")
        @test_throws ArgumentError bad("[extensions]\nX = { branch = \"main\" }\n")
        @test_throws ArgumentError bad("[directories]\ndata = 3\n")
        rm(joinpath(ws, "dashiboard.toml"))
        # A path is kept as written, and made absolute for whoever has to find it from elsewhere
        # — a downloaded pipeline names its extensions for another folder.
        relative = Dict("X" => Dict{String, Any}("path" => "../X"), "U" => Dict{String, Any}("url" => "https://h/U.jl", "rev" => "main"))
        located = DashiBoard.locate_sources(ws, relative)
        @test located["X"]["path"] == normpath(joinpath(ws, "..", "X")) && isabspath(located["X"]["path"])
        @test located["U"] == relative["U"]
        @test relative["X"]["path"] == "../X"
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
        @test occursin("odd.toml → quarantine/", text)
        again = DashiBoard.init_workspace(dir; io = devnull)
        @test isempty(again.placed) && isempty(again.quarantined)
        # A clash inside quarantine keeps both.
        write(joinpath(dir, "odd.toml"), "again = 2\n")
        DashiBoard.init_workspace(dir; io = devnull)
        @test isfile(at("quarantine", "odd-2.toml"))
    end
end

const TEST_EXTENSION = normpath(joinpath(@__DIR__, "static", "extension", "TestExtension"))
const LAUNCHER = normpath(joinpath(@__DIR__, "..", "..", "bin", "launch.jl"))
const PROJECT = normpath(joinpath(@__DIR__, ".."))

@testset "an environment from the extensions table" begin
    mktempdir() do ws
        # Named relative to the workspace, as a folder in `[directories]` is.
        sources = Dict("TestExtension" => Dict{String, Any}("path" => relpath(TEST_EXTENSION, ws)))
        env = DashiBoard.extension_environment(ws, sources; io = devnull)
        @test env == joinpath(ws, ".dashiboard", "env")
        project = TOML.parsefile(joinpath(env, "Project.toml"))
        @test haskey(project["deps"], "TestExtension") && haskey(project["deps"], "DashiBoard")
        # The server's own packages are the launcher's, whatever version an extension names.
        manifest = TOML.parsefile(joinpath(env, "Manifest.toml"))
        core = only(manifest["deps"]["StreamlinerCore"])
        @test haskey(core, "path") && !haskey(core, "repo-url")
        stamp = mtime(joinpath(env, "Manifest.toml"))
        # The same sources again: nothing to redo.
        sleep(1.1)
        DashiBoard.extension_environment(ws, sources; io = devnull)
        @test mtime(joinpath(env, "Manifest.toml")) == stamp

        # Different sources are a different environment, built afresh: what the table no longer
        # names is not carried along.
        DashiBoard.extension_environment(ws, Dict{String, Dict{String, Any}}(); io = devnull)
        @test !haskey(TOML.parsefile(joinpath(env, "Project.toml"))["deps"], "TestExtension")
        DashiBoard.extension_environment(ws, sources; io = devnull)
        # Loaded from the environment that holds them, and the one that was active put back.
        previous = Base.active_project()
        modules = try
            DashiBoard.Pkg.activate(env; io = devnull)
            DashiBoard.load_extensions(sources)
        finally
            DashiBoard.Pkg.activate(previous; io = devnull)
        end
        @test Base.active_project() == previous
        @test length(modules) == 1 && nameof(only(modules)) == :TestExtension
        @test DashiBoard.provenance(modules) == Dict("transform:double" => "TestExtension", "funnel:test" => "TestExtension")
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
    @test_throws ArgumentError DashiBoard.init_workspace(homedir(); io = devnull)
end

# The launcher, as a user runs it: from the workspace file alone, and from the command line.
# Each launch gets its own DuckDB cache: a second process on this suite's would wait on its
# lock. No startup file: the server must not depend on what a user's `startup.jl` loads.
launcher(args...) = addenv(
    `$(Base.julia_cmd()) --startup-file=no --project=$(PROJECT) $(LAUNCHER) $(collect(String, args))`,
    "DASHIBOARD_CACHE" => mktempdir(),
)

@testset "launching from a workspace" begin
    first_free(range) = for p in range
        s = try Sockets.listen(Sockets.localhost, p) catch; continue end
        close(s); return p
    end
    mktempdir() do ws
        mkpath(joinpath(ws, "model")); cp(joinpath(PROJECT, "..", "static", "model", "dense.toml"), joinpath(ws, "model", "dense.toml"))
        mkpath(joinpath(ws, "training")); cp(joinpath(PROJECT, "..", "static", "training", "batched.toml"), joinpath(ws, "training", "batched.toml"))
        port = first_free(8581:8680)
        write(joinpath(ws, "dashiboard.toml"), """
        [server]
        port = $(port)
        [extensions]
        TestExtension = { path = "$(TEST_EXTENSION)" }
        """)
        log = joinpath(ws, "launch.log")
        proc = run(pipeline(launcher(ws); stdout = log, stderr = log); wait = false)
        try
            answered = false
            for _ in 1:600
                process_exited(proc) && break
                try
                    r = HTTP.post("http://127.0.0.1:$(port)/get-card-ir", body = JSON.json((; cols = ["a"], nodes = String[], groups = String[], include = ["cards"])))
                    ir = JSON.parse(r.body)
                    funnel = only(p for p in ir["cards"]["streamliner"]["properties"] if p["key"] == "funnel")
                    transforms = only(p for p in funnel["value"]["objects"][""]["properties"] if p["key"] == "input_transforms")
                    @test "double" in transforms["value"]["values"]["enum"]
                    # A method the extension defined is seen by the running server.
                    @test [p["key"] for p in funnel["value"]["objects"]["test"]["properties"]] == ["marker"]
                    answered = true
                    break
                catch
                    sleep(1)
                end
            end
            @test answered
            # The server runs in the environment its extensions were resolved in, so what is
            # loaded is what was resolved.
            text = read(log, String)
            @test occursin(joinpath(".dashiboard", "env"), text)
            @test occursin("DashiBoard is listening", text)
            @test occursin("no directory for some kinds", text) && occursin(":pipeline", text)   # the warning names what fell back
        finally
            kill(proc); wait(proc)
        end
        # Stopping the launcher stops the server it started.
        gone = false
        for _ in 1:40
            gone = try
                HTTP.post("http://127.0.0.1:$(port)/list-files", body = "{}"; connect_timeout = 1, readtimeout = 1, retry = false); false
            catch
                true
            end
            gone && break
            sleep(0.5)
        end
        @test gone
    end
    # An extension that cannot be found stops the launch before it listens, naming it.
    mktempdir() do ws
        log = joinpath(ws, "launch.log")
        proc = run(pipeline(launcher(ws, "--extensions", "Nope=/nowhere/Nope"); stdout = log, stderr = log); wait = false)
        wait(proc)
        @test proc.exitcode != 0
        @test occursin("Nope", read(log, String))
    end
    # A directory named on the command line and not there stops the launch, by name.
    mktempdir() do ws
        log = joinpath(ws, "launch.log")
        proc = run(pipeline(launcher(ws, "--model_dir", joinpath(ws, "no-models")); stdout = log, stderr = log); wait = false)
        wait(proc)
        @test proc.exitcode != 0
        @test occursin("no-models", read(log, String)) && occursin("model", read(log, String))
    end
    # A workspace that is not there is a mistake in the command, not a folder to serve.
    mktempdir() do ws
        log = joinpath(ws, "launch.log")
        proc = run(pipeline(launcher(joinpath(ws, "nowhere")); stdout = log, stderr = log); wait = false)
        wait(proc)
        @test proc.exitcode != 0
        @test occursin("does not exist", read(log, String))
    end
    # `--init` sorts and leaves.
    mktempdir() do ws
        write(joinpath(ws, "t.csv"), "a\n1\n")
        run(launcher(ws, "--init"))
        @test isfile(joinpath(ws, "data", "t.csv")) && isfile(joinpath(ws, "dashiboard.toml"))
    end
end
