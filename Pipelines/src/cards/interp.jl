struct Interpolator
    method::Base.Callable
    options::Vector{Symbol}
end

function Interpolator(method::Base.Callable, options::Symbol...)
    return Interpolator(method, collect(Symbol, options))
end

const EXTRAPOLATION_OPTIONS = Dict(
    "none" => ExtrapolationType.None,
    "constant" => ExtrapolationType.Constant,
    "linear" => ExtrapolationType.Linear,
    "extension" => ExtrapolationType.Extension,
    "periodic" => ExtrapolationType.Periodic,
    "reflective" => ExtrapolationType.Reflective,
)

const DIRECTION_OPTIONS = Dict("left" => :left, "right" => :right)

const INTERPOLATORS = Dict(
    "constant" => Interpolator(ConstantInterpolation, :extrapolation, :dir),
    "linear" => Interpolator(LinearInterpolation, :extrapolation),
    "quadratic" => Interpolator(QuadraticInterpolation, :extrapolation),
    "quadraticspline" => Interpolator(QuadraticSpline, :extrapolation),
    "cubicspline" => Interpolator(CubicSpline, :extrapolation),
    "akima" => Interpolator(AkimaInterpolation, :extrapolation),
    "pchip" => Interpolator(PCHIPInterpolation, :extrapolation),
)

"""
    struct InterpCard <: AbstractCard
        predictor::String
        targets::Vector{String}
        weights::Union{String, Nothing} = nothing
        distribution::String = "normal"
        link::Union{String, Nothing} = nothing
        link_params::Vector{Any} = Any[]
        suffix::String = "hat"
    end

Interpolate `targets` based on `predictor`.
"""
@kwdef struct InterpCard <: AbstractCard
    predictor::String
    targets::Vector{String}
    method::String = "linear"
    extrapolation::Union{String, Nothing} = nothing
    dir::Union{String, Nothing} = nothing
    partition::Union{String, Nothing} = nothing
    suffix::String = "hat"
end
