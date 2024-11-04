@kwdef struct PartitionSpec
    sorters::Vector{String}
    by::Vector{String}
    tiles::Vector{Int}
    output::String
end

function evaluate(
        p::PartitionSpec,
        repo::Repository,
        (source, target)::Pair{<:AbstractString, <:AbstractString},
        select
    )

    N = length(p.tiles)
    training = findall(==(1), p.tiles)
    validation = findall(==(2), p.tiles)

    by = p.by
    order_by = union(p.sorters, p.by)

    tile = string(uuid4())

    pfun = Fun.case(
        Fun.in(Get(tile), training...), 1,
        Fun.in(Get(tile), validation...), 2,
        0
    )

    selection = @. select => Get(select)

    query = From(source) |>
        Partition(by = Get.(by), order_by = Get.(order_by)) |>
        Select(selection..., tile => Agg.ntile(N)) |>
        Select(selection..., p.output => pfun)

    catalog = get_catalog(repo)
    sql = string(
        "CREATE OR REPLACE TABLE ",
        render(catalog, convert(SQLClause, target)),
        " AS\n",
        render(catalog, query)
    )

    DBInterface.execute(
        Returns(nothing),
        repo,
        sql,
    )
end

inputs(::PartitionSpec) = String[]

outputs(p::PartitionSpec) = [p.output]
