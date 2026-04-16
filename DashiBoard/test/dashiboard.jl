using HTTP, DataIngestion, Pipelines, JSON, DBInterface, DataFrames
using DashiBoard
using Test
using Downloads

# Add trivial card
Pipelines._train(wc::WildCard{:trivial}, t, id_var) = nothing
function (wc::WildCard{:trivial})(model, t, id_var)
    id = t[id_var]
    nrows = length(id)
    return Dict(id_var => id, (k => zeros(nrows) for k in wc.outputs)...)
end
card_config = CardConfig{WildCard{:trivial}}(
    key = "trivial",
    label = "Trivial",
    needs_targets = false,
    needs_order = false,
    allows_partition = false,
    allows_weights = false
)
Pipelines.register_card(card_config)

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

    server = DashiBoard.launch(
        data_dir;
        port = 8080,
        async = true,
        model_directory,
        training_directory
    )

    @testset "request" begin
        url = "http://127.0.0.1:8080/"

        body = read(joinpath(@__DIR__, "static", "card-widgets.json"), String)
        resp = HTTP.post(url * "get-card-widgets", body = body)
        configs = JSON.parse(resp.body)
        @test configs isa AbstractVector
        @test length(configs) == length(Pipelines.CARD_CONFIGS)
        @test resp.headers == [
            DashiBoard.CORS_RES_HEADERS...,
            "Content-Type" => "application/json",
            "Transfer-Encoding" => "chunked",
        ]
        resp = HTTP.request("OPTIONS", url * "get-card-widgets")
        @test resp.headers == [
            DashiBoard.CORS_OPTIONS_HEADERS...,
            "Transfer-Encoding" => "chunked",
        ]

        body = read(joinpath(@__DIR__, "static", "load.json"), String)
        resp = HTTP.post(url * "load-files", body = body)
        summaries = JSON.parse(resp.body)
        @test summaries[end]["name"] == "_name"
        @test resp.headers == [
            DashiBoard.CORS_RES_HEADERS...,
            "Content-Type" => "application/json",
            "Transfer-Encoding" => "chunked",
        ]

        body = read(joinpath(@__DIR__, "static", "pipeline.json"), String)
        resp = HTTP.post(url * "evaluate-pipeline", body = body)
        summaries = JSON.parse(resp.body)["summaries"]
        @test summaries[end]["name"] == "_tiled_partition"
        @test resp.headers == [
            DashiBoard.CORS_RES_HEADERS...,
            "Content-Type" => "application/json",
            "Transfer-Encoding" => "chunked",
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
            "Transfer-Encoding" => "chunked",
        ]

        HTTP.open("GET", url * "get-processed-data") do stream
            r = startread(stream)
            io = IOBuffer()
            write(io, stream)
            data = take!(io)

            @test length(data) == 394870
            @test r.headers == [
                DashiBoard.CORS_RES_HEADERS...,
                "Content-Type" => "text/csv",
                "Transfer-Encoding" => "chunked",
                "Content-Length" => "394870",
            ]
            s = String(data)
            l1, l2 = Iterators.take(eachsplit(s, '\n'), 2)
            @test l1 == "No,year,month,day,hour,pm2.5,DEWP,TEMP,PRES,cbwd,Iws,Is,Ir,_name,_id,_percentile_partition,_tiled_partition"
            @test l2 == "8761,2011,1,1,0,NA,-21,-9,1033.0,NW,570.41,0,0,pollution,8761,1,1"
        end
        resp = HTTP.request("OPTIONS", url * "get-processed-data")
        @test resp.headers == [
            DashiBoard.CORS_OPTIONS_HEADERS...,
            "Transfer-Encoding" => "chunked",
        ]

    end

    close(server)
end
