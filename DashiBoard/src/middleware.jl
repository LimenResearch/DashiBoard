const CORS_RES_HEADERS = ["Access-Control-Allow-Origin" => "*"]

const CORS_OPTIONS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Headers" => "*",
    "Access-Control-Allow-Methods" => "GET, POST, OPTIONS",
]

options_handler(::HTTP.Request) = HTTP.Response(200, headers = CORS_OPTIONS_HEADERS)
cors404(::HTTP.Request) = HTTP.Response(404, headers = CORS_RES_HEADERS, body = "")
cors405(::HTTP.Request) = HTTP.Response(405, headers = CORS_RES_HEADERS, body = "")

# Requests answered since the process started, so a gap in the log reads as a gap rather than as
# quiet. Atomic because HTTP serves connections concurrently.
const REQUEST_COUNT = Threads.Atomic{Int}(0)

"""
    LoggingMiddleware(handler)

One `@debug` line per request: the route, what came back, and how long it took.

The server logged nothing on a successful request, so "what is it doing" could only be inferred
from CPU time and the DuckDB write-ahead log — which cannot distinguish a probe from a card IR
fetch, and cannot see a request that fails before reaching a handler at all.

Three things here are unavailable to a handler, which is why this is a middleware and not a line in
each one:

  * **status** is decided after the handler returns — a handler yields a `Response`, and what is
    finally sent can differ (an `OPTIONS` preflight is answered by the CORS layer; a 404 or 405
    never reaches a route handler at all);
  * **duration** needs something that brackets the call;
  * **coverage** is automatic, so a route added later is logged the day it is added, and no
    handler can forget.

At `@debug` rather than `@info` deliberately: an access log that is always on is a file that grows
without anyone asking for it, and `probe-pipeline` fires on every keystroke. `JULIA_DEBUG=DashiBoard`
turns it on for a session; unset, Julia's logging macro tests the level before evaluating its
arguments, so a disabled line costs nothing and formats nothing.

Two things deliberately absent. **Response size**, because HTTP 2.6.7's server stream carries no
bytes-written counter and inventing one means wrapping every write. And **`valid`/`kind`** from the
two routes that carry them, because reading those means parsing every response body here, and the
case that matters — a run that failed — already logs itself with a backtrace from
`evaluate_pipeline`.

`stream` is left untyped: a middleware needs only what it reads, and the concrete type is a
thirty-field mutable struct that cannot reasonably be constructed in a test.
"""
function LoggingMiddleware(handler)
    return function (stream)
        request = stream.message
        n = Threads.atomic_add!(REQUEST_COUNT, 1) + 1
        # Stamped on *arrival*, not on completion, though the line is written when the request
        # finishes. Requests overlap, so completion order is not arrival order: a 9.4s call that
        # started first finished after an 8.5s call that started second, and the log read
        # `#2 … 23.636` above `#1 … 24.329`. An access log whose numbers and clock disagree is
        # worse than one with neither.
        arrived = Dates.now()
        started = time()
        try
            return handler(stream)
        finally
            # In `finally`, so a handler that throws is still reported — otherwise the one request
            # worth seeing is the only one missing. Note the status logged in that case is
            # whatever had been set *before* the throw: HTTP.jl substitutes its own 500 further
            # out, after this has already unwound.
            response = stream.response
            status = response === nothing ? "-" : response.status
            elapsed = round(time() - started, digits = 3)
            # One line, not a `@debug` with keyword arguments. Julia renders those over five lines
            # with a box drawing around them, which is unreadable at one request per keystroke and
            # needs a parser to answer "what happened between 17:05 and 17:06". The fields are in a
            # fixed order, so `grep` and `awk` still work.
            #
            # The timestamp is the field this log shipped without, and its absence made the log
            # unable to answer the first question asked of it — which of these requests belong to
            # that page load. Full date because a server outlives a day.
            @debug "$(Dates.format(arrived, "yyyy-mm-dd HH:MM:SS.sss")) " *
                "#$(n) $(request.method) $(request.target) $(status) $(elapsed)s"
            # Julia block-buffers `stderr` when it is not a terminal, so a redirected log stays
            # empty until the process exits. A log nobody can read while the server is up is not a
            # log, so every request flushes on its way out.
            #
            # Unconditional, and it covers more than this line: a handler's own `@error` is
            # written during the call this brackets, so one flush here carries it out too, whether
            # or not `@debug` is enabled. One flush per request is nothing beside a DuckDB query.
            flush(stderr)
        end
    end
end

function CorsMiddleware(handler)
    return function (stream::HTTP.Stream)
        req = startread(stream)
        return if req.method == "OPTIONS"
            HTTP.streamhandler(options_handler)(stream)
        else
            handler(stream)
        end
    end
end

stringify_visualization(::Nothing) = nothing
stringify_visualization(x) = sprint(show, MIME"image/svg+xml"(), x)

"""
    to_json(d; omit_null = false)

Non-finite floats are written as `null`. `JSON.json` refuses `NaN` and `Inf` outright, so a run
whose z-score of a zero-variance column is `NaN` on every row would be reported to the client as
an execution failure although the pipeline succeeded — only the response could not be written.
`allownan = true` alone is not the fix:
the tokens it writes are not JSON and the browser's parser rejects them. `null` is what every
JSON client already reads as "no value", and it is what the rows path (`fetch_data`) produces too.
"""
function to_json(d; omit_null::Bool = false)
    return JSON.json(d; omit_null, allownan = true, nan = "null", inf = "null", ninf = "null")
end

# Handler transformation

const JSON_HEADERS = [
    "Content-Type" => "application/json",
    "Accept" => "application/json",
]

struct JSONHandler
    handlers::StringDict
end

function (h::JSONHandler)(req::HTTP.Request)
    s = String(req.body)
    # TODO: support list?
    res::Union{JSONSuccess, JSONFailure, Nothing} = DashiBase.apply_handlers(h.handlers, s)
    headers = JSON_HEADERS
    return if isnothing(res)
        HTTP.Response(204; headers)
    else
        HTTP.Response(200; headers, body = to_json(res))
    end
end

struct JSONStreamHandler
    handlers::StringDict
end

function (h::JSONStreamHandler)(stream::HTTP.Stream)
    s = read(String, stream)
    mktemp() do path, _
        res = DashiBase.apply_handlers(h.handlers, s, path)
        if res isa Tuple
            headers, writer = res
            foreach(Fix1(HTTP.setheader, stream), headers)
            HTTP.setstatus(stream, 200)
            startwrite(stream)
            writer(stream, path)
        elseif isnothing(res)
            HTTP.setstatus(stream, 204)
            foreach(Fix1(HTTP.setheader, stream), JSON_HEADERS)
            startwrite(stream)
        else
            HTTP.setstatus(stream, 200) # Consider error status here
            foreach(Fix1(HTTP.setheader, stream), JSON_HEADERS)
            startwrite(stream)
            write(stream, to_json(res))
        end
        closewrite(stream)
        closeread(stream)
    end
    return
end

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
        valid = false, kind,
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
