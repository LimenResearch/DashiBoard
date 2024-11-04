@kwdef struct PartitionSpec
    sorters::Vector{String}
    by::Vector{String}
    tiles::Vector{Int}
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

    pfun = Fun.case(
        Fun.in(Get._tile, training...), 1,
        Fun.in(Get._tile, validation...), 2,
        0
    )

    selection = @. select => Get(select)

    query = From(source) |>
        Partition(by = Get.(by), order_by = Get.(order_by)) |>
        Select(selection..., "_tile" => Agg.ntile(N)) |>
        Select(selection..., "_partition" => pfun)

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

outputs(::PartitionSpec) = ["_tile", "_partition"]
