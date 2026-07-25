@testset "groups" begin
    d = TOML.parsefile(joinpath(@__DIR__, "static", "configs", "groups.toml"))
    ps = Pipelines.Params(d["nodes"], d["groups"])
    g, cols = Pipelines.dependency_graph!(ps)
    es = sort(collect(edges(g)))
    node_vals, group_vals = ps.node_configs, ps.group_configs

    # @test grp_keys == ["weather"] FIXME!
    @test group_vals[1].cols == ["PRES", "TEMP"]
    @test group_vals[1].through == String[]

    @test node_vals[1]["card"]["group_by"].cols == ["cbwd"]
    @test node_vals[1]["card"]["inputs"][1].groups == ["weather"]
    @test node_vals[1]["card"]["inputs"][2].cols == ["No"]
    @test node_vals[1]["card"]["partition"].nodes == ["partition"]

    @test node_vals[2]["card"]["inputs"].cols == ["No"]

    @test node_vals[3]["card"]["inputs"][1].nodes == ["log"]
    @test node_vals[3]["card"]["inputs"][2].groups == ["weather"]
    @test node_vals[3]["card"]["inputs"][2].through == ["rescale"]

    @test node_vals[4]["card"]["order_by"].cols == ["No"]

    @test length(es) == 5
    @test Pair(es[1]) == (1 => 3)
    @test Pair(es[2]) == (2 => 3)
    @test Pair(es[3]) == (4 => 1)
    @test Pair(es[4]) == (5 => 1)
    @test Pair(es[5]) == (5 => 3)

    @test cols == ["cbwd", "No", "PRES", "TEMP"] # TODO: consider keeping them grouped
end

@testset "groups schema" begin
    deps = Pipelines.Deps(
        nodes = ["rescale", "log", "pca", "partition"],
        groups = ["weather"],
        cols = [
            "No", "year", "month", "day", "hour",
            "pm2.5", "DEWP", "TEMP", "PRES", "cbwd",
            "Iws", "Is", "Ir",
        ]
    )
    d = TOML.parsefile(joinpath(@__DIR__, "static", "configs", "groups.toml"))
    for node in d["nodes"]
        card = node["card"]
        schema = Pipelines.json_schema(card["type"], deps) |> JSONSchema.Schema
        @test JSONSchema.validate(schema, card) === nothing
    end

    # exactly one between `nodes`, `groups`, and `cols` is allowed
    card = deepcopy(d["nodes"][1]["card"])
    card["inputs"] = Dict("groups" => ["weather"], "cols" => ["No"])
    schema = Pipelines.json_schema(card["type"], deps) |> JSONSchema.Schema
    issue = JSONSchema.validate(schema, card)
    @test issue !== nothing
    @test occursin("oneOf", string(issue))
    card["inputs"] = Dict()
    issue = JSONSchema.validate(schema, card)
    @test issue !== nothing
    @test occursin("oneOf", string(issue))

    schema = Pipelines.groups_schema(deps) |> JSONSchema.Schema
    @test JSONSchema.validate(schema, d["groups"]) === nothing

    empty!(deps.groups)
    push!(deps.groups, "wether")
    card = d["nodes"][1]["card"]
    schema = Pipelines.json_schema(card["type"], deps) |> JSONSchema.Schema
    issue = JSONSchema.validate(schema, card)
    @test issue !== nothing
    @test occursin("weather", string(issue))
    @test occursin("wether", string(issue))

    empty!(deps.groups)
    push!(deps.groups, "weather")
    push!(deps.groups, "grp_name")
    schema = Pipelines.groups_schema(deps) |> JSONSchema.Schema
    issue = JSONSchema.validate(schema, d["groups"])
    @test issue !== nothing
    @test occursin("grp_name", string(issue))

    empty!(deps.groups)
    schema = Pipelines.groups_schema(deps) |> JSONSchema.Schema
    issue = JSONSchema.validate(schema, d["groups"])
    @test issue !== nothing
    @test occursin("additionalProperties", string(issue))

    empty!(deps.groups)
    push!(deps.groups, "weather")
    empty!(deps.cols)
    schema = Pipelines.groups_schema(deps) |> JSONSchema.Schema
    issue = JSONSchema.validate(schema, d["groups"])
    @test issue !== nothing
    @test occursin("TEMP", string(issue)) || occursin("PRES", string(issue))
end

@testset "node_digraph" begin
    spec = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "spec.json"))
    repo = Repository()

    mktempdir() do dir
        Downloads.download(
            "https://raw.githubusercontent.com/jbrownlee/Datasets/master/pollution.csv",
            joinpath(dir, "pollution.csv")
        )
        DataIngestion.load_files(repo, dir, spec["data"])
    end
    d = TOML.parsefile(joinpath(@__DIR__, "static", "configs", "groups.toml"))
    pipeline = Pipelines.Pipeline(d["nodes"], d["groups"])
    Pipelines.train_evaljoin!(repo, pipeline, "source", "No")
    df = DBInterface.execute(DataFrame, repo, "FROM source")
    # order-insensitive: `evaljoin_many` appends independent nodes' columns
    # concurrently, so column order is not deterministic under multithreading.
    @test issetequal(
        names(df),
        [
            "No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP",
            "PRES", "cbwd", "Iws", "Is", "Ir", "_name", "No_log", "partition",
            "PRES_rescaled", "TEMP_rescaled", "No_rescaled", "component_1", "component_2",
        ]
    )
end
