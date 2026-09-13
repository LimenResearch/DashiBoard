abstract type InterpolationMethod <: AbstractMethod end

function StructUtils.lift(::DashiStyle, ::Type{ExtrapolationType.T}, s::AbstractString)
    return StructUtils.lift(ExtrapolationType.T, uppercasefirst(s)), nothing
end

function StructUtils.lower(::DashiStyle, x::ExtrapolationType.T)
    return lowercase(string(Symbol(x)))
end

## Constant interpolation

@kwarg struct ConstantInterpolationMethod <: InterpolationMethod
    dir::Symbol & (dashi = StringIR(enum = ["left", "right"]),)
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

const INTERPOLATION_METHODS = OrderedDict{String, Type}(
    "constant" => ConstantInterpolationMethod,
    "linear" => LinearInterpolationMethod,
    "quadratic" => QuadraticInterpolationMethod,
    "quadraticspline" => QuadraticSplineMethod,
    "cubicspline" => CubicSplineMethod,
    "akima" => AkimaInterpolationMethod,
    "pchip" => PCHIPInterpolationMethod,
)

@options InterpolationMethod INTERPOLATION_METHODS

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
    method::M
    input::String & (dashi = VARIABLE_DEF,)
    targets::Vector{String} & (dashi = NONEMPTY_VARIABLES_DEF,)
    partition::Maybe{String} = nothing & (dashi = VARIABLE_DEF,)
    suffix::String = "hat" & (dashi = StringIR(minLength = 1),)
end

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
