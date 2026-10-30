using DashiBoard, Test
using TOML: TOML
using JSON: JSON

# The starter is a script copied alone to a client's machine; included here, it only defines its module.
module StarterUnderTest
include(normpath(joinpath(@__DIR__, "..", "..", "bin", "install.jl")))
end
const Install = StarterUnderTest.Install

@testset "the starter" begin
    # This checkout stands in for the clone: the Project points every package into it.
    repo = normpath(joinpath(@__DIR__, "..", ".."))
    p = Install.starter_project(repo)
    own = TOML.parsefile(joinpath(repo, "DashiBoard", "Project.toml"))
    @test Set(keys(p["deps"])) == Set(["DashiBoard"; collect(keys(own["sources"]))])
    @test p["deps"]["DashiBoard"] == own["uuid"]
    @test p["sources"]["Pipelines"]["path"] == joinpath(repo, "Pipelines")
    mktempdir() do dir
        head = readchomp(`git -C $repo rev-parse HEAD`)
        @test Install.clone_at("file://" * repo, head, joinpath(dir, "c")) == head
        @test isfile(joinpath(dir, "c", "dashiboard-ui", "package.json"))   # the whole repo, UI included
        # A rev that is not there stops, naming it; what was downloaded stays, and the next run
        # moves it rather than downloading again.
        e = @test_throws ErrorException Install.clone_at("file://" * repo, "no-such-rev", joinpath(dir, "d"))
        @test occursin("no-such-rev", e.value.msg) && occursin("file://" * repo, e.value.msg)
        @test Install.prepare_clone(joinpath(dir, "d"), "file://" * repo, head) == head
        # A source git would read as an option is refused before git sees it.
        @test_throws ErrorException Install.prepare_clone(joinpath(dir, "e"), "--upload-pack=touch", head)
        @test_throws ErrorException Install.prepare_clone(joinpath(dir, "e"), "file://" * repo, "--orphan")
        mkpath(joinpath(dir, "x", ".dashiboard")); touch(joinpath(dir, "x", ".dashiboard", "record.toml"))
        e = @test_throws ErrorException Install.check_not_installed(joinpath(dir, "x"))
        @test occursin("--update", e.value.msg)
        # An update needs an install to update.
        write(joinpath(dir, "dashiboard.toml"), "[dashiboard]\nurl = \"file://$(repo)\"\nrev = \"$(head)\"\n")
        e = @test_throws ErrorException Install.main([dir, "--update", "all"])
        @test occursin("not installed", e.value.msg)
    end
end

@testset "the deployment files" begin
    file = Dict(
        "dashiboard" => Dict("url" => "https://x/D", "rev" => "v2"),
        "extensions" => Dict("TestExtension" => Dict("url" => "https://x/T", "rev" => "v1")),
    )
    rec = DashiBoard.deployment_record(file, "abc")
    @test rec["dashiboard"] == Dict("url" => "https://x/D", "rev" => "v2", "commit" => "abc")
    @test rec["julia"] == string(VERSION)
    @test isempty(DashiBoard.record_mismatches(rec, file, "abc"))
    # What install resolved is what a launch may serve: a clone moved, Julia changed or the
    # extensions edited since are refused, each with the update to run.
    moved = DashiBoard.record_mismatches(rec, file, "def")
    @test length(moved) == 1 && occursin("abc", only(moved)) && occursin("def", only(moved)) && occursin("--update all", only(moved))
    julia = only(DashiBoard.record_mismatches(rec, file, "abc", "1.0.0"))
    @test occursin("1.0.0", julia) && occursin(string(VERSION), julia) && occursin("--update all", julia)
    added = merge(file, Dict("extensions" => Dict("Other" => Dict("url" => "https://x/O", "rev" => "v1"))))
    @test occursin("--update extensions", only(DashiBoard.record_mismatches(rec, added, "abc")))
    @test occursin("using TestExtension", DashiBoard.serve_script(["TestExtension"]))
    @test occursin("JULIA_DEPOT_PATH=\"\$here/depot\"", DashiBoard.launch_script())
