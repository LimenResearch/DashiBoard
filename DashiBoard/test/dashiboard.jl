using HTTP, DataIngestion, Pipelines, JSON, DBInterface, DataFrames
using Sockets: Sockets
using DashiBoard
using Test
using Downloads
using Logging: Logging, with_logger, Debug

# Add trivial card
Pipelines._train(wc::WildCard{:trivial}, t, id_var) = nothing
function (wc::WildCard{:trivial})(model, t, id_var)
    id = t[id_var]
    nrows = length(id)
    return Dict(id_var => id, (k => zeros(nrows) for k in wc.outputs)...)
end
settings = Pipelines.WildCardSettings(
    needs_order = false,
    needs_targets = false,
    allows_partition = false,
    allows_weights = false
)
Pipelines.register_wild_card(:trivial, "Trivial"; settings)

@testset "LoggingMiddleware" begin
    # DashiBoard logged nothing on a successful request — not the route, not the status, not how
    # long it took — so "what is the server doing" could only be inferred from CPU time and the
    # DuckDB write-ahead log. This is the access log that was missing.

    # A stand-in for the server stream. The real one is a thirty-field mutable struct that cannot
    # be constructed outside a live connection, and the middleware reads exactly two things from
    # it, so this is the whole contract.
    mutable struct FakeStream
        message::HTTP.Request
        response::Union{Nothing, HTTP.Response}
    end

    function serve(method, target; status = 200, handler = _ -> nothing)
        stream = FakeStream(HTTP.Request(method, target), HTTP.Response(status))
        logs = Test.TestLogger(min_level = Debug)
        with_logger(logs) do
            DashiBoard.LoggingMiddleware(handler)(stream)
        end
        return logs.logs
    end

    record = only(serve("POST", "/probe-pipeline"))
    @test record.level == Debug
    @test record.message == "POST /probe-pipeline"
    kv = Dict(record.kwargs)
    @test kv[:status] == 200
    @test kv[:seconds] isa Real && kv[:seconds] >= 0

    # A route that was never registered is still a request, and is the one you most want to see
    # when a client is pointed at the wrong place. It never reaches a handler, so only a middleware
    # outside the router can report it.
    @test Dict(only(serve("POST", "/nosuchroute"; status = 404)).kwargs)[:status] == 404

    # A handler that throws is still reported, and the exception still propagates. The status is
    # whatever was set before the throw — HTTP.jl substitutes its own 500 further out, after this
    # has unwound — so what is pinned here is that the line exists, not what it claims.
    logs = Test.TestLogger(min_level = Debug)
    stream = FakeStream(HTTP.Request("POST", "/evaluate-pipeline"), HTTP.Response(200))
    @test_throws ErrorException with_logger(logs) do
        DashiBoard.LoggingMiddleware(_ -> error("boom"))(stream)
    end
    @test only(logs.logs).message == "POST /evaluate-pipeline"

    # Silent unless asked for: `@debug` is filtered by level, so with an ordinary logger nothing is
    # emitted and nothing is even formatted.
    logs = Test.TestLogger(min_level = Logging.Info)
    with_logger(logs) do
        DashiBoard.LoggingMiddleware(_ -> nothing)(
            FakeStream(HTTP.Request("POST", "/probe-pipeline"), HTTP.Response(200))
        )
    end
    @test isempty(logs.logs)
end

