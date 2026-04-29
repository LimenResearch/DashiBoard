@testset "FunneledData" begin
    schema = "schm"
    repo = Repository()
    DBInterface.execute(Returns(nothing), repo, "CREATE SCHEMA schm;")

    sql = """
    CREATE TABLE schm.split AS
    FROM read_csv('https://raw.githubusercontent.com/jbrownlee/Datasets/master/pollution.csv')
    SELECT *, CASE WHEN random() > 0.8 THEN 2 ELSE 1 END AS _partition;
    """
    DBInterface.execute(Returns(nothing), repo, sql)

    funnel = StreamlinerCore.DBFunnel(
        order_by = ["No"],
        inputs = StreamlinerCore.RichColumn.(["TEMP", "PRES"]),
        targets = StreamlinerCore.RichColumn.(["Iws"])
    )

    @test StreamlinerCore.get_metadata(funnel) == Dict(
        "order_by" => ["No"],
        "inputs" => [Dict("colname" => "TEMP", "transform" => ""), Dict("colname" => "PRES", "transform" => "")],
        "input_paths" => nothing,
        "targets" => [Dict("colname" => "Iws", "transform" => "")],
        "target_paths" => nothing,
    )

    data = StreamlinerCore.FunneledData(
        Val(2), funnel,
        repository = repo,
        schema = schema,
        table = "split",
        id_var = "No",
        partition = "_partition",
    )

    df = DBInterface.execute(DataFrame, repo, "FROM schm.split ORDER BY No")

    @test StreamlinerCore.get_nsamples(data, 1) === count(==(1), df._partition)
    @test StreamlinerCore.get_nsamples(data, 2) === count(==(2), df._partition)

    @test StreamlinerCore.get_templates(data) === (
        input = StreamlinerCore.Template(Float32, (2,)),
        target = StreamlinerCore.Template(Float32, (1,)),
    )

    parser = StreamlinerCore.default_parser()

    streaming = Streaming(parser, joinpath(@__DIR__, "static", "streaming", "shuffled.toml"))
    len = cld(count(==(1), df._partition), 32)
    len′ = StreamlinerCore.stream(length, data, 1, streaming)
    batches = StreamlinerCore.stream(collect, data, 1, streaming)
    @test len == len′ == length(batches)

    @test size(batches[1].input) == (2, 32)
    @test size(batches[1].target) == (1, 32)

    len = cld(count(==(2), df._partition), 32)
    len′ = StreamlinerCore.stream(length, data, 2, streaming)
    batches = StreamlinerCore.stream(collect, data, 2, streaming)
    @test len == len′ == length(batches)

    @test size(batches[1].input) == (2, 32)
    @test size(batches[1].target) == (1, 32)

    batches′ = StreamlinerCore.stream(collect, data, 2, streaming)
    @test batches′[1].input != batches[1].input # ensure randomness

    streaming = Streaming(parser, joinpath(@__DIR__, "static", "streaming", "unshuffled.toml"))
    len = cld(count(==(1), df._partition), 32)
    len′ = StreamlinerCore.stream(length, data, 1, streaming)
    batches = StreamlinerCore.stream(collect, data, 1, streaming)
    @test len == len′ == length(batches)

    dd = subset(df, "_partition" => x -> x .== 1)

    @test size(batches[1].input) == (2, 32)
    @test size(batches[1].target) == (1, 32)
    @test batches[1].input == Float32.(Matrix(dd[1:32, ["TEMP", "PRES"]])')
    @test batches[1].target == Float32.(Matrix(dd[1:32, ["Iws"]])')

    len = cld(count(==(2), df._partition), 32)
    len′ = StreamlinerCore.stream(length, data, 2, streaming)
    batches = StreamlinerCore.stream(collect, data, 2, streaming)
    @test len == len′ == length(batches)

    dd = subset(df, "_partition" => x -> x .== 2)

    @test size(batches[1].input) == (2, 32)
    @test size(batches[1].target) == (1, 32)
    @test batches[1].input == Float32.(Matrix(dd[1:32, ["TEMP", "PRES"]])')
    @test batches[1].target == Float32.(Matrix(dd[1:32, ["Iws"]])')

    batches′ = StreamlinerCore.stream(collect, data, 2, streaming)
    @test batches′[1].input == batches[1].input # ensure determinism

    # TODO: ingestion with categorical target?
    data1 = StreamlinerCore.FunneledData{StreamlinerCore.DBFunnel, 1}(data)
    outputs = [(id = [1, 2], prediction = [10.0 20.0]), (id = [3, 4], prediction = [30.0 40.0])]

    StreamlinerCore.ingest(data1, outputs, (:prediction,); suffix = "hat", destination = "outputs")

    df = DBInterface.execute(DataFrame, repo, "FROM schm.outputs")
    @test df.No == [1, 2, 3, 4]
    @test df.Iws_hat == [10.0, 20.0, 30.0, 40.0]

    funnel = StreamlinerCore.DBFunnel(
        order_by = ["No"],
        inputs = StreamlinerCore.RichColumn.(["TEMP", "PRES"]),
        targets = StreamlinerCore.RichColumn.(["cbwd"]),
    )

    data = StreamlinerCore.FunneledData(
        Val(2), funnel;
        repository = repo,
        schema = schema,
        table = "split",
        id_var = "No",
        partition = "_partition"
    )
    StreamlinerCore.compute_unique_values!(data)

    batches = StreamlinerCore.stream(collect, data, 2, streaming)

    @test size(batches[1].input) == (2, 32)
    @test size(batches[1].target) == (4, 32)

    @test StreamlinerCore.get_templates(data) === (
        input = StreamlinerCore.Template(Float32, (2,)),
        target = StreamlinerCore.Template(Float32, (4,)),
    )
end
