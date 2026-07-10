## Card state type

@kwdef struct CardState
    content::Union{Vector{UInt8}, Nothing} = nothing
    metadata::StringDict = StringDict()
end

function jldserialize(m)
    return mktemp() do path, io
        jldopen(path, "w") do file
            file["model_state"] = m
        end
        return read(io)
    end
end

function jlddeserialize(v::AbstractVector{UInt8}, k = "model_state")
    return mktemp() do path, io
        write(io, v)
        flush(io)
        jldopen(path) do file
            return file[k]
        end
    end
end

## Card interface

"""
    abstract type Card end

Abstract supertype to encompass all possible cards.

Current implementations:

- [`SplitCard`](@ref) (`type = "split"`),
- [`WindowFunctionCard`](@ref) (`type = "window_function"`),
- [`RescaleCard`](@ref) (`type = "rescale"`),
- [`ClusterCard`](@ref) (`type = "cluster"`),
- [`DimensionalityReductionCard`](@ref) (`type = "dimensionality_reduction"`),
- [`GLMCard`](@ref) (`type = "glm"`),
- [`MixedModelCard`](@ref) (`type = "mixed_model"`),
- [`InterpCard`](@ref) (`type = "interp"`),
- [`GaussianEncodingCard`](@ref) (`type = "gaussian_encoding"`),
- [`StreamlinerCard`](@ref) (`type = "streamliner"`),
- [`WildCard`](@ref).
"""
abstract type Card end

abstract type StandardCard <: Card end
abstract type SQLCard <: Card end
abstract type StreamingCard <: Card end

"""
    Card(d::AbstractDict)

Generate a [`Card`](@ref) based on a configuration dictionary `d`.

## Examples

Dictionaries are given in TOML format for clarity.

Card configuration `d`:

```toml
type = "cluster"
method = "kmeans"
method_options = {classes = 3}
inputs = [
    "wind_10m",
    "wind_20m",
    "temperature_10m",
    "temperature_20m",
    "precipitation",
    "irradiance",
    "humidity"
]
```

Resulting card:

```julia-repl
julia> card = Card(d);

julia> typeof(card)
ClusterCard

julia> card.clusterer
Pipelines.KMeansMethod(3, 100, 1.0e-6, nothing)

julia> card.inputs
7-element Vector{String}:
 "wind_10m"
 "wind_20m"
 "temperature_10m"
 "temperature_20m"
 "precipitation"
 "irradiance"
 "humidity"
```
"""
function Card(d::AbstractDict; adjust::Bool = false)
    type::String = d["type"]
    C = CARD_SPECS[type].type
    return adjust ? C(adjust_config(C, d)) : C(d)
end

"""
    Card(d::AbstractDict, params::AbstractDict; recursive::Integer = 1)

Generate a [`Card`](@ref) based on a _parametric_ configuration dictionary `d`
and parameter dictionary `params`.
The value `recursive` denotes how many times to process replaced variables.
Use `recursive = 0` to avoid recursion altogether and a large number to allow
arbitrary recursion.

!!! warning
    Parametric configurations are experimental, the API is not yet
    fully stabilized and documented.

## Current implementation

- Variable substitution based on key `-v`
- Splicing variable substitution based on key `-s`
- Range substitution based on key `-r`
- Splicing joining with underscore based on key `-j`

## Examples

Dictionaries are given in TOML format for clarity.

Initial card configuration `d`:

```toml
type = "cluster"
method = "kmeans"
method_options = {classes = {"-v" = "nclasses"}}
inputs = [
    {"-j" = ["component", {"-r" = 3}]},
    {"-j" = [["wind", "temperature"], ["10m", "20m"]]},
    {"-s" = "additional_input_vars"},
    "humidity"
]
```

Parameter dictionary `params`:

```toml
nclasses = 3
additional_input_vars = ["precipitation", "irradiance"]
```

Final card configuration `Pipelines.apply_helpers(d, params; recursive)`:

```toml
method = "kmeans"
classes = 3
type = "cluster"
inputs = [
    "component_1",
    "component_2",
    "component_3",
    "wind_10m",
    "wind_20m",
    "temperature_10m",
    "temperature_20m",
    "precipitation",
    "irradiance",
    "humidity"
]
```
"""
function Card(
        d::AbstractDict, params::AbstractDict;
        recursive::Integer = 1, adjust::Bool = false
    )
    return Card(apply_helpers(d, params; recursive); adjust)
end

## Encode how a given card uses table variables

@kwdef struct SourceVariables
    order_by::Vector{String} = String[]
    group_by::Vector{String} = String[]
    helpers::Vector{String} = String[]
    inputs::Vector{String} = String[]
    inverse_inputs::Vector{String} = String[]
    targets::Vector{String} = String[]
    weights::Union{String, Nothing} = nothing
    partition::Union{String, Nothing} = nothing
end

