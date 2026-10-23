const CORS_RES_HEADERS = ["Access-Control-Allow-Origin" => "*"]

const CORS_OPTIONS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Headers" => "*",
    "Access-Control-Allow-Methods" => "GET, POST, OPTIONS",
]

options_handler(::HTTP.Request) = HTTP.Response(200, headers = CORS_OPTIONS_HEADERS)
cors404(::HTTP.Request) = HTTP.Response(404, headers = CORS_RES_HEADERS, body = "")
cors405(::HTTP.Request) = HTTP.Response(405, headers = CORS_RES_HEADERS, body = "")

function CorsMiddleware(handler)
    return function (stream::HTTP.Stream)
        req = startread(stream)
        return if req.method == "OPTIONS"
            HTTP.streamhandler(options_handler)(stream)
        else
            # Set here, before any route writes, so every reply carries it and no route can
            # forget; a browser refuses a cross-origin reply without it.
            foreach(Fix1(HTTP.setheader, stream), CORS_RES_HEADERS)
            handler(stream)
        end
    end
end

stringify_visualization(::Nothing) = nothing
stringify_visualization(x) = sprint(show, MIME"image/svg+xml"(), x)

"""
    to_json(d)

Non-finite floats are written as `null`. `JSON.json` refuses `NaN` and `Inf` outright, so a run
whose z-score of a zero-variance column is `NaN` on every row would be reported to the client as
an execution failure although the pipeline succeeded — only the response could not be written.
`allownan = true` alone is not the fix:
the tokens it writes are not JSON and the browser's parser rejects them. `null` is what every
JSON client already reads as "no value", and it is what the rows path (`fetch_data`) produces too.
"""
function to_json(d)
    return JSON.json(d; allownan = true, nan = "null", inf = "null", ninf = "null")
end

# Handler transformation

const JSON_HEADERS = [
    "Content-Type" => "application/json",
    "Accept" => "application/json",
]

"""
    reply(stream, status, body = nothing)

Write a JSON reply on `stream`. The routes write to the stream rather than return a `Response`,
because a returned `Response` replaces the stream's own and would drop the headers
`CorsMiddleware` set on it.
"""
function reply(stream::HTTP.Stream, status::Integer, body::Maybe{String} = nothing)
    HTTP.setstatus(stream, status)
    foreach(Fix1(HTTP.setheader, stream), JSON_HEADERS)
    isnothing(body) || HTTP.setheader(stream, "Content-Length" => string(ncodeunits(body)))
    startwrite(stream)
    isnothing(body) || write(stream, body)
    return
end

struct JSONHandler
    handlers::StringDict
end

# Always 200 when there is a body, failures included: the error is in the body, and a batch
# whose calls fared differently has no single status to give. Nothing to answer is 204.
function (h::JSONHandler)(stream::HTTP.Stream)
    res = DashiBase.apply_handlers(h.handlers, String(read(stream)))
    isnothing(res) ? reply(stream, 204) : reply(stream, 200, to_json(res))
    closewrite(stream)
    closeread(stream)
    return
end

"""
    stream_status(failure) -> Int

The status of a streamed request that failed. A stream may itself be JSON (`fetch-data` is), so
the content type cannot tell a file from an error: the status does. A fault of the request is
400, an unknown method 404, and a failure while running 500.
"""
function stream_status(failure::DashiBase.JSONFailure)
    code = failure.error.code
    return code == Int(DashiBase.method_not_found) ? 404 :
        code == Int(DashiBase.internal_error) ? 500 : 400
end

struct JSONStreamHandler
    handlers::StringDict
end

(h::JSONStreamHandler)(stream::HTTP.Stream) = stream_response(h, stream, String(read(stream)))

