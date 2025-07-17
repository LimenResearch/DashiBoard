using Pipelines: Node, invert, get_card, get_state
using Pipelines, DataIngestion, DuckDBUtils, StreamlinerCore
using DBInterface, DataFrames, Graphs, JSON, Downloads
using Clustering, GLM, DataInterpolations, Distributions, Dates, Statistics
using MultivariateStats: PCA, PPCA, FactorAnalysis, MDS
using FunSQL: Get
using Base.ScopedValues: @with
using Test

include("evaluation.jl")
include("funnels.jl")
include("cards.jl")
include("frontend.jl")
include("utils.jl")
