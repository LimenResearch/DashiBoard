# How a funnel reads a row.
#
# By default a row is the values of its columns. A row can instead be a tensor kept in a file, the
# table holding only the path: an image, a field on a grid. That is a property of the rows, not of
# how they are grouped into samples, so the choice belongs to every funnel. What can read a file
# is an extension's business: this package holds the slot and the contract, and registers only
# the default.

abstract type Loader end

"""
    RowLoader()

The default loader: a row is read as the values of its columns.
"""
struct RowLoader <: Loader end

"""
    FileLoader(input_paths, target_paths, reader)

Rows read as tensors from files. `input_paths` and `target_paths` each name the column holding
the paths for that side — one column a side, and at least one of the two. `reader` is the
registered object that turns a path into an array; its settings are written beside the two
columns, flat.
"""
@kwarg struct FileLoader{R} <: Loader
    input_paths::Maybe{String} = nothing & (dashi = VARIABLE_DEF,)
    target_paths::Maybe{String} = nothing & (dashi = VARIABLE_DEF,)
    reader::R
end

input_paths(::RowLoader) = nothing
target_paths(::RowLoader) = nothing
input_paths(l::FileLoader) = l.input_paths
target_paths(l::FileLoader) = l.target_paths

# What a registered reader answers. The steps that call these while streaming and at ingest are
# not in this package yet; a funnel with a file loader can be described and built, not yet run.

"""
    read_array(reader, path, kind)

The array stored at `path`, as `reader` reads it for `kind` — `:input` or `:target`.
"""
function read_array end

"""
    array_size(reader, kind)

The size of every array `reader` yields for `kind`. All files of one side share it.
"""
function array_size end

"""
    write_array(reader, array, path)

Store `array` at `path` in the format `reader` reads back.
"""
function write_array end

const PATHS_REQUIRED = "A loader that reads files names `input_paths`, `target_paths`, or both"

# The schema of one registered loader: nothing for the default, and for a reader the two path
# columns followed by its own settings.
function loader_branch(::Type{R}) where {R}
    R <: RowLoader && return ObjectIR()
    ir = flat_IR(FileLoader, :reader, ObjectIR(R))
    either = StringDict("anyOf" => [StringDict("required" => ["input_paths"]), StringDict("required" => ["target_paths"])])
    return ObjectIR(; ir.properties, constraints = vcat(ir.constraints, [either]))
end

"""
    loader_IR()

The loaders a funnel may name, as a choice among those registered in the parser in scope. The
default is the blank one, so a funnel that names none reads rows as they are.
"""
function loader_IR()
    objects = Dict{String, ObjectIR}(name => loader_branch(R) for (name, R) in pairs(PARSER[].loaders))
    return TaggedObjectIR(; objects, default_option = "")
end

"""
    make_loader(d::AbstractDict)

The loader a document describes: the one registered under `d["type"]`, the default when it is
left out.
"""
function make_loader(d::AbstractDict)
    name::String = get(d, "type", "")
    R = get(PARSER[].loaders, name, nothing)
    if isnothing(R)
        valid = join(sort!(collect(String, keys(PARSER[].loaders))), ", ")
        throw(ArgumentError("No loader is registered as '$(name)'. Registered loaders: $(valid)."))
    end
    R <: RowLoader && return RowLoader()
    settings, rest = split_config(ObjectIR(R), d)
    input::Maybe{String} = get(rest, "input_paths", nothing)
    target::Maybe{String} = get(rest, "target_paths", nothing)
    isnothing(input) && isnothing(target) && throw(ArgumentError(PATHS_REQUIRED))
    reader = DashiBase.construct(R, settings)
    return FileLoader(input, target, reader)
end

loader_name(::RowLoader) = ""
loader_name(l::FileLoader) = findfirst(R -> l.reader isa R, PARSER[].loaders)

function get_metadata(l::Loader)
    d = StringDict("type" => loader_name(l))
    l isa FileLoader || return d
    isnothing(l.input_paths) || (d["input_paths"] = l.input_paths)
    isnothing(l.target_paths) || (d["target_paths"] = l.target_paths)
    return merge!(d, DashiBase.to_config(l.reader))
end