function stream_response(h::JSONStreamHandler, stream::HTTP.Stream, s::AbstractString)
    mktemp() do path, _
        res = DashiBase.apply_handlers(h.handlers, s, path)
        if res isa Tuple
            success, writer = res
            # The thunk's result is the headers of the file it wrote to `path`.
            foreach(Fix1(HTTP.setheader, stream), success.result)
            HTTP.setstatus(stream, 200)
            startwrite(stream)
            writer(stream, path)
        elseif isnothing(res)
            reply(stream, 204)
        else
            reply(stream, stream_status(res), to_json(res))
        end
        closewrite(stream)
        closeread(stream)
    end
    return
end

# What the GET download asks for, as the request a client would have sent to `/rpc-stream`.
const PROCESSED_DATA_REQUEST = """{"jsonrpc":"2.0","id":0,"method":"get-processed-data","params":{}}"""

"""
    failure_report(kind::Symbol, exception)

The body both pipeline routes answer with when they cannot do what was asked.

`kind` says *where* it broke, not whose fault it is: `"pipeline"` for a document that could not be
turned into a pipeline — a schema failure, a duplicate id, a cycle — and `"execution"` for one that
built and then died while running. That split is on which call threw, which is observable;
"is this the author's mistake or ours" is not, and a field that claims to know would be guessing.

A client reads the two the same way and means different things by them: a `pipeline` failure sends
the author back to the cards, an `execution` failure back to the data.
"""
function failure_report(kind::Symbol, exception::Exception)
    # Four kinds of failure carry a JSON Pointer into the document, so the form can address the
    # control and, where it is known, offer a correction: a schema failure, a `through` chain the
    # pipeline refused to resolve, a product selection a card cannot write, and a transform for a
    # column a funnel does not have. Anything else — a cyclic graph, a
    # duplicate id, a binder error from DuckDB — has only its message.
    # Validation collects, so one schema failure and twenty arrive in the same shape; a chain
    # fails on the first one, so it arrives singular and is wrapped to match.
    issues = if exception isa Union{Pipelines.SchemaValidationErrors, BundleError}
        Pipelines.issue_report(exception)
    elseif exception isa Union{Pipelines.ThroughError, Pipelines.ProductError, StreamlinerCore.TransformError}
        [Pipelines.issue_report(exception)]
    else
        []
    end
    return (;
        kind,
        errors = [sprint(showerror, cause) for cause in root_causes(exception)],
        issues,
    )
end

function throw_failure(kind::Symbol, exception::Exception)
    failure = StructUtils.make(StringDict, failure_report(kind, exception))
    throw(DashiBase.StructuredException(failure))
end

struct KindHandler{F}
    handler::F
    kind::Symbol
    content::String
end

# A request for a kind route, rewritten as one for the general route it stands on: the kind
# filled in, and the path checked against the layout's folder names, resolved under the kind's
# directory and handed on relative to that directory, which becomes the general route's base.
function (kh::KindHandler)(spec::AbstractDict)
    (; handler, kind, content) = kh
    local spec′, base, what
    try
        path = spec["path"]
        base = pointer(kind)
        full = kind_path(kind, path)
        spec′ = merge(spec, Dict("kind" => content, "path" => relpath(full, base)))
        what = "the $(kind) directory"
    catch exception
        throw_failure(:document, exception)
    end
    return handler(spec′, base; what)
end

struct StructuredHandler{F}
    handler::F
    kind::Symbol
end

function (sh::StructuredHandler)(spec::AbstractDict)
    (; handler, kind) = sh
    return try
        handler(spec)
    catch exception
        throw_failure(kind, exception)
    end
end

# Streaming helper

@kwarg struct Writer
    pre::Maybe{String} = nothing
    post::Maybe{String} = nothing
end

function (w::Writer)(io::IO, path::AbstractString)
    isnothing(w.pre) || print(io, w.pre)
    open(Fix1(write, io), path)
    isnothing(w.post) || print(io, w.post)
    return
end

function content_length(w::Writer, path::AbstractString)
    n = filesize(path)
    isnothing(w.pre) || (n += ncodeunits(w.pre))
    isnothing(w.post) || (n += ncodeunits(w.post))
    return string(n)
end
