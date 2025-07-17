@testset "basic funnel" begin
    spec = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "spec.json"))
    schema = "schm"
    repo = Repository()
    DBInterface.execute(Returns(nothing), repo, "CREATE SCHEMA schm;")
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "split.json"))
    node = Node(Card(d["tiles"]))

    mktempdir() do data_dir
        Downloads.download(
            "https://raw.githubusercontent.com/jbrownlee/Datasets/master/pollution.csv",
            joinpath(data_dir, "pollution.csv")
        )
        DataIngestion.load_files(repo, data_dir, spec["data"]; schema)
    end
    Pipelines.train_evaljoin!(repo, node, "source" => "split"; schema)

    data = Pipelines.DBData{2}(
        repository = repo,
        schema = schema,
        table = "split",
        order_by = ["No"],
        inputs = ["TEMP", "PRES"],
        targets = ["Iws"],
        partition = "_tiled_partition"
    )

    df = DBInterface.execute(DataFrame, repo, "FROM schm.split ORDER BY No")

    @test StreamlinerCore.get_nsamples(data, 1) === count(==(1), df._tiled_partition)
    @test StreamlinerCore.get_nsamples(data, 2) === count(==(2), df._tiled_partition)

    @test StreamlinerCore.get_templates(data) === (
        input = StreamlinerCore.Template(Float32, (2,)),
        target = StreamlinerCore.Template(Float32, (1,)),
    )

    @test StreamlinerCore.get_metadata(data) == Dict(
        "schema" => schema,
        "table" => "split",
        "order_by" => ["No"],
        "inputs" => ["TEMP", "PRES"],
        "targets" => ["Iws"],
        "partition" => "_tiled_partition",
    )

    parser = StreamlinerCore.default_parser()
    d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "streaming.json"))

    streaming = Streaming(parser, d["shuffled"])
    len = cld(count(==(1), df._tiled_partition), 32)
    len′ = StreamlinerCore.stream(length, data, 1, streaming)
    batches = StreamlinerCore.stream(collect, data, 1, streaming)
    @test len == len′ == length(batches)

    @test size(batches[1].input) == (2, 32)
    @test size(batches[1].target) == (1, 32)

    len = cld(count(==(2), df._tiled_partition), 32)
    len′ = StreamlinerCore.stream(length, data, 2, streaming)
    batches = StreamlinerCore.stream(collect, data, 2, streaming)
    @test len == len′ == length(batches)

    @test size(batches[1].input) == (2, 32)
    @test size(batches[1].target) == (1, 32)

    batches′ = StreamlinerCore.stream(collect, data, 2, streaming)
    @test batches′[1].input != batches[1].input # ensure randomness

    streaming = Streaming(parser, d["unshuffled"])
    len = cld(count(==(1), df._tiled_partition), 32)
    len′ = StreamlinerCore.stream(length, data, 1, streaming)
    batches = StreamlinerCore.stream(collect, data, 1, streaming)
    @test len == len′ == length(batches)

    dd = subset(df, "_tiled_partition" => x -> x .== 1)

    @test size(batches[1].input) == (2, 32)
    @test size(batches[1].target) == (1, 32)
    @test batches[1].input == Float32.(Matrix(dd[1:32, ["TEMP", "PRES"]])')
    @test batches[1].target == Float32.(Matrix(dd[1:32, ["Iws"]])')

    len = cld(count(==(2), df._tiled_partition), 32)
    len′ = StreamlinerCore.stream(length, data, 2, streaming)
    batches = StreamlinerCore.stream(collect, data, 2, streaming)
    @test len == len′ == length(batches)

    dd = subset(df, "_tiled_partition" => x -> x .== 2)

    @test size(batches[1].input) == (2, 32)
    @test size(batches[1].target) == (1, 32)
    @test batches[1].input == Float32.(Matrix(dd[1:32, ["TEMP", "PRES"]])')
    @test batches[1].target == Float32.(Matrix(dd[1:32, ["Iws"]])')

    batches′ = StreamlinerCore.stream(collect, data, 2, streaming)
    @test batches′[1].input == batches[1].input # ensure determinism

    data = Pipelines.DBData{2}(
        repository = repo,
        schema = schema,
        table = "split",
        order_by = ["No"],
        inputs = ["TEMP", "PRES"],
        targets = ["cbwd"],
        partition = "_tiled_partition"
    )
    Pipelines.train!(data)

    batches = StreamlinerCore.stream(collect, data, 2, streaming)

    @test size(batches[1].input) == (2, 32)
    @test size(batches[1].target) == (4, 32)

    @test StreamlinerCore.get_templates(data) === (
        input = StreamlinerCore.Template(Float32, (2,)),
        target = StreamlinerCore.Template(Float32, (4,)),
    )
end
