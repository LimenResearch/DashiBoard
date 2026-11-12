using HTTP: HTTP
using Sockets: Sockets

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
