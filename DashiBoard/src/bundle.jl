# A pipeline as a workspace: the document, the configurations it names, and which extensions
# it needs — zipped, so that unpacked beside a table it launches and runs the same pipeline.
# No data goes in: the table is what the author already has.

using ZipArchives: ZipWriter, zip_newfile

# The registry entries a document uses, each keyed as the launcher records provenance:
# `"<registry>:<name>"`. A streamliner card names a model configuration, whose `name` is the
# architecture; a funnel type; a loader type; and the transforms of its columns.
function registry_entries(cards::AbstractDict)
    entries = String[]
    for node in get(cards, "nodes", Any[])
        card = get(node, "card", Dict{String, Any}())
        get(card, "type", nothing) == "streamliner" || continue
        model = get(card, "model", Dict{String, Any}())
        if haskey(model, "type")
            config = Pipelines.SC.parse_without_properties(pointer(:model), model["type"])
            haskey(config, "name") && push!(entries, "model:" * config["name"])
        end
        funnel = get(card, "funnel", Dict{String, Any}())
        push!(entries, "funnel:" * get(funnel, "type", ""))
        loader = get(funnel, "loader", Dict{String, Any}())
        push!(entries, "loader:" * get(loader, "type", ""))
        for map in ("input_transforms", "target_transforms"), transform in values(get(funnel, map, Dict{String, Any}()))
            push!(entries, "transform:" * transform)
        end
    end
    return unique!(entries)
end

"""
    needed_extensions(cards) -> Vector{String}

The extensions that contributed something the document uses, by name, sorted. Known from the
provenance the launcher records when it combines the parsers; a server launched without
extensions needs none.
"""
function needed_extensions(cards::AbstractDict)
    provenance = EXTENSION_OF[]
    names = String[provenance[entry] for entry in registry_entries(cards) if haskey(provenance, entry)]
    return sort!(unique!(names))
end

# One pointed issue, in the shape every other issue has, for a configuration the document names
# and the directory lacks.
function missing_configuration(index::Integer, field::AbstractString, name::AbstractString)
    return (;
        pointer = "/nodes/$(index - 1)/card/$(field)/type", reason = "missing", severity = "error",
        found = name, allowed = nothing, missing = String[], related = String[],
        message = "no $(field) configuration is called `$(name)`",
    )
end

# The configuration files the document names: `(kind, name, path)`, or the issues for those
# that are not there.
function named_configurations(cards::AbstractDict)
    found, issues = Tuple{Symbol, String, String}[], Any[]
    for (i, node) in enumerate(get(cards, "nodes", Any[]))
        card = get(node, "card", Dict{String, Any}())
        get(card, "type", nothing) == "streamliner" || continue
        for (kind, field) in ((:model, "model"), (:training, "training"))
            name = get(get(card, field, Dict{String, Any}()), "type", nothing)
            isnothing(name) && continue
            path = joinpath(pointer(kind), string(name, ".toml"))
            isfile(path) ? push!(found, (kind, String(name), path)) : push!(issues, missing_configuration(i, field, name))
        end
    end
    return unique!(found), issues
end

"""
    bundle_pipeline(cards, filters, name) -> Vector{UInt8}

The zip: `pipeline/<name>.json`, `filter/<name>.json` when `filters` is given, one file per
configuration named under `model/` and `training/`, and a `dashiboard.toml` whose
`[extensions]` is the launched table narrowed to what the document needs. Throws
`BundleError` when a configuration is missing, with the issues to report.
"""
struct BundleError <: Exception
    issues::Vector{Any}
end

Base.showerror(io::IO, err::BundleError) = print(io, join((issue.message for issue in err.issues), "; "))

function bundle_pipeline(cards::AbstractDict, filters::Union{AbstractDict, Nothing}, name::AbstractString)
    configurations, issues = named_configurations(cards)
    isempty(issues) || throw(BundleError(issues))
    extensions = Dict{String, Any}(ext => EXTENSIONS[][ext] for ext in needed_extensions(cards) if haskey(EXTENSIONS[], ext))
    io = IOBuffer()
    ZipWriter(io) do zip
        entry(path, content) = (zip_newfile(zip, path); write(zip, content))
        entry("pipeline/$(name).json", JSON.json(cards; pretty = true))
        isnothing(filters) || entry("filter/$(name).json", JSON.json(filters; pretty = true))
        for (kind, config, path) in configurations
            entry("$(kind)/$(config).toml", read(path))
        end
        buffer = IOBuffer()
        TOML.print(buffer, Dict("extensions" => extensions))
        entry("dashiboard.toml", take!(buffer))
    end
    return take!(io)
end

"""
    bundle_pipeline(req)

`{name, cards, filters?}` → the zip as `application/zip`, named for download; or the JSON
failure envelope, with an issue pointed at each configuration the document names and the
directory lacks, so the form can mark the card rather than show a half zip.
"""
function bundle_pipeline(req::HTTP.Request)
    spec = json_read(req)
    name = get(spec, "name", "pipeline")
    bytes = try
        bundle_pipeline(spec["cards"], get(spec, "filters", nothing), name)
    catch exception
        exception isa BundleError || rethrow()
        return json_response((; valid = false, kind = "bundle", errors = [sprint(showerror, exception)], issues = exception.issues))
    end
    headers = vcat(
        CORS_RES_HEADERS,
        ["Content-Type" => "application/zip", "Content-Disposition" => "attachment; filename=\"$(name).zip\""],
    )
    return HTTP.Response(200, headers = headers, body = bytes)
end
