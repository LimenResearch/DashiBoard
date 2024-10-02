module Pipelines

using Tables: Tables
using IntervalSets: Interval, leftendpoint, rightendpoint, isleftclosed, isrightclosed

include("tables.jl")
include("filters.jl")
include("query.jl")

end
