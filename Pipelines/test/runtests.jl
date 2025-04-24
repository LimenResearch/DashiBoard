using Pipelines, DataIngestion, DuckDBUtils, StreamlinerCore
using DBInterface, DataFrames, OrderedCollections, JSON3
using Clustering, GLM, DataInterpolations, Distributions, Dates, Statistics
using FunSQL: Get
using Base.ScopedValues: @with
using Test

include("evaluation.jl")
include("funnels.jl")
include("cards.jl")
include("frontend.jl")
include("utils.jl")
