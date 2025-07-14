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
struct InterpCard <: Card
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

invertible(::InterpCard) = false

inputs(ic::InterpCard) = stringlist(ic.predictor, ic.targets, ic.partition)
outputs(ic::InterpCard) = join_names.(ic.targets, ic.suffix)

function train(
        repository::Repository,
        ic::InterpCard,
        source::AbstractString;
        schema = nothing
    )

    (; interpolator, extrapolation_left, extrapolation_right, dir, targets, predictor, partition) = ic

    q = From(source) |>
        filter_partition(partition) |>
        Select(Get(predictor), Get.(targets)...) |>
        Order(Get(predictor))
    t = DBInterface.execute(fromtable, repository, q; schema)

    ips = map(targets) do target
        ip = interpolator
        y, x = t[target], t[predictor]
        return if ip.has_dir
            ip.method(y, x; extrapolation_left, extrapolation_right, dir)
        else
            ip.method(y, x; extrapolation_left, extrapolation_right)
        end
    end
    return CardState(content = jldserialize(ips))
end

function evaluate(
        repository::Repository,
        ic::InterpCard,
        state::CardState,
        (source, destination)::Pair;
        schema = nothing
    )

    ips = jlddeserialize(state.content)
    (; targets, predictor, suffix) = ic
    query = From(source) |> Order(Get(predictor))
    t = DBInterface.execute(fromtable, repository, query; schema)
    x = t[predictor]

    for (ip, target) in zip(ips, targets)
        pred_name = join_names(target, suffix)
        ŷ = similar(x, float(eltype(x)))
        t[pred_name] = ip(ŷ, x)
    end

    return load_table(repository, t, destination; schema)
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
