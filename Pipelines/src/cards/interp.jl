abstract type InterpolationMethod end

function StructUtils.lift(::DashiStyle, ::Type{ExtrapolationType.T}, s::AbstractString)
    return StructUtils.lift(ExtrapolationType.T, uppercasefirst(s)), nothing
end

function StructUtils.lower(::DashiStyle, x::ExtrapolationType.T)
    return lowercase(string(Symbol(x)))
end

## Constant interpolation

@kwarg struct ConstantInterpolationMethod <: InterpolationMethod
    dir::Symbol & (dashi = StringDict("enum" => ["left", "right"]),)
    extrapolation_left::ExtrapolationType.T = ExtrapolationType.None
    extrapolation_right::ExtrapolationType.T = ExtrapolationType.None
end

function (m::ConstantInterpolationMethod)(y, x)
    return ConstantInterpolation(y, x; m.dir, m.extrapolation_left, m.extrapolation_right)
end

## Non-constant interpolation

@kwarg struct LinearInterpolationMethod <: InterpolationMethod
    extrapolation_left::ExtrapolationType.T = ExtrapolationType.None
    extrapolation_right::ExtrapolationType.T = ExtrapolationType.None
end

@kwarg struct QuadraticInterpolationMethod <: InterpolationMethod
    extrapolation_left::ExtrapolationType.T = ExtrapolationType.None
    extrapolation_right::ExtrapolationType.T = ExtrapolationType.None
end

@kwarg struct QuadraticSplineMethod <: InterpolationMethod
    extrapolation_left::ExtrapolationType.T = ExtrapolationType.None
    extrapolation_right::ExtrapolationType.T = ExtrapolationType.None
end

@kwarg struct CubicSplineMethod <: InterpolationMethod
    extrapolation_left::ExtrapolationType.T = ExtrapolationType.None
    extrapolation_right::ExtrapolationType.T = ExtrapolationType.None
end

@kwarg struct AkimaInterpolationMethod <: InterpolationMethod
    extrapolation_left::ExtrapolationType.T = ExtrapolationType.None
    extrapolation_right::ExtrapolationType.T = ExtrapolationType.None
end

@kwarg struct PCHIPInterpolationMethod <: InterpolationMethod
    extrapolation_left::ExtrapolationType.T = ExtrapolationType.None
    extrapolation_right::ExtrapolationType.T = ExtrapolationType.None
end

for sym in [
        :LinearInterpolation, :QuadraticInterpolation, :QuadraticSpline,
        :CubicSpline, :AkimaInterpolation, :PCHIPInterpolation,
    ]
    method = Symbol(sym, :Method)
    @eval begin
        (m::$(method))(y, x) = $sym(y, x; m.extrapolation_left, m.extrapolation_right)
    end
end

# Global dictionary of interpolation methods

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
    struct InterpCard{M <: InterpolationMethod} <: Card
        method::M
        input::String
        targets::Vector{String}
        partition::Union{String, Nothing} = nothing
        suffix::String = "hat"
    end

Interpolate `targets` based on `input`.
"""
@kwarg struct InterpCard{M <: InterpolationMethod} <: StandardCard
    method::M & (name = "method_options",)
    input::String
    targets::Vector{String}
    partition::Union{String, Nothing} = nothing
    suffix::String = "hat"
end

get_metadata(ic::InterpCard) = _get_metadata(ic, INTERPOLATION_METHODS)

InterpCard(c::AbstractDict) = _construct(InterpCard, c, INTERPOLATION_METHODS)

## StandardCard interface

function SourceVariables(ic::InterpCard)
    return SourceVariables(; order_by = [ic.input], inputs = [ic.input], ic.targets, ic.partition)
end

OutputVariables(ic::InterpCard) = OutputVariables(join_names.(ic.targets, ic.suffix))

function _train(ic::InterpCard, t, ::AbstractPrimaryKey)
    (; method, targets, input, partition) = ic
    return map(targets) do target
        y, x = t[target], t[input]
        return method(y, x)
    end
end

function (ic::InterpCard)(itps, t, id_var::AbstractPrimaryKey)
    (; targets, input, suffix) = ic
    x = t[input]

    pred_table = SimpleTable(id_var => t[id_var])
    for (itp, target) in zip(itps, targets)
        pred_name = join_names(target, suffix)
        ŷ = similar(x, float(eltype(x)))
        pred_table[pred_name] = itp(ŷ, x)
    end

    return pred_table
end

## UI representation

function CardWidget(
        ::Type{InterpCard}, key::AbstractString;
        global_options::AbstractDict, user_options::AbstractDict
    )

    config = CardWidgetConfigs(parse_toml_config("config", key))
    c = combine_options(config.widget_configs; global_options, user_options)

    methods = collect(keys(INTERPOLATION_METHODS))
    extrapolation_options = enum_instances(ExtrapolationType.T)
    direction_options = ["left", "right"]

    fields = vcat(
        [
            Widget("input", c),
            Widget("targets", c),
            Widget("method", c; options = methods),
        ],
        method_dependent_widgets(c, "method", config.methods),
        [
            Widget("partition", c, required = false),
            Widget("suffix", c, value = "hat"),
        ]
    )

    return CardWidget(key, fields, OutputSpec("targets", "suffix"))
end
