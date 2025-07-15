struct Interpolator
    method::Base.Callable
    has_dir::Bool
end

function Interpolator(method::Base.Callable; has_dir::Bool = false)
    return Interpolator(method, has_dir)
end

const EXTRAPOLATION_OPTIONS = OrderedDict(
    "none" => ExtrapolationType.None,
    "constant" => ExtrapolationType.Constant,
    "linear" => ExtrapolationType.Linear,
    "extension" => ExtrapolationType.Extension,
    "periodic" => ExtrapolationType.Periodic,
    "reflective" => ExtrapolationType.Reflective,
)

const DIRECTION_OPTIONS = OrderedDict("left" => :left, "right" => :right)

const INTERPOLATORS = OrderedDict(
    "constant" => Interpolator(ConstantInterpolation, has_dir = true),
    "linear" => Interpolator(LinearInterpolation),
    "quadratic" => Interpolator(QuadraticInterpolation),
    "quadraticspline" => Interpolator(QuadraticSpline),
    "cubicspline" => Interpolator(CubicSpline),
    "akima" => Interpolator(AkimaInterpolation),
    "pchip" => Interpolator(PCHIPInterpolation),
)

"""
    struct InterpCard <: Card
        interpolator::Interpolator
        predictor::String
        targets::Vector{String}
        extrapolation_left::ExtrapolationType.T
        extrapolation_right::ExtrapolationType.T
        dir::Union{Symbol, Nothing} = nothing
        partition::Union{String, Nothing} = nothing
        suffix::String = "hat"
    end

Interpolate `targets` based on `predictor`.
"""
struct InterpCard <: StandardCard
    interpolator::Interpolator
    predictor::String
    targets::Vector{String}
    extrapolation_left::ExtrapolationType.T
    extrapolation_right::ExtrapolationType.T
    dir::Union{Symbol, Nothing}
    partition::Union{String, Nothing}
    suffix::String
end

register_card("interp", InterpCard)

function InterpCard(c::AbstractDict)
    method::String = c["method"]
    interpolator::Interpolator = INTERPOLATORS[method]
    predictor::String = c["predictor"]
    targets::Vector{String} = c["targets"]
    extrapolation_left::ExtrapolationType.T = EXTRAPOLATION_OPTIONS[get(c, "extrapolation_left", "none")]
    extrapolation_right::ExtrapolationType.T = EXTRAPOLATION_OPTIONS[get(c, "extrapolation_right", "none")]
    dir_key::Union{String, Nothing} = get(c, "dir", nothing)
    dir::Union{Symbol, Nothing} = isnothing(dir_key) ? nothing : DIRECTION_OPTIONS[dir_key]
    partition::Union{String, Nothing} = get(c, "partition", nothing)
    suffix::String = get(c, "suffix", "hat")
    return InterpCard(
        interpolator,
        predictor,
        targets,
        extrapolation_left,
        extrapolation_right,
        dir,
        partition,
        suffix
    )
end

## StandardCard interface

weight_var(::InterpCard) = nothing
grouping_vars(::InterpCard) = String[]
sorting_vars(ic::InterpCard) = [ic.predictor]

partition_var(ic::InterpCard) = ic.partition
input_vars(ic::InterpCard) = [ic.predictor]
target_vars(ic::InterpCard) = ic.targets
output_vars(ic::InterpCard) = join_names.(ic.targets, ic.suffix)

function _train(ic::InterpCard, t, _)
    (; interpolator, extrapolation_left, extrapolation_right, dir, targets, predictor, partition) = ic
    return map(targets) do target
        itp = interpolator
        y, x = t[target], t[predictor]
        return if itp.has_dir
            itp.method(y, x; extrapolation_left, extrapolation_right, dir)
        else
            itp.method(y, x; extrapolation_left, extrapolation_right)
        end
    end
end

function (ic::InterpCard)(itps, t, id)
    (; targets, predictor, suffix) = ic
    x = t[predictor]
    pred_table = SimpleTable()

    for (itp, target) in zip(itps, targets)
        pred_name = join_names(target, suffix)
        ŷ = similar(x, float(eltype(x)))
        pred_table[pred_name] = itp(ŷ, x)
    end

    return pred_table, id
end

## UI representation

function CardWidget(::Type{InterpCard})
    options = collect(keys(INTERPOLATORS))
    extrapolation_options = collect(keys(EXTRAPOLATION_OPTIONS))
    direction_options = collect(keys(DIRECTION_OPTIONS))

    fields = [
        Widget("predictor"),
        Widget("targets"),
        Widget("method"; options, value = "linear"),
        Widget(
            "extrapolation_left",
            value = "linear",
            options = extrapolation_options
        ),
        Widget(
            "extrapolation_right",
            value = "linear",
            options = extrapolation_options
        ),
        Widget(
            "dir",
            options = direction_options,
            value = "left",
            visible = Dict("method" => ["constant"])
        ),
        Widget("partition", required = false),
        Widget("suffix", value = "hat"),
    ]

    return CardWidget(;
        type = "interp",
        label = "Interpolation",
        output = OutputSpec("targets", "suffix"),
        fields
    )
end
