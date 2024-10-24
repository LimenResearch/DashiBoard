@kwdef struct PartitionSpec
    sorters::Vector{String}
    by::Vector{String}
    tiles::Vector{Int}
end

# TODO: decide where input of `Partition` comes from
function register_partition(ex::Experiment, p::PartitionSpec)
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

    query = From(TABLE_NAMES.source) |>
        Partition(by = Get.(by), order_by = Get.(order_by)) |>
        Define("_tile" => Agg.ntile(N)) |>
        Define("_partition" => pfun)

    repo = ex.repository
    catalog = get_catalog(repo)
    sql = string(
        "CREATE OR REPLACE VIEW ",
        TABLE_NAMES.partition,
        " AS \n",
        render(catalog, query)
    )

    DBInterface.execute(
        Returns(nothing),
        repo,
        sql,
    )
end
