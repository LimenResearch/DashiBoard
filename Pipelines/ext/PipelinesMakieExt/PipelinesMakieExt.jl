module PipelinesMakieExt

using CairoMakie: Axis, Figure, axislegend, lines!
using AlgebraOfGraphics: AlgebraOfGraphics

using Pipelines: Pipelines, CardState, StreamlinerCard
using DuckDBUtils: Repository
using JLD2: jldopen

include("streamliner.jl")

end
