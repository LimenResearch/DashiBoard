using Pipelines: Node, invert, get_card, get_state
using Pipelines, DataIngestion, DuckDBUtils, StreamlinerCore
using DBInterface, DataFrames, Graphs, JSON, Downloads
using Clustering, GLM, MixedModels, DataInterpolations, Distributions, Dates, Statistics
using MultivariateStats: PCA, PPCA, FactorAnalysis, MDS
using FunSQL: Get, Select, Partition
using Base.ScopedValues: @with
using Test

include("evaluation.jl")
include("funnels.jl")
include("options.jl")
include("cards.jl")
include("metadata.jl")
include("frontend.jl")
include("utils.jl")
