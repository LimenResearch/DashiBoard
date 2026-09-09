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
# e.g., `TaggedStreamlinerIR(model_dir)`
function TaggedStreamlinerIR(dir)
    vals = available_streamliner_configs(dir)
    objects = OrderedDict{String, ObjectIR}(x => StreamlinerIR(parse_properties(dir, x)) for x in vals)
    return TaggedObjectIR(; objects)
end

## Parsing

const MODEL_DIR = ScopedValue{String}()
const TRAINING_DIR = ScopedValue{String}()

function available_streamliner_configs(dir)
    return String[
        fn for (fn, ext) in Iterators.map(splitext, readdir(dir)) if ext == ".toml"
    ]
end

function parse_without_properties(dir, x)
    file = string(x, ".toml")
    c = TOML.parsefile(joinpath(dir, file))
    delete!(c, "widgets")
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
        vals = TaggedStreamlinerIR(MODEL_DIR[])
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
        TaggedStreamlinerIR(TRAINING_DIR[])
    else
        ObjectIR(additionalProperties = true)
    end
end

function get_streamliner_funnel(d::AbstractDict)
    funnel_name::String = get(d, "type", "")
    return PARSER[].funnels[funnel_name](d)
end

StructUtils.structlike(::DashiStyle, ::Type{<:Funnel}) = false

function StructUtils.lift(::DashiStyle, ::Type{Funnel}, d::AbstractDict)
    return get_streamliner_funnel(d), nothing
end

function StructUtils.lower(::DashiStyle, funnel::Funnel)
    d = get_metadata(funnel)
    d["type"] = findfirst(Fix1(isa, funnel), PARSER[].funnels)
    return d
end
