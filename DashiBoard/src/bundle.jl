# A pipeline as a workspace: the document, the configurations it names, and which extensions
# it needs — zipped, so that unpacked beside a table it launches and runs the same pipeline.
# No data goes in: the table is what the author already has.

using ZipArchives: ZipWriter, zip_newfile

# Where the configuration a card names is, confined to its kind's directory: a name is a path
# under it, never out of it.
configuration_path(kind::Symbol, name::AbstractString) =
    resolve_in(pointer(kind), string(name, ".toml"); what = "the $(kind) directory")

# The registry entries a configuration names, each keyed as the launcher records provenance:
# `"<registry>:<name>"`. A value written as a placeholder for a setting is not a name.
function configuration_entries(config::AbstractDict)
    entries = String[]
    name(registry, value) = value isa AbstractString && push!(entries, string(registry, ':', value))
    named(registry, items) = foreach(item -> item isa AbstractDict && name(registry, get(item, "name", nothing)), items)
    name("model", get(config, "name", nothing))
    for layers in values(get(config, "components", Dict{String, Any}()))
        layers isa AbstractVector || continue
        named("layer", layers)
        foreach(layer -> layer isa AbstractDict && name("sigma", get(layer, "sigma", nothing)), layers)
    end
    for metric in vcat(Any[get(config, "loss", nothing)], get(config, "metrics", Any[]))
        metric isa AbstractDict || continue
        name("metric", get(metric, "name", nothing))
        name("aggregator", get(metric, "agg", nothing))
    end
    named("regularization", get(config, "regularizations", Any[]))
    optimizer = get(config, "optimizer", nothing)
    optimizer isa AbstractDict && name("optimizer", get(optimizer, "name", nothing))
    name("device", get(config, "device", nothing))
    named("schedule", values(get(config, "schedules", Dict{String, Any}())))
    named("stopper", get(config, "stoppers", Any[]))
    return entries
end

# The registry entries a document uses. A streamliner card names a model and a training
# configuration — whose architecture, layers, losses, optimizer may each come from an extension
# — a funnel type, and the transforms of its columns.
function registry_entries(cards::AbstractDict)
    entries = String[]
    for node in get(cards, "nodes", Any[])
        card = get(node, "card", Dict{String, Any}())
        get(card, "type", nothing) == "streamliner" || continue
        for (kind, field) in ((:model, "model"), (:training, "training"))
            name = get(get(card, field, Dict{String, Any}()), "type", nothing)
            name isa AbstractString || continue
            path = configuration_path(kind, name)
            isfile(path) && append!(entries, configuration_entries(TOML.parsefile(path)))
        end
        funnel = get(card, "funnel", Dict{String, Any}())
        push!(entries, "funnel:" * get(funnel, "type", ""))
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
            name isa AbstractString || continue
            path = configuration_path(kind, name)
            isfile(path) ? push!(found, (kind, String(name), path)) : push!(issues, missing_configuration(i, field, name))
        end
    end
    return unique!(found), issues
end

# A document that cannot be bundled, with the issues to report: one per configuration it names
# and the directory lacks.
struct BundleError <: Exception
    issues::Vector{Any}
end

Base.showerror(io::IO, err::BundleError) = print(io, join((issue.message for issue in err.issues), "; "))

# The name a download is filed under becomes file names in the zip and the name of the zip: it
# has to be one plain name.
function file_stem(name)
    plain = name isa AbstractString && !isempty(strip(name)) && name != "." && name != ".." &&
        !any(c -> c in "/\\<>:\"|?*" || iscntrl(c), name)
    plain || throw(ArgumentError("`$(name)` cannot name the downloaded files: use a plain name, without folders or any of < > : \" | ? *"))
    return String(name)
end

"""
    bundle_pipeline(cards, filters, name) -> Vector{UInt8}

The zip: `pipeline/<name>.json`, `filter/<name>.json` when `filters` is given, one file per
configuration named under `model/` and `training/`, and a `dashiboard.toml` whose
`[extensions]` is the launched table narrowed to what the document needs. Throws
`BundleError` when a configuration is missing, with the issues to report.
"""
function bundle_pipeline(cards::AbstractDict, filters::Union{AbstractDict, Nothing}, name::AbstractString)
    name = file_stem(name)
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
    # Every way this can fail is said in the envelope: a download that answers with nothing
    # readable leaves the form saving an empty file or blaming the connection.
    bytes = try
        bundle_pipeline(spec["cards"], get(spec, "filters", nothing), file_stem(name))
    catch exception
        exception isa BundleError || return json_response(failure_report("bundle", exception))
        return json_response((; valid = false, kind = "bundle", errors = [sprint(showerror, exception)], issues = exception.issues))
    end
    # The plain form for a name a header can carry as it is; the encoded one, which every current
    # browser prefers, for the rest.
    plain = all(isascii, name) ? name : "pipeline"
    disposition = "attachment; filename=\"$(plain).zip\"; filename*=UTF-8''$(HTTP.escapeuri(name)).zip"
    headers = vcat(CORS_RES_HEADERS, ["Content-Type" => "application/zip", "Content-Disposition" => disposition])
    return HTTP.Response(200, headers = headers, body = bytes)
end
