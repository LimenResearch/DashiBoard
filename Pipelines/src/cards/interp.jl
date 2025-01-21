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
    struct InterpCard <: AbstractCard
        predictor::String
        targets::Vector{String}
        method::String = "linear"
        extrapolation_left::String = "none"
        extrapolation_right::String = "none"
        dir::String = "left"
        partition::Union{String, Nothing} = nothing
        suffix::String = "hat"
    end

Interpolate `targets` based on `predictor`.
"""
@kwdef struct InterpCard <: AbstractCard
    predictor::String
    targets::Vector{String}
    method::String = "linear"
    extrapolation_left::Union{String, Nothing} = nothing
    extrapolation_right::Union{String, Nothing} = nothing
    dir::Union{String, Nothing} = nothing
    partition::Union{String, Nothing} = nothing
    suffix::String = "hat"
end

function inputs(ic::InterpCard)
    i = Set{String}()
    push!(i, ic.predictor)
    isnothing(ic.partition) || push!(i, ic.partition)
    return i
end

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

    extrapolation_left = EXTRAPOLATION_OPTIONS[something(ic.extrapolation_left, "none")]
    extrapolation_right = EXTRAPOLATION_OPTIONS[something(ic.extrapolation_right, "none")]
    dir = DIRECTION_OPTIONS[something(ic.dir, "left")]

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
    x = t[predictor]

    for (ip, target) in zip(ips, ic.targets)
        pred_name = string(target, '_', ic.suffix)
        ŷ = similar(x, float(eltype(x)))
        t[pred_name] = ip(ŷ, x)
    end

    load_table(repo, t, dest; schema)
end

function CardWidget(::Type{InterpCard})
    options = collect(keys(INTERPOLATORS))
    extrapolation_options = collect(keys(EXTRAPOLATION_OPTIONS))
    direction_options = collect(keys(DIRECTION_OPTIONS))

    fields = [
        PredictorWidget(multiple = false),
        TargetWidget(multiple = true),
        MethodWidget(; options, value = "linear"),
        SelectWidget(
            key = "extrapolation_left",
            label = "Extrapolation (left)",
            placeholder = "Select extrapolation method...",
            value = "linear",
            options = extrapolation_options
        ),
        SelectWidget(
            key = "extrapolation_right",
            label = "Extrapolation (right)",
            placeholder = "Select extrapolation method...",
            value = "linear",
            options = extrapolation_options
        ),
        SelectWidget(
            key = "dir",
            label = "Direction",
            placeholder = "Select extrapolation direction...",
            options = direction_options,
            value = "left",
            conditional = Dict("method" => ["constant"])
        ),
        PartitionWidget(),
        SuffixWidget(value = "hat")
    ]

    return CardWidget(;
        type = "interp",
        label = "Interpolation",
        output = OutputSpec("targets", "suffix"),
        fields
    )
end