@testset "root_causes" begin
    # Pipelines evaluates nodes as tasks, so every runtime failure reaches the handler wrapped in
    # `TaskFailedException` — twice over, in practice. `showerror` on the wrapper prints the
    # scheduler's stacktrace and not one word about what actually went wrong, which is what a user
    # was being shown.
    wrapped = try
        t = Threads.@spawn error("the real problem")
        wait(t)
    catch exception
        exception
    end
    @test wrapped isa TaskFailedException
    @test occursin("TaskFailedException", sprint(showerror, wrapped))
    @test occursin("the real problem", sprint(showerror, only(DashiBoard.root_causes(wrapped))))

    # Nested, which is the shape the pipeline actually produces.
    twice = try
        outer = Threads.@spawn begin
            inner = Threads.@spawn error("buried")
            wait(inner)
        end
        wait(outer)
    catch exception
        exception
    end
    @test occursin("buried", sprint(showerror, only(DashiBoard.root_causes(twice))))

    # Several tasks failing at once are several messages, not one chosen arbitrarily.
    many = CompositeException([ErrorException("first"), ErrorException("second")])
    @test [sprint(showerror, e) for e in DashiBoard.root_causes(many)] ==
        ["first", "second"]

    # Anything else is its own root cause.
    plain = ArgumentError("as is")
    @test only(DashiBoard.root_causes(plain)) === plain
end

