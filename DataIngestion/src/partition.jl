@kwdef struct Partition
    sorters::Vector{String}
    by::Vector{String}
    tiles::Vector{Int}
end

function register_partition(repo::Repository, p::Partition, (source, target)::Pair)
    N = length(p.tiles)
    training = join(findall(==(1), p.tiles), ", ")
    validation = join(findall(==(2), p.tiles), ", ")

    _by = join(p.by, ", ")
    _sorters = join(union(p.sorters, p.by), ", ")

    PARTITION_CLAUSE = isempty(_by) ? "" : "PARTITION BY $_by"
    ORDER_CLAUSE = isempty(_sorters) ? "" : "ORDER BY $_sorters"

    DBInterface.execute(
        Returns(nothing),
        repo,
        """
        CREATE OR REPLACE VIEW $target AS
        SELECT *,
            ntile($N) OVER($PARTITION_CLAUSE $ORDER_CLAUSE) AS _tile,
            CASE
                WHEN _tile IN ($training) THEN 1
                WHEN _tile IN ($validation) THEN 2
                ELSE 0
            END AS _partition
        FROM $source;
        """
    )
    @info "Created partitioned view '$target' on DB"
end

function register_partition(ex::Experiment, p::Partition)
    source = ex.name
    target = string(source, "_partitioned")
    register_partition(ex.repository, p, source => target)
end
