module DataIngestion

export Experiment, Partition, register_partition
export Query

using DuckDB: DBInterface, DuckDB
using ConcurrentUtilities: Pool, acquire, release
using IntervalSets: Interval, leftendpoint, rightendpoint, isleftclosed, isrightclosed
using IterTools: flagfirst

include("repository.jl")
include("experiment.jl")
include("partition.jl")
include("filters.jl")
include("query.jl")

end
