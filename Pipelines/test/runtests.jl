using Pipelines, DataIngestion, DuckDBUtils, StreamlinerCore
using DBInterface, DataFrames, GLM, DataInterpolations, Statistics, JSON3
using OrderedCollections, EasyConfig, Dates, Distributions
using FunSQL: Get
using Base.ScopedValues: @with
using Test

include("evaluation.jl")
include("funnels.jl")
include("cards.jl")
include("frontend.jl")
include("utils.jl")
