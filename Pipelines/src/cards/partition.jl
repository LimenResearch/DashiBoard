abstract type AbstractPartition <: AbstractCard end

inputs(p::AbstractPartition) = union(p.order_by, p.by)

outputs(p::AbstractPartition) = [p.output]

function check_order(p::AbstractPartition)
    if isempty(p.order_by)
        throw(
            ArgumentError(
                """
                At least one sorter is required.
                """
            )
        )
    end
end

function evaluate(
        p::AbstractPartition,
        repo::Repository,
        (source, target)::Pair{<:AbstractString, <:AbstractString}
    )

    catalog = get_catalog(repo)
    select = colnames(catalog, source)
    selection = @. select => Get(select)

    query = From(source) |>
        Partition(by = Get.(p.by), order_by = Get.(p.order_by)) |>
        node -> partition_query(p, selection, node)

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

@kwdef struct TiledPartition <: AbstractPartition
    order_by::Vector{String}
    by::Vector{String}
    tiles::Vector{Int}
    output::String
end

function TiledPartition(d::AbstractDict)
    order_by, by, tiles, output = d["order_by"], d["by"], d["tiles"], d["output"]
    return TiledPartition(order_by, by, tiles, output)
end

function partition_query(p::TiledPartition, selection::AbstractVector, node::SQLNode)
    check_order(p)

    N = length(p.tiles)
    training = findall(==(1), p.tiles)
    validation = findall(==(2), p.tiles)

    tile = string(uuid4())

    pfun = Fun.case(
        Fun.in(Get(tile), training...), 1,
        Fun.in(Get(tile), validation...), 2,
        0
    )

    return node |>
        Select(selection..., tile => Agg.ntile(N)) |>
        Select(selection..., p.output => pfun)
end

@kwdef struct PercentilePartition <: AbstractPartition
    order_by::Vector{String}
    by::Vector{String}
    p::Float64
    output::String
end

function PercentilePartition(d::AbstractDict)
    order_by, by, p, output = d["order_by"], d["by"], d["p"], d["output"]
    return PercentilePartition(order_by, by, p, output)
end

function partition_query(p::PercentilePartition, selection::AbstractVector, node::SQLNode)
    check_order(p)
    pfun = Fun.case(Fun."<="(Agg.percent_rank(), p.p), 1, 2)
    return node |> Select(selection..., p.output => pfun)
end
