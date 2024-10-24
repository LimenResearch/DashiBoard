@kwdef struct PartitionSpec
    sorters::Vector{String}
    by::Vector{String}
    tiles::Vector{Int}
end

function register_partition(repo::Repository, p::PartitionSpec, (source, target)::Pair)
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

    query = From(source) |>
        Partition(by = Get.(by), order_by = Get.(order_by)) |>
        Define("_tile" => Agg.ntile(N)) |>
        Define("_partition" => pfun)

    catalog = get_catalog(repo)

    sql = string(
        "CREATE OR REPLACE TABLE ",
        target,
        " AS \n",
        render(catalog, query)
    )

    DBInterface.execute(
        Returns(nothing),
        repo,
        sql,
    )
end

function register_partition(ex::Experiment, p::PartitionSpec)
    source = ex.name
    target = string(source, "_partitioned")
    register_partition(ex.repository, p, source => target)
end
