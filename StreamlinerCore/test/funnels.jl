using DashiBase: DashiBase
using JSONSchema: JSONSchema

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

    funnel = StreamlinerCore.DBFunnel(order_by = ["No"], inputs = ["TEMP", "PRES"], targets = ["Iws"])

    @test StreamlinerCore.get_helper_table_keys(funnel) == (tables = String[], files = String[])

    # What is written back is the document: no entry for a transform nobody named, none for the
    # default loader.
    @test StreamlinerCore.get_metadata(funnel) == Dict{String, Any}(
        "order_by" => ["No"], "inputs" => ["TEMP", "PRES"], "targets" => ["Iws"],
    )

    table_spec = StreamlinerCore.TableSpec(
        repository = repo,
        schema = schema,
        table = "split",
        id_var = "No"
    )
    data = StreamlinerCore.FunneledData(Val(2), funnel, table_spec, partition = "_partition")

    @test isnothing(data.helper_tables)

    helper_tables = Dict("fake_key" => "table_name")
    helper_files = Dict("fake_key" => "table_name")
    @test_throws ArgumentError StreamlinerCore.initialize_helper_tables!(
        data, tables = helper_tables, files = helper_files
    )

    helper_tables = Dict()
    helper_files = Dict()

    StreamlinerCore.initialize_helper_tables!(data, tables = helper_tables, files = helper_files)
    @test data.helper_tables == Dict()
    @test data.helper_files == Dict()

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
    data1 = StreamlinerCore.FunneledData(Val(1), funnel, table_spec, partition = "_partition")
    outputs = [(_id = [1, 2], prediction = [10.0 20.0]), (_id = [3, 4], prediction = [30.0 40.0])]

    StreamlinerCore.ingest(data1, outputs, (:prediction,); suffix = "hat", destination = "outputs")

    df = DBInterface.execute(DataFrame, repo, "FROM schm.outputs")
    @test df.No == [1, 2, 3, 4]
    @test df.Iws_hat == [10.0, 20.0, 30.0, 40.0]

    funnel = StreamlinerCore.DBFunnel(order_by = ["No"], inputs = ["TEMP", "PRES"], targets = ["cbwd"])

    data = StreamlinerCore.FunneledData(Val(2), funnel, table_spec; partition = "_partition")
    StreamlinerCore.compute_unique_values!(data)

    batches = StreamlinerCore.stream(collect, data, 2, streaming)

    @test size(batches[1].input) == (2, 32)
    @test size(batches[1].target) == (4, 32)

    @test StreamlinerCore.get_templates(data) === (
        input = StreamlinerCore.Template(Float32, (2,)),
        target = StreamlinerCore.Template(Float32, (4,)),
    )

    # A transform is applied to its column on the way in, and to no other.
    plain = StreamlinerCore.DBFunnel(order_by = ["No"], inputs = ["TEMP", "PRES"], targets = ["Iws"])
    logged = StreamlinerCore.DBFunnel(
        order_by = ["No"], inputs = ["TEMP", "PRES"], targets = ["Iws"],
        input_transforms = Dict("PRES" => "log"),
    )
    first_batch(f) = first(
        StreamlinerCore.stream(
            collect, StreamlinerCore.FunneledData(Val(2), f, table_spec; partition = "_partition"), 1, streaming
        )
    )
    a, b = first_batch(plain), first_batch(logged)
    @test b.input[1, :] == a.input[1, :]
    @test b.input[2, :] ≈ log.(a.input[2, :])
    @test b.target == a.target

    # A one-hot column has no single value to transform; that is only known once the data is read.
    onehot = StreamlinerCore.DBFunnel(
        order_by = ["No"], inputs = ["TEMP"], targets = ["cbwd"],
        target_transforms = Dict("cbwd" => "log"),
    )
    data = StreamlinerCore.FunneledData(Val(2), onehot, table_spec; partition = "_partition")
    StreamlinerCore.compute_unique_values!(data)
    e = try
        StreamlinerCore.stream(collect, data, 1, streaming); nothing
    catch err
        err
    end
    @test e isa StreamlinerCore.TransformError
    @test e.path == ["target_transforms", "cbwd"]
end