end

@testset "an extension through the handlers" begin
    @eval using TestExtension
    mktempdir() do ws
        handlers, _, _ = DashiBoard.get_handlers(
            ws;
            parser = DashiBoard.Pipelines.default_parser(; plugins = [TestExtension.DEFAULT_PARSER]),
            extension_of = DashiBoard.provenance([TestExtension]),
        )
        params = Dict("cols" => ["a"], "nodes" => String[], "groups" => String[], "include" => ["cards"])
        req = DashiBoard.DashiBase.JSONRequest(; method = "get-card-ir", params, id = 1)
        ir = JSON.parse(JSON.json(DashiBoard.DashiBase.apply_handlers(handlers, req)))["result"]
        funnel = only(p for p in ir["cards"]["streamliner"]["properties"] if p["key"] == "funnel")
        transforms = only(p for p in funnel["value"]["objects"][""]["properties"] if p["key"] == "input_transforms")
        @test "double" in transforms["value"]["values"]["enum"]
        # A method the extension defined is what the form describes.
        @test [p["key"] for p in funnel["value"]["objects"]["test"]["properties"]] == ["marker"]
    end
end

using HTTP: HTTP
using Sockets: Sockets
using FileWatching: FileMonitor

# The one launch in the suite: a generated `serve.jl`, run in this test environment (which holds
# DashiBoard and TestExtension) instead of an installed one, so nothing is resolved or downloaded.
@testset "serving a deployment" begin
    mktempdir() do deploy
        port = let s = Sockets.listen(Sockets.localhost, 0)
            p = Int(Sockets.getsockname(s)[2]); close(s); p
        end
        file = Dict(
            "dashiboard" => Dict("url" => "https://x/DashiBoard", "rev" => "v2"),
            "server" => Dict("port" => port),
            "extensions" => Dict("TestExtension" => Dict("url" => "https://x/TestExtension", "rev" => "v1")),
        )
        open(io -> TOML.print(io, file), joinpath(deploy, "dashiboard.toml"), "w")
        own = mkpath(joinpath(deploy, ".dashiboard"))
        mkpath(joinpath(own, "DashiBoard", ".git"))
        write(joinpath(own, "DashiBoard", ".git", "HEAD"), "abc\n")
        open(io -> TOML.print(io, DashiBoard.deployment_record(file, "abc")), joinpath(own, "record.toml"), "w")
        write(joinpath(own, "serve.jl"), DashiBoard.serve_script(["TestExtension"]))

        # The server says it is listening once its port is bound, so its log saying so is the
        # wait. Each wait is for an event — the file changed, or the process exited — and the
        # monitor is open before the start, so no change between two reads is missed.
        log = joinpath(deploy, "serve.log")
        touch(log)
        monitor = FileMonitor(log)
        cmd = addenv(`$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) $(joinpath(own, "serve.jl"))`, "DASHIBOARD_CACHE" => mktempdir())
        proc = run(pipeline(cmd; stdout = log, stderr = log); wait = false)
        events = Channel{Symbol}(Inf)
        @async (wait(proc); put!(events, :exited))
        @async try
            while true
                wait(monitor); put!(events, :changed)
            end
        catch  # the monitor is closed
        end
        try
            listening(text) = occursin(r"DashiBoard is listening[^└]*└[^\n]*\n", text)
            text = read(log, String)
            while !listening(text) && !process_exited(proc)
                take!(events)
                text = read(log, String)
            end
            @test listening(text)
            params = (; cols = ["a"], nodes = String[], groups = String[], include = ["cards"])
            r = HTTP.post("http://127.0.0.1:$(port)/rpc"; body = JSON.json((; jsonrpc = "2.0", id = 1, method = "get-card-ir", params)))
            funnel = only(p for p in JSON.parse(r.body)["result"]["cards"]["streamliner"]["properties"] if p["key"] == "funnel")
            @test haskey(funnel["value"]["objects"], "test")   # the extension is loaded
        finally
            close(monitor)
            kill(proc); wait(proc)
        end
        refused = try
            close(Sockets.connect(Sockets.localhost, port)); false
        catch e
            e isa Base.IOError || rethrow()
            true
        end
        @test refused
    end
