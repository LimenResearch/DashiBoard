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

    before = DashiBoard.REQUEST_COUNT[]
    record = only(serve("POST", "/probe-pipeline"))
    @test record.level == Debug
    # One line, fields in a fixed order: when, which request, what was asked, what came back, how
    # long. The timestamp is the field the first version shipped without, and its absence made the
    # log unable to answer the question it was built for — which requests belong to which page
    # load.
    @test occursin(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} ", record.message)
    @test occursin("POST /probe-pipeline 200 ", record.message)
    @test occursin(r"\d+\.\d+s$", record.message)
    # Numbered, so a gap in the log reads as a gap rather than as quiet.
    @test occursin("#$(before + 1) ", record.message)
    @test DashiBoard.REQUEST_COUNT[] == before + 1

    # Numbers and clock agree, because both are taken on arrival. Requests overlap, so a slow one
    # that arrived first can finish last — stamping at completion put `#2` above `#1` in a real
    # log. Checked by holding the first request open while a second arrives and finishes.
    stamp(rec) = match(r"^(\S+ \S+) #(\d+)", rec.message)
    slow, fast = Test.TestLogger(min_level = Debug), Test.TestLogger(min_level = Debug)
    gate = Threads.Event()
    first_done = Threads.@spawn with_logger(slow) do
        DashiBoard.LoggingMiddleware(_ -> wait(gate))(
            FakeStream(HTTP.Request("POST", "/slow"), HTTP.Response(200))
        )
    end
    sleep(0.05)
    with_logger(fast) do
        DashiBoard.LoggingMiddleware(_ -> nothing)(
            FakeStream(HTTP.Request("POST", "/fast"), HTTP.Response(200))
        )
    end
    notify(gate)
    wait(first_done)
    slow_at, slow_n = stamp(only(slow.logs)).captures
    fast_at, fast_n = stamp(only(fast.logs)).captures
    @test parse(Int, slow_n) < parse(Int, fast_n)   # the slow one arrived first
    @test slow_at <= fast_at                        # ...and its stamp says so, though it finished last

    # A route that was never registered is still a request, and is the one you most want to see
    # when a client is pointed at the wrong place. It never reaches a handler, so only a middleware
    # outside the router can report it.
    @test occursin("POST /nosuchroute 404 ", only(serve("POST", "/nosuchroute"; status = 404)).message)

    # A response that never got as far as being written says so, rather than claiming a status.
    stream = FakeStream(HTTP.Request("POST", "/probe-pipeline"), nothing)
    logs = Test.TestLogger(min_level = Debug)
    with_logger(logs) do
        DashiBoard.LoggingMiddleware(_ -> nothing)(stream)
    end
    @test occursin("POST /probe-pipeline - ", only(logs.logs).message)

    # A handler that throws is still reported, and the exception still propagates. The status is
    # whatever was set before the throw — HTTP.jl substitutes its own 500 further out, after this
    # has unwound — so what is pinned here is that the line exists, not what it claims.
    logs = Test.TestLogger(min_level = Debug)
    stream = FakeStream(HTTP.Request("POST", "/evaluate-pipeline"), HTTP.Response(200))
    @test_throws ErrorException with_logger(logs) do
        DashiBoard.LoggingMiddleware(_ -> error("boom"))(stream)
    end
    @test occursin("POST /evaluate-pipeline", only(logs.logs).message)

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

@testset "json_response and non-finite floats" begin
    # A12: `JSON.json` refuses NaN and Inf, so a run whose z-score of a constant column was NaN
    # on every row was reported as an execution failure (measured on `constant = 42`, 2026-09-13
    # and 2026-09-16). `null` is what every JSON client reads as "no value".
    resp = DashiBoard.json_response((; a = [1.0, NaN, Inf, -Inf], b = Dict("x" => NaN)))
    body = String(resp.body)
    @test !occursin("NaN", body) && !occursin("Infinity", body)
    @test JSON.parse(body)["a"] == [1.0, nothing, nothing, nothing]
    @test JSON.parse(body)["b"]["x"] === nothing
end