@testset "a funnel is one definition" begin
    SC = StreamlinerCore
    ir = SC.funnel_IR(SC.DBFunnel)
    @test [p.key for p in ir.properties] ==
        ["order_by", "inputs", "input_transforms", "targets", "target_transforms", "loader"]
    transforms = only(p for p in ir.properties if p.key == "input_transforms").value
    @test transforms isa DashiBase.MapIR && transforms.keys_from == "inputs"
    @test transforms.values.enum == ["asinh", "log", "log1p", "sqrt"]
    @test only(p for p in ir.properties if p.key == "order_by").required
    @test !only(p for p in ir.properties if p.key == "loader").required
    # With the default loader the columns must be named; a file loader may stand in for them.
    @test length(ir.constraints) == 1

    tagged = DashiBase.IR_from_type(SC.Funnel, nothing)
    @test tagged.options == [""] && tagged.default_option == ""
    @test [p.key for p in tagged.objects[""].properties] == [p.key for p in ir.properties]

    d = Dict{String, Any}(
        "order_by" => ["No"], "inputs" => ["TEMP", "Iws"], "targets" => ["Iws"],
        "input_transforms" => Dict("Iws" => "log"),
    )
    funnel = SC.get_streamliner_funnel(d)
    @test funnel isa SC.DBFunnel
    @test SC.get_order_by(funnel) == ["No"]
    @test SC.colname.(SC.get_inputs(funnel)) == ["TEMP", "Iws"]
    @test [c.transform_name for c in SC.get_inputs(funnel)] == ["identity", "log"]
    # The same column as a target is its own entry: untransformed unless its own map says so.
    @test only(SC.get_targets(funnel)).transform === identity
    @test isnothing(SC.get_input_paths(funnel)) && isnothing(SC.get_target_paths(funnel))
    @test SC.get_metadata(funnel) == d
    @test SC.get_streamliner_funnel(SC.get_metadata(funnel)) == funnel
    # Naming the default funnel and leaving it out are the same document.
    @test SC.get_streamliner_funnel(merge(d, Dict("type" => ""))) == funnel

    stale = merge(d, Dict("input_transforms" => Dict("PRES" => "log")))
    e = @test_throws SC.TransformError SC.get_streamliner_funnel(stale)
    @test e.value.path == ["input_transforms", "PRES"]
    @test isnothing(e.value.pointer)
    @test occursin("PRES", sprint(showerror, e.value))

    @test_throws ArgumentError SC.get_streamliner_funnel(Dict{String, Any}("inputs" => ["a"], "targets" => ["b"]))
    @test_throws ArgumentError SC.get_streamliner_funnel(Dict{String, Any}("order_by" => ["No"], "targets" => ["b"]))
    @test_throws ArgumentError SC.get_streamliner_funnel(Dict{String, Any}("order_by" => ["No"], "inputs" => ["a"]))

    # The schema says the same: closed, and the columns required with the default loader.
    schema = DashiBase.json_schema(tagged)
    schema["\$defs"] = Dict{String, Any}(
        "variable" => Dict("type" => "string"),
        "variables" => Dict("type" => "array", "items" => Dict("type" => "string")),
        "nonempty_variables" => Dict("type" => "array", "items" => Dict("type" => "string"), "minItems" => 1),
    )
    s = JSONSchema.Schema(schema)
    @test isnothing(JSONSchema.validate(d, s))
    @test !isnothing(JSONSchema.validate(merge(d, Dict("inptus" => ["TEMP"])), s))
    @test !isnothing(JSONSchema.validate(merge(d, Dict("input_transforms" => Dict("Iws" => "cube"))), s))
    @test !isnothing(JSONSchema.validate(Dict{String, Any}("order_by" => ["No"], "targets" => ["Iws"]), s))
end

@testset "transforms" begin
    @test StreamlinerCore.transform_names() == ["asinh", "log", "log1p", "sqrt"]
    @test !haskey(StreamlinerCore.PARSER[].transforms, "")
    x = Float32[1, 4, 9]
    @test StreamlinerCore.RichColumn("a", "sqrt").transform(x) == Float32[1, 2, 3]
    @test StreamlinerCore.RichColumn("a", "log").transform(x) ≈ log.(x)
    @test StreamlinerCore.RichColumn("a").transform === identity
    @test_throws KeyError StreamlinerCore.RichColumn("a", "")
end
