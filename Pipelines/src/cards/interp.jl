abstract type InterpolationMethod end

function get_options(m::InterpolationMethod)
    options = StringDict()
    hasproperty(m, :dir) && (options["dir"] = string(m.dir))
    options["extrapolation_left"] = lowercase(string(Symbol(m.extrapolation_left)))
    options["extrapolation_right"] = lowercase(string(Symbol(m.extrapolation_right)))
    return options
end

function get_extrapolation_options(c::AbstractDict)
    left::ExtrapolationType.T = EXTRAPOLATION_OPTIONS[get(c, "extrapolation_left", "none")]
    right::ExtrapolationType.T = EXTRAPOLATION_OPTIONS[get(c, "extrapolation_right", "none")]
    return left, right
end

## Constant interpolation

struct ConstantInterpolationMethod <: InterpolationMethod
    dir::Symbol
    extrapolation_left::ExtrapolationType.T
    extrapolation_right::ExtrapolationType.T
end

function ConstantInterpolationMethod(c::AbstractDict)
    dir::String = c["dir"]
    return ConstantInterpolationMethod(
        DIRECTION_OPTIONS[dir],
        get_extrapolation_options(c)...
    )
end

function (m::ConstantInterpolationMethod)(y, x)
    return ConstantInterpolation(y, x; m.dir, m.extrapolation_left, m.extrapolation_right)
end

## Non-constant interpolation

struct LinearInterpolationMethod <: InterpolationMethod
    extrapolation_left::ExtrapolationType.T
    extrapolation_right::ExtrapolationType.T
end

struct QuadraticInterpolationMethod <: InterpolationMethod
    extrapolation_left::ExtrapolationType.T
    extrapolation_right::ExtrapolationType.T
end

struct QuadraticSplineMethod <: InterpolationMethod
    extrapolation_left::ExtrapolationType.T
    extrapolation_right::ExtrapolationType.T
end

struct CubicSplineMethod <: InterpolationMethod
    extrapolation_left::ExtrapolationType.T
    extrapolation_right::ExtrapolationType.T
end

struct AkimaInterpolationMethod <: InterpolationMethod
    extrapolation_left::ExtrapolationType.T
    extrapolation_right::ExtrapolationType.T
end

struct PCHIPInterpolationMethod <: InterpolationMethod
    extrapolation_left::ExtrapolationType.T
    extrapolation_right::ExtrapolationType.T
end

for sym in [
        :LinearInterpolation, :QuadraticInterpolation, :QuadraticSpline,
        :CubicSpline, :AkimaInterpolation, :PCHIPInterpolation,
    ]
    method = Symbol(sym, :Method)
    @eval begin
        $(method)(c::AbstractDict) = $(method)(get_extrapolation_options(c)...)
        (m::$(method))(y, x) = $sym(y, x; m.extrapolation_left, m.extrapolation_right)
    end
end

## Global dictionaries of options

const EXTRAPOLATION_OPTIONS = OrderedDict(
    "none" => ExtrapolationType.None,
    "constant" => ExtrapolationType.Constant,
    "linear" => ExtrapolationType.Linear,
    "extension" => ExtrapolationType.Extension,
    "periodic" => ExtrapolationType.Periodic,
    "reflective" => ExtrapolationType.Reflective,
)

const DIRECTION_OPTIONS = OrderedDict("left" => :left, "right" => :right)

const INTERPOLATION_METHODS = OrderedDict{String, DataType}(
    "constant" => ConstantInterpolationMethod,
    "linear" => LinearInterpolationMethod,
    "quadratic" => QuadraticInterpolationMethod,
    "quadraticspline" => QuadraticSplineMethod,
    "cubicspline" => CubicSplineMethod,
    "akima" => AkimaInterpolationMethod,
    "pchip" => PCHIPInterpolationMethod,
)

"""
    struct InterpCard <: Card
        type::String
        label::String
        method::String
        interpolator::InterpolationMethod
        input::String
        targets::Vector{String}
        partition::Union{String, Nothing} = nothing
        suffix::String = "hat"
    end

Interpolate `targets` based on `input`.
"""
struct InterpCard <: StandardCard
    type::String
    label::String
    method::String
    interpolator::InterpolationMethod
    input::String
    targets::Vector{String}
    partition::Union{String, Nothing}
    suffix::String
end

const INTERP_CARD_CONFIG = CardConfig{InterpCard}(parse_toml_config("config", "interp"))

function get_metadata(ic::InterpCard)
    return StringDict(
        "type" => ic.type,
        "label" => ic.label,
        "method" => ic.method,
        "method_options" => get_options(ic.interpolator),
        "input" => ic.input,
        "targets" => ic.targets,
        "partition" => ic.partition,
        "suffix" => ic.suffix,
    )
end

function InterpCard(c::AbstractDict)
    type::String = c["type"]
    config = CARD_CONFIGS[type]
    label::String = card_label(c, config)
    method::String = c["method"]
    method_options::StringDict = extract_options(c, method, "method")
    interpolator::InterpolationMethod = INTERPOLATION_METHODS[method](method_options)
    input::String = c["input"]
    targets::Vector{String} = c["targets"]
    partition::Union{String, Nothing} = get(c, "partition", nothing)
    suffix::String = get(c, "suffix", "hat")
    return InterpCard(
        type,
        label,
        method,
        interpolator,
        input,
        targets,
        partition,
        suffix
    )
end

## StandardCard interface

sorting_vars(ic::InterpCard) = [ic.input]
grouping_vars(::InterpCard) = String[]
input_vars(ic::InterpCard) = [ic.input]
target_vars(ic::InterpCard) = ic.targets
weight_var(::InterpCard) = nothing
partition_var(ic::InterpCard) = ic.partition
output_vars(ic::InterpCard) = join_names.(ic.targets, ic.suffix)

function _train(ic::InterpCard, t, _)
    (; interpolator, targets, input, partition) = ic
    return map(targets) do target
        y, x = t[target], t[input]
        return interpolator(y, x)
    end
end

function (ic::InterpCard)(itps, t, id)
    (; targets, input, suffix) = ic
    x = t[input]

    pred_table = SimpleTable()
    for (itp, target) in zip(itps, targets)
        pred_name = join_names(target, suffix)
        ŷ = similar(x, float(eltype(x)))
        pred_table[pred_name] = itp(ŷ, x)
    end

    return pred_table, id
end

## UI representation

function CardWidget(config::CardConfig{InterpCard}, c::AbstractDict)
    methods = collect(keys(INTERPOLATION_METHODS))
    extrapolation_options = collect(keys(EXTRAPOLATION_OPTIONS))
    direction_options = collect(keys(DIRECTION_OPTIONS))

    fields = vcat(
        [
            Widget("input", c),
            Widget("targets", c),
            Widget("method", c; options = methods),
        ],
        method_dependent_widgets(c, config.methods, "method"),
        [
            Widget("partition", c, required = false),
            Widget("suffix", c, value = "hat"),
        ]
    )

    return CardWidget(config.key, config.label, fields, OutputSpec("targets", "suffix"))
end
