using HTTP, DataIngestion, Pipelines, JSON, DBInterface, DataFrames
using DashiBoard
using Test
using Downloads

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
    Pipelines.evaluate(repo, cards, "selection")

    res = DBInterface.execute(DataFrame, repo, "FROM selection")

    @testset "cards" begin
        @test "_tiled_partition" in names(res)
        @test "_percentile_partition" in names(res)
    end

    static_directory = joinpath(@__DIR__, "..", "..", "static")
    model_directory = joinpath(static_directory, "model")
    training_directory = joinpath(static_directory, "training")

    # Add trivial card
    _train(wc, t, id; weights = nothing) = nothing
    function _evaluate(wc, model, t, id)
        return Pipelines.SimpleTable(k => zeros(length(id)) for k in wc.outputs), id
    end
    Pipelines.register_wild_card("trivial", "Trivial", _train, _evaluate)

    server = DashiBoard.launch(
        data_dir;
        async = true,
        model_directory,
        training_directory
    )

    @testset "request" begin
        url = "http://127.0.0.1:8080/"

        body = read(joinpath(@__DIR__, "static", "card-configurations.json"), String)
        resp = HTTP.post(url * "get-card-configurations", body = body)
        configs = JSON.parse(IOBuffer(resp.body))
        @test configs isa AbstractVector
        @test length(configs) == 9
        @test resp.headers == [
            DashiBoard.CORS_RES_HEADERS...,
            "Content-Type" => "application/json",
            "Transfer-Encoding" => "chunked",
        ]
        resp = HTTP.request("OPTIONS", url * "get-card-configurations")
        @test resp.headers == [
            DashiBoard.CORS_OPTIONS_HEADERS...,
            "Transfer-Encoding" => "chunked",
        ]

        body = read(joinpath(@__DIR__, "static", "load.json"), String)
        resp = HTTP.post(url * "load-files", body = body)
        summaries = JSON.parse(IOBuffer(resp.body))
        @test summaries[end]["name"] == "_name"
        @test resp.headers == [
            DashiBoard.CORS_RES_HEADERS...,
            "Content-Type" => "application/json",
            "Transfer-Encoding" => "chunked",
        ]

        body = read(joinpath(@__DIR__, "static", "pipeline.json"), String)
        resp = HTTP.post(url * "evaluate-pipeline", body = body)
        summaries = JSON.parse(IOBuffer(resp.body))["summaries"]
        @test summaries[end]["name"] == "_tiled_partition"
        @test resp.headers == [
            DashiBoard.CORS_RES_HEADERS...,
            "Content-Type" => "application/json",
            "Transfer-Encoding" => "chunked",
        ]

        body = read(joinpath(@__DIR__, "static", "fetch.json"), String)
        resp = HTTP.post(url * "fetch-data", body = body)
        tbl = JSON.parse(IOBuffer(resp.body))
        df = DBInterface.execute(DataFrame, DashiBoard.REPOSITORY[], "FROM selection")
        @test tbl["length"] == nrow(df)
        @test [row["No"] for row in tbl["values"]] == df.No[11:60]
        @test resp.headers == [
            DashiBoard.CORS_RES_HEADERS...,
            "Content-Type" => "application/json",
            "Transfer-Encoding" => "chunked",
        ]

        HTTP.open("GET", url * "get-processed-data") do stream
            r = startread(stream)
            io = IOBuffer()
            write(io, stream)
            data = take!(io)

            @test length(data) == 360326
            @test r.headers == [
                DashiBoard.CORS_RES_HEADERS...,
                "Content-Type" => "text/csv",
                "Transfer-Encoding" => "chunked",
                "Content-Length" => "360326",
            ]
        end
        resp = HTTP.request("OPTIONS", url * "get-processed-data")
        @test resp.headers == [
            DashiBoard.CORS_OPTIONS_HEADERS...,
            "Transfer-Encoding" => "chunked",
        ]

    end

    close(server)
end