end

@testset "updates keep what they did not change" begin
    rec = DashiBoard.deployment_record(Dict("dashiboard" => Dict("url" => "https://x/D", "rev" => "v2")), "abc")
    # Moving only the extensions may not adopt a new DashiBoard or a new Julia: the record would
    # then name a release that was never installed.
    edited = Dict("dashiboard" => Dict("url" => "https://x/D", "rev" => "v3"))
    e = @test_throws ArgumentError DashiBoard.check_extensions_update(rec, edited, "abc")
    @test occursin("--update all", e.value.msg)
    @test_throws ArgumentError DashiBoard.check_extensions_update(rec, Dict("dashiboard" => Dict("url" => "https://x/D", "rev" => "v2")), "abc", "1.0.0")
    @test isnothing(DashiBoard.check_extensions_update(rec, merge(edited, Dict("dashiboard" => Dict("url" => "https://x/D", "rev" => "v2"))), "abc"))

    repo = normpath(joinpath(@__DIR__, "..", ".."))
    mktempdir() do dir
        head = readchomp(`git -C $repo rev-parse HEAD`)
        # A full update follows the toml's url, not the one the clone was made from.
        fork = joinpath(dir, "fork")
        run(`git clone --quiet file://$repo $fork`)
        run(`git -C $fork -c user.name=t -c user.email=t@t commit --quiet --allow-empty -m fork`)
        ahead = readchomp(`git -C $fork rev-parse HEAD`)
        clone = joinpath(dir, "clone")
        Install.clone_at("file://" * repo, head, clone)
        @test Install.checkout_update(clone, "file://" * fork, ahead) == ahead
        @test readchomp(`git -C $clone remote get-url origin`) == "file://" * fork

        # An update that fails leaves the deployment it found.
        deploy = joinpath(dir, "deploy")
        own = mkpath(joinpath(deploy, ".dashiboard"))
        mv(clone, joinpath(own, "DashiBoard"))
        for name in ("Project.toml", "Manifest.toml", "record.toml")
            write(joinpath(own, name), name)
        end
        @test_throws ErrorException Install.with_rollback(deploy) do
            write(joinpath(own, "Project.toml"), "rewritten")
            rm(joinpath(own, "Manifest.toml"))
            run(`git -C $(joinpath(own, "DashiBoard")) checkout --quiet --detach $head`)
            error("the resolve failed")
        end
        @test read(joinpath(own, "Project.toml"), String) == "Project.toml"
        @test read(joinpath(own, "Manifest.toml"), String) == "Manifest.toml"
        @test readchomp(`git -C $(joinpath(own, "DashiBoard")) rev-parse HEAD`) == ahead
    end
end

@testset "a launch whose Julia is gone" begin
    mktempdir() do dir
        script = joinpath(dir, "launch.sh")
        # Taken as written: nothing in the path is read by the shell.
        gone = joinpath(dir, "it's \$HOME `x`", "julia")
        write(script, DashiBoard.launch_script(gone))
        err = IOBuffer()
        ok = success(pipeline(`sh $script`; stdout = devnull, stderr = err))
        said = String(take!(err))
        @test !ok && occursin("--update all", said) && occursin(gone, said)
    end
end

@testset "the starter's refusals are sentences" begin
    mktempdir() do dir
        err = IOBuffer()
        ok = success(pipeline(`$(Base.julia_cmd()) --startup-file=no $(normpath(joinpath(@__DIR__, "..", "..", "bin", "install.jl"))) $dir`; stdout = devnull, stderr = err))
        said = String(take!(err))
        @test !ok && startswith(said, "ERROR: ") && !occursin("Stacktrace", said)
    end
end