mktempdir() do data_dir
    Downloads.download(
        "https://raw.githubusercontent.com/jbrownlee/Datasets/master/pollution.csv",
        joinpath(data_dir, "pollution.csv")
    )

    load_config = JSON.parsefile(joinpath(@__DIR__, "static", "load.json"))
    pipeline_config = JSON.parsefile(joinpath(@__DIR__, "static", "pipeline.json"))

    repo = DashiBoard.REPOSITORY[]
    DataIngestion.load_files(repo, data_dir, load_config)

    filters = DataIngestion.Filter.(pipeline_config["filters"])
    DataIngestion.select(repo, filters)

    cards = Pipelines.Card.(pipeline_config["cards"])
    Pipelines.train_evaljoin!(repo, Pipelines.Node.(cards), "selection", "No")

    res = DBInterface.execute(DataFrame, repo, "FROM selection")

    @testset "cards" begin
        @test "_tiled_partition" in names(res)
        @test "_percentile_partition" in names(res)
    end

    static_directory = joinpath(@__DIR__, "..", "..", "static")
    model_directory = joinpath(static_directory, "model")
    training_directory = joinpath(static_directory, "training")

    # Take the first free port rather than hardcoding one. 8080 is the default of both Julia
    # servers *and* what nexus-weaver-pro's Vite dev server occupies, while the agentgraph stack
    # runs ExperimentTracking on 8081 — so a hardcoded 8080 made this suite unrunnable whenever
    # the dev stack was up.
    function first_free_port(range)
        for p in range
            socket = try
                Sockets.listen(Sockets.localhost, p)
            catch
                continue # in use
            end
            # Small window between closing the probe and `launch` binding; fine for a test.
            close(socket)
            return p
        end
        error("no free port in $(range)")
    end

    port = first_free_port(8080:8280)
    server = DashiBoard.launch(
        data_dir;
        port = port,
        async = true,
        model_directory,
        training_directory
    )

    @testset "request" begin
        url = "http://127.0.0.1:$(port)/"

        body = read(joinpath(@__DIR__, "static", "card-ir.json"), String)
        resp = HTTP.post(url * "get-card-ir", body = body)
        payload = JSON.parse(resp.body)
        @test sort(collect(keys(payload))) == ["cards", "defs"]
        @test length(payload["cards"]) == length(Pipelines.CARD_SPECS)
        # The group dialect: six definitions, hoisted once into the envelope rather than repeated
        # per card. This route serves the same dialect evaluate-pipeline now runs.
        @test sort(collect(keys(payload["defs"]))) ==
            ["col", "group", "node", "nonempty_variables", "variable", "variables"]
        @test payload["defs"]["col"]["enum"] == ["No", "TEMP"]
        @test payload["defs"]["node"]["enum"] == ["percentile", "tiled"]
        @test payload["defs"]["group"]["enum"] == ["wind"]
        # `variable` is a selector object here, where the flat dialect had a string enum
        @test payload["defs"]["variable"]["type"] == "object"
        # and its one-or-many fields identify themselves, so a renderer can dispatch on them
        nodes_entry = only(
            p for p in payload["defs"]["variable"]["properties"] if p["key"] == "nodes"
        )
        @test nodes_entry["value"]["type"] == "one_or_many"
        # field entries are an ordered array, and the card label travels in the IR
        @test payload["cards"]["split"]["properties"] isa AbstractVector
        @test payload["cards"]["split"]["title"] isa AbstractString
        # The only place the response headers and the OPTIONS preflight are asserted, so this
        # covers CORS for every route rather than for this one.
        #
        # Before the `String(resp.body)` below, not after: `String(::Vector{UInt8})` takes
        # ownership of the buffer and leaves it empty, so a `length(resp.body)` that follows it
        # reads 0 and the Content-Length assertion fails against its own response.
        @test resp.headers == [
            DashiBoard.CORS_RES_HEADERS...,
            "Content-Type" => "application/json",
            "Content-Length" => string(length(resp.body)),
        ]
        # nulls are omitted rather than shipped
        @test !occursin(":null", String(resp.body))
        # `cards` is 96% of the payload and cannot change within a session — `card_ir` takes no
        # vocabulary. A client that has it once asks for `defs` alone afterwards.
        body = JSON.json((; cols = ["No", "TEMP"], nodes = String[], groups = String[], include = ["defs"]))
        resp = HTTP.post(url * "get-card-ir", body = body)
        only_defs = JSON.parse(resp.body)
        @test collect(keys(only_defs)) == ["defs"]
        @test only_defs["defs"]["col"]["enum"] == ["No", "TEMP"]
        @test length(resp.body) < 4000                     # against ~19 KB for the full payload
        body = JSON.json((; include = ["cards"]))
        resp = HTTP.post(url * "get-card-ir", body = body)
        @test collect(keys(JSON.parse(resp.body))) == ["cards"]
        resp = HTTP.options(url * "get-card-ir")
        @test resp.headers == [
            DashiBoard.CORS_OPTIONS_HEADERS...,
            "Content-Length" => "0",
        ]

        body = read(joinpath(@__DIR__, "static", "load.json"), String)
        resp = HTTP.post(url * "load-files", body = body)
        summaries = JSON.parse(resp.body)
        @test summaries[end]["name"] == "Ir"
        @test resp.headers == [
            DashiBoard.CORS_RES_HEADERS...,
            "Content-Type" => "application/json",
            "Content-Length" => string(length(resp.body)),
        ]

        # The group dialect: {filters, nodes, groups} with selector-form variable fields, which
        # is what the new UI authors. The flat {filters, cards} shape is gone from this route.
        body = read(joinpath(@__DIR__, "static", "pipeline-groups.json"), String)
        resp = HTTP.post(url * "evaluate-pipeline", body = body)
        parsed = JSON.parse(resp.body)
        summaries = parsed["summaries"]
        @test summaries[end]["name"] == "_tiled_partition"
        # A4: the graph renders, and names the group rather than its resolved columns
        @test startswith(parsed["graph"], "digraph G{")
        @test occursin("\"wind\"", parsed["graph"])

        # A card checked on its own, which is what a form editing one card actually needs. No
        # document, no graph walk — and `related` gives a pointer per absent name, so the answer
        # lands on the control rather than on the card.
        body = JSON.json((;
            card = Dict("type" => "cluster"),
            cols = ["No", "TEMP"], nodes = String[], groups = String[],
            base = "/nodes/0/card",
        ))
        resp = HTTP.post(url * "validate-card", body = body)
        @test resp.status == 200
        parsed = JSON.parse(resp.body)
        issue = only(parsed["issues"])
        @test issue["reason"] == "required"
        @test issue["missing"] == ["method", "inputs"]
        @test issue["related"] == ["/nodes/0/card/method", "/nodes/0/card/inputs"]

        # A card with nothing wrong says nothing, rather than saying it is valid in some other way.
        body = JSON.json((;
            card = Dict(
                "type" => "rescale", "method" => Dict("type" => "zscore"),
                "inputs" => [Dict("cols" => "TEMP")],
            ),
            cols = ["No", "TEMP"], nodes = String[], groups = String[],
        ))
        resp = HTTP.post(url * "validate-card", body = body)
        @test isempty(JSON.parse(resp.body)["issues"])

        # An unknown card type has no schema to check against, so it answers as a failure rather
        # than throwing out of the handler.
        body = JSON.json((; card = Dict("type" => "nosuchcard"), cols = ["TEMP"]))
        resp = HTTP.post(url * "validate-card", body = body, status_exception = false)
        @test resp.status == 200
        parsed = JSON.parse(resp.body)
        @test parsed["valid"] == false
        @test parsed["kind"] == "pipeline"

        # A10: probing constructs without executing, and reports references nothing produces.
        # `through = ["r","r"]` names TEMP_a_a, which no node emits — schema validation accepts it.
        body = read(joinpath(@__DIR__, "static", "probe-bad.json"), String)
        resp = HTTP.post(url * "probe-pipeline", body = body)
        probe = JSON.parse(resp.body)
        @test probe["valid"] == false
        @test probe["kind"] == "pipeline"   # an unproduced reference is a document fault too
        offender = only(filter(n -> !isempty(n["unproduced"]), probe["nodes"]))
        @test offender["id"] == "bad"
        @test offender["unproduced"] == ["TEMP_a_a"]
        # and it still reports what it resolved, rather than only failing
        @test "TEMP_a" in probe["nodes"][1]["outputs"]
        # A7: the same failure also arrives in the uniform `issues` shape, addressed by pointer.
        # Node granularity, not item: resolution keeps no provenance back to the selector item.
        unproduced = only(filter(i -> i["reason"] == "unproduced", probe["issues"]))
        @test unproduced["pointer"] == "/nodes/1/card"
        @test unproduced["missing"] == ["TEMP_a_a"]

        # A probe reports rather than throws — for *every* way a document can be malformed,
        # not only schema failures. Two nodes with no `id` both resolve to "", which the
        # dependency graph rejects as a duplicate; that used to escape as a 500, leaving the
        # form with nothing to render and no reason.
        body = read(joinpath(@__DIR__, "static", "probe-noid.json"), String)
        resp = HTTP.post(url * "probe-pipeline", body = body, status_exception = false)
        @test resp.status == 200
        probe = JSON.parse(resp.body)
        @test probe["valid"] == false
        # The probe never runs anything, so every fault it can see is a `pipeline` one — said
        # explicitly rather than left to be inferred from which route answered.
        @test probe["kind"] == "pipeline"
        @test occursin("id", only(probe["errors"]))

        # A7: a schema failure comes back as data, addressed by JSON Pointer into the document,
        # carrying what would have been accepted — so a form can point at the control and offer a
        # correction rather than print a sentence. The second input is the bad one, which is also
        # what pins the index conversion: JSONSchema.jl counts from one, JSON Pointer from zero.
        body = read(joinpath(@__DIR__, "static", "probe-badvalue.json"), String)
        resp = HTTP.post(url * "probe-pipeline", body = body, status_exception = false)
        @test resp.status == 200
        probe = JSON.parse(resp.body)
        @test probe["valid"] == false
        issue = only(probe["issues"])
        @test issue["pointer"] == "/nodes/0/card/inputs/1/cols"
        @test issue["reason"] == "enum"
        @test issue["found"] == "NOSUCHCOLUMN"
        @test "TEMP" in issue["allowed"]

        # A well-formed document probes clean.
        body = read(joinpath(@__DIR__, "static", "pipeline-groups.json"), String)
        resp = HTTP.post(url * "probe-pipeline", body = body)
        probe = JSON.parse(resp.body)
        @test probe["valid"] == true
        @test all(n -> isempty(n["unproduced"]), probe["nodes"])
        @test resp.headers == [
            DashiBoard.CORS_RES_HEADERS...,
            "Content-Type" => "application/json",
            "Content-Length" => string(length(resp.body)),
        ]

        body = read(joinpath(@__DIR__, "static", "fetch.json"), String)
        resp = HTTP.post(url * "fetch-data", body = body)
        tbl = JSON.parse(resp.body)
        df = DBInterface.execute(DataFrame, DashiBoard.REPOSITORY[], "FROM selection")
        @test tbl["length"] == nrow(df)
        @test [row["No"] for row in tbl["values"]] == df.No[11:60]
        @test resp.headers == [
            DashiBoard.CORS_RES_HEADERS...,
            "Content-Type" => "application/json",
            "Content-Length" => string(length(resp.body)),
        ]

        HTTP.open("GET", url * "get-processed-data") do stream
            r = startread(stream)
            @test r.headers == [
                DashiBoard.CORS_RES_HEADERS...,
                "Content-Type" => "text/csv",
                "Content-Length" => "336104",
            ]

            s = read(stream, String)
            @test ncodeunits(s) == 336104
            l1, l2 = Iterators.take(eachsplit(s, '\n'), 2)
            @test l1 == "No,year,month,day,hour,pm2.5,DEWP,TEMP,PRES,cbwd,Iws,Is,Ir,_id,_percentile_partition,_tiled_partition"
            @test l2 == "8761,2011,1,1,0,NA,-21,-9,1033.0,NW,570.41,0,0,8761,1,1"
        end
        resp = HTTP.options(url * "get-processed-data")
        @test resp.headers == [
            DashiBoard.CORS_OPTIONS_HEADERS...,
            "Content-Length" => "0",
        ]


        # ---- keep last: this one runs a pipeline that fails ----
        #
        # A failed run still rebuilds `selection` from `source` before it dies, so it
        # drops every column the successful pipeline added. Anything asserting on that
        # table — the CSV export above, for instance — has to have run already.
        # A run that the schema accepts and the data defeats: PCA cannot take three components
        # from one column. Nothing static can catch it — the probe says `valid: true` — so the
        # only place it can be reported is the response to the run itself. Before this, the
        # exception escaped the handler and HTTP.jl answered with a bare 500 carrying zero bytes
        # and no CORS header, so the client had nothing to show and no way to tell a failed run
        # from one that had never happened.
        body = read(joinpath(@__DIR__, "static", "evaluate-bad.json"), String)
        resp = HTTP.post(url * "probe-pipeline", body = body)
        @test JSON.parse(resp.body)["valid"] == true   # static checks pass; this is a runtime fault
        resp = HTTP.post(url * "evaluate-pipeline", body = body)
        @test resp.status == 200
        failed = JSON.parse(resp.body)
        @test failed["valid"] == false
        # `execution`, not `pipeline`: the document built fine and the *run* is what died. The
        # split is on which call threw, which is observable, rather than on whose fault it is,
        # which is not.
        @test failed["kind"] == "execution"
        @test !isempty(failed["errors"])
        # The message is the cause, not the wrapper. Before unwrapping, this said
        # "TaskFailedException" followed by forty lines of scheduler stacktrace, and the sentence
        # naming the actual fault was buried two levels inside it.
        @test !occursin("TaskFailedException", failed["errors"][1])
        @test occursin("Binder Error", failed["errors"][1])
        # and the response is still a normal one, so a browser can read it
        @test ("Access-Control-Allow-Origin" => "*") in resp.headers

        # The other kind on the same route. A client that probes first would never send this, but
        # the route is public and cannot assume it was asked politely: two unnamed nodes both
        # resolve to "" and the dependency graph rejects the pair, before anything runs.
        body = read(joinpath(@__DIR__, "static", "probe-noid.json"), String)
        resp = HTTP.post(url * "evaluate-pipeline", body = body, status_exception = false)
        @test resp.status == 200
        failed = JSON.parse(resp.body)
        @test failed["valid"] == false
        @test failed["kind"] == "pipeline"
        @test occursin("id", only(failed["errors"]))
    end

    close(server)
end