struct OutputVariables
    outputs::Vector{String}
    inverse_outputs::Vector{String}
end

OutputVariables(outputs::AbstractVector) = OutputVariables(outputs, String[])

function get_metadata end

## Training and evaluation

"""
    invertible(c::Card)::Bool

Return `true` for invertible cards, `false` otherwise.
"""
invertible(::Card) = false

"""
    train(
        repository::Repository, card::Card, source;
        schema::Union{AbstractString, Nothing} = nothing
    )::CardState

Return a trained model for a given `card` on a table `table` in the database `repository.db`.
"""
function train end

"""
    evaluate(
        repository::Repository,
        card::Card,
        state::CardState,
        (source, destination)::Pair,
        id_var::AbstractString;
        schema::Union{AbstractString, Nothing} = nothing
    )

Replace table `destination` in the database `repository.db` with the outcome of executing the `card`
on the table `source`.
The column `id_var` should be a primarye key of the `source` table.
The new table `destination` will then also have an additional column `id_var`,
to be joined with the column `id_var` of the original table.

A valid implementation of `evaluate` must return the list of output variables added to `destination`.

Here, `state` represents the result of `train(repository, card, source; schema)`.
See also [`train`](@ref).
"""
function evaluate end

"""
    report(repository::Repository, nodes::AbstractVector)

Create default reports for all `nodes` referring to a given `repository`.
Each node must be of type `Node`.
"""
function report(repository::Repository, nodes::AbstractVector)
    return report.(Ref(repository), get_card.(nodes), get_state.(nodes))
end

"""
    report(::Repository, ::Card, ::CardState)

Overload this method (replacing `Card` with a specific card type)
to implement a default report for a given card type.
"""
report(::Repository, ::Card, ::CardState) = StringDict()

"""
    visualize(repository::Repository, nodes::AbstractVector)

Create default visualizations for all `nodes` referring to a given `repository`.
Each node must be of type `Node`.
"""
function visualize(repository::Repository, nodes::AbstractVector)
    return visualize.(Ref(repository), get_card.(nodes), get_state.(nodes))
end

"""
    visualize(::Repository, ::Card, ::CardState)

Overload this method (replacing `Card` with a specific card type)
to implement a default visualization for a given card type.
"""
visualize(::Repository, ::Card, ::CardState) = nothing

## Define new cards using a global dictionary

struct CardSpec
    type::Type
    label::String
    schema::Function
    settings::Any
end

"""
    CardSpec(
        f::Function = Returns(Dict());
        type::Type, label::AbstractString, settings::Any = nothing,
    )

Specification to register a given card type.
"""
function CardSpec(
        f::Function = Returns(Dict());
        type::Type, label::AbstractString, settings::Any = nothing,
        kwargs...
    )
    isempty(kwargs) || @warn "Only `type`, `label` and `settings` keyword arguments are allowed in `CardSpec`"
    return CardSpec(type, label, f, settings)
end

get_label(spec::CardSpec) = spec.label

const CARD_SPECS = OrderedDict{String, CardSpec}()

get_spec(k::AbstractString) = CARD_SPECS[k]

"""
    register_card((key, spec)::Pair{<:AbstractString, CardSpec})

Register a card spec `spec` as the default card for string.
Seel [`CardSpec`](@ref).
"""
function register_card((key, spec)::Pair{<:AbstractString, CardSpec})
    CARD_SPECS[key] = spec
    return
end

## Helper (support two modalities to pass method options)

function extract_options(c::AbstractDict, key::AbstractString, m::AbstractString)
    option_key = string(key, "_", "options")
    r = r"^" * join([option_key, m, ""], ".") * r"(?<name>.*)$"
    return get(c, option_key) do
        d = StringDict()
        for (k, v) in pairs(c)
            m = match(r, k)
            isnothing(m) || (d[m[:name]] = v)
        end
        return d
    end
end

## Construction and metadata helpers

card_name(c::Card) = findfirst(spec -> isa(c, spec.type), CARD_SPECS)
card_name(T::Type) = findfirst(spec -> (T <: spec.type), CARD_SPECS)

card_type(config::AbstractDict) = CARD_SPECS[config["type"]].type

@choosetype DashiStyle Card card_type

function get_method(
        config::AbstractDict, methods::AbstractDict;
        default::Union{AbstractString, Nothing} = nothing
    )
    method::String = isnothing(default) ? config["name"] : get(config, "name", default)
    M = get(methods, method, nothing)
    if isnothing(M)
        valid_methods = join(keys(methods), ", ")
        throw(ArgumentError("Invalid method: '$method'. Valid methods are: $valid_methods."))
    end
    return M
end

function _get_metadata(c::Card, methods::AbstractDict)
    d = construct(StringDict, c)
    d["type"] = card_name(c)
    d["method"] = construct(StringDict, c.method)
    d["method"]["name"] = findfirst(Fix1(isa, c.method), methods)
    return d
end