mktempdir() do data_dir
    Downloads.download(
        "https://raw.githubusercontent.com/jbrownlee/Datasets/master/pollution.csv",
        joinpath(data_dir, "pollution.csv")
    )

    # Fixtures for the file routes: one of each kind, a JSON that is a real table, a JSON that
    # does not parse, and hidden entries — all in the directory the server is launched on.
    cards_doc = Dict("nodes" => [Dict("id" => "r", "card" => Dict("type" => "rescale"))], "groups" => Dict{String, Any}())
    write(joinpath(data_dir, "cards.json"), JSON.json(cards_doc))
    write(joinpath(data_dir, "cards.toml"), "groups = {}\n[[nodes]]\nid = \"r\"\n[nodes.card]\ntype = \"rescale\"\n")
    write(joinpath(data_dir, "filters.json"), JSON.json(Dict("numerical" => Dict("TEMP" => Dict("min" => 0, "max" => 1)), "categorical" => Dict{String, Any}())))
    mkdir(joinpath(data_dir, "sub"))
    write(joinpath(data_dir, "sub", "table.json"), JSON.json([Dict("a" => 1), Dict("a" => 2)]))
    write(joinpath(data_dir, "broken.json"), "{ not json")
    write(joinpath(data_dir, ".hidden.json"), JSON.json(cards_doc))
    mkdir(joinpath(data_dir, ".cache"))
    write(joinpath(data_dir, ".cache", "cards.json"), JSON.json(cards_doc))
    write(joinpath(data_dir, "notes.md"), "not a table, not a document")

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

        @testset "files" begin
            post(route, body) = JSON.parse(HTTP.post(url * route, body = JSON.json(body), status_exception = false).body)

            # The listing names every file the UI may pick, with what it is. A JSON is told from
            # a table by content, so the kind survives a rename; what does not parse, what is
            # hidden and what is neither table nor document are not listed.
            listed = post("list-files", Dict())
            @test [(f["path"], f["kind"]) for f in listed] == [
                ("cards.json", "cards"),
                ("cards.toml", "cards"),
                ("filters.json", "filters"),
                ("pollution.csv", "table"),
                (joinpath("sub", "table.json"), "table"),
            ]

            # `load-files` joined `..` without looking; a path outside the data directory is now
            # a failure envelope, not a read.
            escaped = post("load-files", Dict("files" => ["../pollution.csv"]))
            @test escaped["valid"] == false
            @test occursin("outside the data directory", only(escaped["errors"]))

            # Reading: JSON and TOML spell the same document; the kind asked for must be the kind
            # found; nothing outside the directory, nothing that is not there.
            from_json = post("read-document", Dict("path" => "cards.json", "kind" => "cards"))
            from_toml = post("read-document", Dict("path" => "cards.toml", "kind" => "cards"))
            @test from_json["valid"] == true
            @test from_json["document"]["nodes"][1]["id"] == "r"
            @test from_toml["document"]["nodes"][1]["card"]["type"] == "rescale"
            @test isempty(from_toml["document"]["groups"])

            wrong_kind = post("read-document", Dict("path" => "filters.json", "kind" => "cards"))
            @test wrong_kind["valid"] == false
            @test wrong_kind["kind"] == "document"
            @test occursin("not a cards document", only(wrong_kind["errors"]))

            for path in ("../cards.json", joinpath(data_dir, "cards.json"))
                outside = post("read-document", Dict("path" => path, "kind" => "cards"))
                @test outside["valid"] == false
                @test occursin("outside the data directory", only(outside["errors"]))
            end
            missing_file = post("read-document", Dict("path" => "nope.json", "kind" => "cards"))
            @test occursin("does not exist", only(missing_file["errors"]))
            unparsable = post("read-document", Dict("path" => "broken.json", "kind" => "cards"))
            @test unparsable["valid"] == false

            # Writing: a document round-trips inside the directory; an existing file is kept
            # unless the author says replace; the shape must match the kind; JSON only.
            doc = from_json["document"]
            save(path, kind, overwrite) = post("write-document", Dict("path" => path, "kind" => kind, "document" => doc, "overwrite" => overwrite))
            saved = save("sub/mine.json", "cards", false)
            @test saved["valid"] == true
            @test saved["path"] == "sub/mine.json"
            @test ("sub/mine.json", "cards") in [(f["path"], f["kind"]) for f in post("list-files", Dict())]
            @test post("read-document", Dict("path" => "sub/mine.json", "kind" => "cards"))["document"] == doc

            @test occursin("already exists", only(save("sub/mine.json", "cards", false)["errors"]))
            @test save("sub/mine.json", "cards", true)["valid"] == true

            @test occursin("not a filters document", only(save("f.json", "filters", false)["errors"]))
            @test occursin("outside the data directory", only(save("../x.json", "cards", false)["errors"]))
            @test occursin(".json", only(save("x.toml", "cards", false)["errors"]))
            @test occursin("folder", only(save("nowhere/x.json", "cards", false)["errors"]))
            @test !isfile(joinpath(data_dir, "f.json"))
        end

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

        # A14: a document with no cards. Filter-only is a legitimate run (filter, run, look), and
        # the probe of an empty document is what the UI sends when the last card is removed.
        # Placed before the failing-run block below: this run succeeds and leaves `selection`
        # equal to `source`, which that block's CSV assertion tolerates.
        body = JSON.json((; filters = [], nodes = [], groups = Dict{String, Any}()))
        resp = HTTP.post(url * "probe-pipeline", body = body)
        @test JSON.parse(resp.body)["valid"] == true
        resp = HTTP.post(url * "evaluate-pipeline", body = body)
        empty_run = JSON.parse(resp.body)
        @test empty_run["valid"] == true
        @test "TEMP" in [s["name"] for s in empty_run["summaries"]]

        # Groups but no cards: the usual authoring order is groups first, so this is what the UI's
        # continuous probe sends for most of the time a document is being written. It has to
        # resolve — `group_outputs = c.outputs[1:end]` over zero nodes — or the author gets no
        # live finding on their groups until the first card exists.
        groups_only = JSON.json((;
            filters = [],
            nodes = [],
            groups = Dict("g" => [Dict("cols" => "TEMP")]),
        ))
        resp = HTTP.post(url * "probe-pipeline", body = groups_only)
        @test JSON.parse(resp.body)["valid"] == true

        # An empty group is a document the schema accepts (`weather = []` constructs) that
        # resolves to zero columns; a card reading it used to die inside the card constructor
        # with `UndefKeywordError: keyword argument args not assigned` (measured 2026-09-16,
        # smoke check 5). The probe and the run both name the group instead.
        reads_empty = JSON.json((;
            filters = [],
            nodes = [(; id = "z", card = Dict(
                "type" => "rescale", "method" => Dict("type" => "zscore"),
                "inputs" => [Dict("groups" => "empty")], "suffix" => "z",
            ))],
            groups = Dict("empty" => []),
        ))
        for route in ("probe-pipeline", "evaluate-pipeline")
            resp = HTTP.post(url * route, body = reads_empty)
            answer = JSON.parse(resp.body)
            @test answer["valid"] == false
            @test answer["kind"] == "pipeline"
            issue = only(answer["issues"])
            @test issue["pointer"] == "/groups/empty"
            @test issue["reason"] == "empty"
            @test issue["severity"] == "error"
            @test occursin("empty", issue["message"])
            @test !occursin("UndefKeywordError", join(answer["errors"]))
        end
        # An empty group used to end the reply: the cards were never looked at, so a document
        # with an empty group *and* a broken card named the group only, and the card turned red
        # one fix and one question later (seen in a browser, 2026-09-21, loading a document).
        # Both are told in one answer, the group first as in the document.
        empty_and_broken = JSON.json((;
            filters = [],
            nodes = [
                (; id = "fine", card = Dict(
                    "type" => "rescale", "method" => Dict("type" => "zscore"),
                    "inputs" => [Dict("cols" => "TEMP")], "suffix" => "z",
                )),
                (; id = "broken", card = Dict("type" => "rescale")),
            ],
            groups = Dict("empty" => []),
        ))
        for route in ("probe-pipeline", "evaluate-pipeline")
            answer = JSON.parse(HTTP.post(url * route, body = empty_and_broken).body)
            @test answer["valid"] == false
            @test answer["kind"] == "pipeline"
            @test [(issue["pointer"], issue["reason"]) for issue in answer["issues"]] ==
                [("/groups/empty", "empty"), ("/nodes/1/card", "required")]
            @test length(answer["errors"]) == 2
            @test !occursin("UndefKeywordError", join(answer["errors"]))
        end
        # Every issue says how bad it is; a schema failure is an error.
        two_broken = JSON.json((;
            filters = [],
            nodes = [(; id = "a", card = Dict("type" => "cluster")),
                     (; id = "b", card = Dict("type" => "split"))],
            groups = Dict{String, Any}(),
        ))
        resp = HTTP.post(url * "evaluate-pipeline", body = two_broken)
        failed = JSON.parse(resp.body)
        @test failed["valid"] == false && failed["kind"] == "pipeline"
        @test [i["pointer"] for i in failed["issues"]] == ["/nodes/0/card", "/nodes/1/card"]
        @test all(i["severity"] == "error" for i in failed["issues"])
        @test !isempty(failed["errors"])

        # A13: two cards emitting the same column name. The second silently replaced the first's
        # output (and a source column would be replaced the same way — `rescale TEMP suffix =
        # "rescaled"` over a source with `TEMP_rescaled`, measured 2026-09-13 and on 1M rows
        # 2026-09-16). A warning, not a rejection: overwriting can be meant.
        same_name = JSON.json((;
            filters = [],
            nodes = [
                (; id = "one", card = Dict("type" => "rescale", "method" => Dict("type" => "zscore"),
                    "inputs" => [Dict("cols" => "TEMP")], "suffix" => "z")),
                (; id = "two", card = Dict("type" => "rescale", "method" => Dict("type" => "minmax"),
                    "inputs" => [Dict("cols" => "TEMP")], "suffix" => "z")),
            ],
            groups = Dict{String, Any}(),
        ))
        resp = HTTP.post(url * "probe-pipeline", body = same_name)
        probed = JSON.parse(resp.body)
        @test probed["valid"] == true
        warning = only(i for i in probed["issues"] if i["reason"] == "overwrites")
        @test warning["severity"] == "warning"
        @test warning["pointer"] == "/nodes/1/card"
        @test occursin("TEMP_z", warning["message"])
        resp = HTTP.post(url * "evaluate-pipeline", body = same_name)
        @test JSON.parse(resp.body)["valid"] == true

        # The rows take a different path — DuckDB writes the page as JSON itself, and its writer
        # emits bare `NaN`/`Infinity`, which a browser's JSON.parse rejects (measured 2026-09-16).
        # Julia's parser accepts those tokens, so this asserts on the text.
        DBInterface.execute(Returns(nothing), DashiBoard.REPOSITORY[],
            "CREATE OR REPLACE TABLE selection AS SELECT 'nan'::DOUBLE AS bad, 2.5 AS good, 'x' AS s")
        body = JSON.json((; offset = 0, limit = 10, filterModel = Dict(), sortModel = [], processed = true))
        resp = HTTP.post(url * "fetch-data", body = body)
        page = String(resp.body)
        @test !occursin("NaN", page) && !occursin("Infinity", page)
        @test JSON.parse(page)["values"][1]["bad"] === nothing
        @test JSON.parse(page)["values"][1]["good"] == 2.5

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

        # A loop is a fault of the document, not of any one card, and Graphs.jl's sentence for it
        # names nothing. The handlers name the members: an issue that points at no item
        # (`pointer = ""`), with the members under `related` and in the message. Seen in a
        # browser on 2026-09-18 with the bare sentence written on every card that was asked.
        @testset "loops" begin
            rescale(id, input) = (; id, card = Dict(
                "type" => "rescale", "method" => Dict("type" => "zscore"),
                "inputs" => [input], "suffix" => id,
            ))
            looped = JSON.json((;
                filters = [],
                nodes = [rescale("a", Dict("nodes" => "b")), rescale("b", Dict("nodes" => "a")), rescale("c", Dict("cols" => "TEMP"))],
                groups = Dict{String, Any}(),
            ))
            for route in ("probe-pipeline", "evaluate-pipeline")
                answer = JSON.parse(HTTP.post(url * route, body = looped).body)
                @test answer["valid"] == false
                @test answer["kind"] == "pipeline"
                issue = only(answer["issues"])
                @test issue["reason"] == "loop"
                @test issue["pointer"] == ""
                @test issue["severity"] == "error"
                @test issue["related"] == ["/nodes/0", "/nodes/1"]
                @test issue["message"] == "The input graph contains at least one loop: a, b"
                @test answer["errors"] == [issue["message"]]
            end

            # Through a group: the group is a member, named and pointed at like one.
            via_group = JSON.json((;
                filters = [],
                nodes = [rescale("a", Dict("groups" => "g")), rescale("b", Dict("nodes" => "a"))],
                groups = Dict("g" => [Dict("nodes" => "b")]),
            ))
            issue = only(JSON.parse(HTTP.post(url * "probe-pipeline", body = via_group).body)["issues"])
            @test issue["related"] == ["/nodes/0", "/nodes/1", "/groups/g"]
            @test endswith(issue["message"], ": a, b, g")
        end
    end

    close(server)

    # A data directory that does not exist used to make every listing throw: a 500 with an
    # empty body, logged as 200 (see `LoggingMiddleware`), and an empty picker with no reason.
    @testset "a missing data directory" begin
        nowhere_port = first_free_port(8281:8380)
        nowhere = DashiBoard.launch(
            joinpath(data_dir, "does-not-exist");
            port = nowhere_port, async = true, model_directory, training_directory
        )
        resp = HTTP.post("http://127.0.0.1:$(nowhere_port)/list-files", body = "{}", status_exception = false)
        @test resp.status == 200
        @test JSON.parse(resp.body) == []
        close(nowhere)
    end
end
