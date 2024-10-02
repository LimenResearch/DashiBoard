module DataIngestion

export Experiment, Partition, register_partition

using DuckDB: DBInterface, DuckDB
using Glob: glob
using ConcurrentUtilities: Pool, acquire, release

include("repository.jl")
include("experiment.jl")
include("partition.jl")

end
