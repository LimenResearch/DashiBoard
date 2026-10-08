# schema utils for Streamliner cards (TODO: test here directly, not only in Pipelines)

function StreamlinerIR(configs::AbstractVector)
    properties = map(configs) do config
        c = StringDict(config)
        key::String = pop!(c, "key")
        value = StructUtils.make(DashiBase.AbstractIR, c)
        # potentially allow a custom keyword for this
        is_required = !haskey(c, "default")
        return Property(key => value, required = is_required)
    end
    return ObjectIR(; properties)
end

# Compute schemas used for model or training in Streamliner,
# e.g., `TaggedStreamlinerIR(model_dir, "model")`
# `kind` names the directory the options are the files of, so a form can show the file behind
# a name rather than the name alone.
function TaggedStreamlinerIR(dir, kind::AbstractString)
    vals = available_streamliner_configs(dir, kind)
    objects = OrderedDict{String, ObjectIR}(x => StreamlinerIR(parse_properties(dir, x)) for x in vals)
    return TaggedObjectIR(; objects, options_from = kind)
end

## Parsing

const MODEL_DIR = ScopedValue{String}()
const TRAINING_DIR = ScopedValue{String}()

"""
    configuration_kind(parsed) -> Union{String, Nothing}

`"model"`, `"training"`, or `nothing`: what a parsed TOML is a configuration of, told by the
tables each is built from.
"""
function configuration_kind(parsed)
    parsed isa AbstractDict || return nothing
    (haskey(parsed, "components") || haskey(parsed, "loss")) && return "model"
    (haskey(parsed, "optimizer") || haskey(parsed, "iterations")) && return "training"
    return nothing
end

# A configuration may be filed in a subfolder like any other file; its name is then the path
# from `dir` without the extension, `sub/x`, which is also how a card names it. Hidden folders
# and `quarantine` — what a workspace sets aside — are not looked into.
function toml_names(keep, dir)
    names = String[]
    for (root, dirs, files) in walkdir(dir)
        filter!(d -> !startswith(d, ".") && d != "quarantine", dirs)
        for file in files
            stem, ext = splitext(file)
            ext == ".toml" && keep(joinpath(root, file)) || continue
            push!(names, replace(normpath(relpath(joinpath(root, stem), dir)), '\\' => '/'))
        end
    end
    return sort!(names)
end

available_streamliner_configs(dir) = toml_names(Returns(true), dir)

"""
    available_streamliner_configs(dir, kind)

The configurations of `kind` — `"model"` or `"training"` — under `dir`. A directory may hold
other TOML files, the other kind's among them when one folder serves for both; only a file that
parses and is a configuration of this kind counts, so one stray file does not break the listing.
"""
function available_streamliner_configs(dir, kind::AbstractString)
    return toml_names(dir) do path
        parsed = try
            TOML.parsefile(path)
        catch
            return false
        end
        return configuration_kind(parsed) == kind
    end
end

function parse_without_properties(dir, x)
    file = string(x, ".toml")
    c = TOML.parsefile(joinpath(dir, file))
    delete!(c, "properties")
    return c
end

function parse_properties(dir, x)::Vector{StringDict}
    file = string(x, ".toml")
    c = TOML.parsefile(joinpath(dir, file))
    return get(c, "properties", StringDict[])
end

## Model, Training, and Funnel implementations

function get_streamliner_model(d::AbstractDict)
    model_name::String = d["type"]
    model = parse_without_properties(MODEL_DIR[], model_name)
    return Model(PARSER[], model, d)
end

StructUtils.structlike(::DashiStyle, ::Type{<:Model}) = false

function StructUtils.lift(::DashiStyle, ::Type{Model}, d::AbstractDict)
    return if isassigned(MODEL_DIR)
        get_streamliner_model(d), nothing
    else
        Model(PARSER[], d), nothing
    end
end

StructUtils.lower(::DashiStyle, model::Model) = get_metadata(model)

function DashiBase.IR_from_type(::Type{Model}, default)
    if !isnothing(default)
        throw(ArgumentError("Default not supported here"))
    end
    # TODO: here and for `Training` decide more carefully
    #  how to distinguish between the two cases
    # Same for the lifting method
    return if isassigned(MODEL_DIR)
        vals = TaggedStreamlinerIR(MODEL_DIR[], "model")
    else
        ObjectIR(additionalProperties = true)
    end
end

function get_streamliner_training(d::AbstractDict)
    training_name::String = d["type"]
    training = parse_without_properties(TRAINING_DIR[], training_name)
    return Training(PARSER[], training, d)
end

StructUtils.structlike(::DashiStyle, ::Type{<:Training}) = false

function StructUtils.lift(::DashiStyle, ::Type{Training}, d::AbstractDict)
    return if isassigned(TRAINING_DIR)
        get_streamliner_training(d), nothing
    else
        Training(PARSER[], d), nothing
    end
end

StructUtils.lower(::DashiStyle, training::Training) = get_metadata(training)

function DashiBase.IR_from_type(::Type{Training}, default)
    if !isnothing(default)
        throw(ArgumentError("Default not supported here"))
    end
    return if isassigned(TRAINING_DIR)
        TaggedStreamlinerIR(TRAINING_DIR[], "training")
    else
        ObjectIR(additionalProperties = true)
    end
end

function get_streamliner_funnel(d::AbstractDict)
    funnel_name::String = get(d, "type", "")
    F = PARSER[].funnels[funnel_name]
    return make_funnel(F, filter(!=("type") ∘ first, d))
end

# The funnels a card may name, as a choice among those registered in the parser in scope, each
# described by its own fields. The blank one is the default.
function DashiBase.IR_from_type(::Type{Funnel}, default)
    if !isnothing(default)
        throw(ArgumentError("Default not supported here"))
    end
    objects = Dict{String, ObjectIR}(name => funnel_IR(F) for (name, F) in pairs(PARSER[].funnels))
    return TaggedObjectIR(; objects, default_option = "")
end

# An abstract funnel is chosen by name, so it is read through `lift`; a concrete one is read field
# by field.
StructUtils.structlike(::DashiStyle, ::Type{Funnel}) = false

function StructUtils.lift(::DashiStyle, ::Type{Funnel}, d::AbstractDict)
    return get_streamliner_funnel(d), nothing
end

function StructUtils.lower(::DashiStyle, funnel::Funnel)
    d = get_metadata(funnel)
    d["type"] = findfirst(Fix1(isa, funnel), PARSER[].funnels)
    return d
end
