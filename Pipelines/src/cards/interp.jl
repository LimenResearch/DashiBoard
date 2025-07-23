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
        type::String
        label::String
        method::String
        interpolator::Interpolator
        input::String
        targets::Vector{String}
        extrapolation_left::ExtrapolationType.T
        extrapolation_right::ExtrapolationType.T
        dir::Union{Symbol, Nothing} = nothing
        partition::Union{String, Nothing} = nothing
        suffix::String = "hat"
    end

Interpolate `targets` based on `input`.
"""
struct InterpCard <: StandardCard
    type::String
    label::String
    method::String
    interpolator::Interpolator
    input::String
    targets::Vector{String}
    extrapolation_left::ExtrapolationType.T
    extrapolation_right::ExtrapolationType.T
    dir::Union{Symbol, Nothing}
    partition::Union{String, Nothing}
    suffix::String
end

const INTERP_CARD_CONFIG = CardConfig{InterpCard}(parse_toml_config("config", "interp"))

function get_metadata(ic::InterpCard)
    return StringDict(
        "type" => ic.type,
        "label" => ic.label,
        "method" => ic.method,
        "input" => ic.input,
        "targets" => ic.targets,
        "extrapolation_left" => lowercase(string(Symbol(ic.extrapolation_left))),
        "extrapolation_right" => lowercase(string(Symbol(ic.extrapolation_right))),
        "dir" => isnothing(ic.dir) ? nothing : string(ic.dir),
        "partition" => ic.partition,
        "suffix" => ic.suffix,
    )
end

function InterpCard(c::AbstractDict)
    type::String = c["type"]
    config = CARD_CONFIGS[type]
    label::String = card_label(c, config)
    method::String = c["method"]
    interpolator::Interpolator = INTERPOLATORS[method]
    input::String = c["input"]
    targets::Vector{String} = c["targets"]
    extrapolation_left::ExtrapolationType.T = EXTRAPOLATION_OPTIONS[get(c, "extrapolation_left", "none")]
    extrapolation_right::ExtrapolationType.T = EXTRAPOLATION_OPTIONS[get(c, "extrapolation_right", "none")]
    dir_key::Union{String, Nothing} = get(c, "dir", nothing)
    dir::Union{Symbol, Nothing} = isnothing(dir_key) ? nothing : DIRECTION_OPTIONS[dir_key]
    partition::Union{String, Nothing} = get(c, "partition", nothing)
    suffix::String = get(c, "suffix", "hat")
    return InterpCard(
        type,
        label,
        method,
        interpolator,
        input,
        targets,
        extrapolation_left,
        extrapolation_right,
        dir,
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
    (; interpolator, extrapolation_left, extrapolation_right, dir, targets, input, partition) = ic
    return map(targets) do target
        itp = interpolator
        y, x = t[target], t[input]
        return if itp.has_dir
            itp.method(y, x; extrapolation_left, extrapolation_right, dir)
        else
            itp.method(y, x; extrapolation_left, extrapolation_right)
        end
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

function CardWidget(config::CardConfig{InterpCard}, ::AbstractDict)
    methods = collect(keys(INTERPOLATORS))
    extrapolation_options = collect(keys(EXTRAPOLATION_OPTIONS))
    direction_options = collect(keys(DIRECTION_OPTIONS))

    fields = [
        Widget("input"),
        Widget("targets"),
        Widget("method"; options = methods, value = "linear"),
        Widget(
            config,
            "extrapolation_left", value = "linear",
            options = extrapolation_options
        ),
        Widget(
            config,
            "extrapolation_right", value = "linear",
            options = extrapolation_options
        ),
        Widget(
            config,
            "dir", value = "left",
            options = direction_options,
            visible = Dict("method" => ["constant"])
        ),
        Widget("partition", required = false),
        Widget("suffix", value = "hat"),
    ]

    return CardWidget(config.key, config.label, fields, OutputSpec("targets", "suffix"))
end
