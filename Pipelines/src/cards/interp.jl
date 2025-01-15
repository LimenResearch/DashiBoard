struct Interpolator
    method::Base.Callable
    has_dir::Bool
end

function Interpolator(method::Base.Callable; has_dir::Bool = false)
    return Interpolator(method, has_dir)
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
    "constant" => Interpolator(ConstantInterpolation, has_dir = true),
    "linear" => Interpolator(LinearInterpolation),
    "quadratic" => Interpolator(QuadraticInterpolation),
    "quadraticspline" => Interpolator(QuadraticSpline),
    "cubicspline" => Interpolator(CubicSpline),
    "akima" => Interpolator(AkimaInterpolation),
    "pchip" => Interpolator(PCHIPInterpolation),
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
    extrapolation_left::String = "none"
    extrapolation_right::String = "none"
    dir::String = "left"
    partition::Union{String, Nothing} = nothing
    suffix::String = "hat"
end

inputs(ic::InterpCard) = Set{String}([ic.predictor])

outputs(ic::InterpCard) = Set{String}(ic.targets)

function train(
        repo::Repository,
        ic::InterpCard,
        source::AbstractString;
        schema = nothing
    )

    select = filter_partition(ic.partition)
    q = From(source) |>
        select |>
        Select(Get(ic.predictor), Get.(ic.targets)...) |>
        Order(Get(ic.predictor))
    t = DBInterface.execute(fromtable, repo, q; schema)

    extrapolation_left = EXTRAPOLATION_OPTIONS[ic.extrapolation_left]
    extrapolation_right = EXTRAPOLATION_OPTIONS[ic.extrapolation_right]
    dir = DIRECTION_OPTIONS[ic.dir]

    return map(ic.targets) do target
        ip = INTERPOLATORS[ic.method]
        predictor = ic.predictor
        y, x = t[target], t[predictor]
        return if ip.has_dir
            ip.method(y, x; extrapolation_left, extrapolation_right, dir)
        else
            ip.method(y, x; extrapolation_left, extrapolation_right)
        end
    end
end

function evaluate(
        repo::Repository,
        ic::InterpCard,
        ips::AbstractVector,
        (source, dest)::Pair;
        schema = nothing
    )

    t = DBInterface.execute(fromtable, repo, From(source) |> Order(Get(ic.predictor)); schema)
    predictor = ic.predictor

    for (ip, target) in zip(ips, ic.targets)
        pred_name = string(target, '_', ic.suffix)
        t[pred_name] = ip(t[predictor])
    end

    load_table(repo, t, dest; schema)
end
