const CORS_RES_HEADERS = ["Access-Control-Allow-Origin" => "*"]

const CORS_OPTIONS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Headers" => "*",
    "Access-Control-Allow-Methods" => "GET, POST, OPTIONS",
]

options_handler(::HTTP.Request) = HTTP.Response(200, headers = CORS_OPTIONS_HEADERS)
cors404(::HTTP.Request) = HTTP.Response(404, headers = CORS_RES_HEADERS, body = "")
cors405(::HTTP.Request) = HTTP.Response(405, headers = CORS_RES_HEADERS, body = "")

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
        started = time()
        try
            return handler(stream)
        finally
            # In `finally`, so a handler that throws is still reported — otherwise the one request
            # worth seeing is the only one missing. Note the status logged in that case is
            # whatever had been set *before* the throw: HTTP.jl substitutes its own 500 further
            # out, after this has already unwound.
            response = stream.response
            @debug "$(request.method) $(request.target)" status =
                response === nothing ? nothing : response.status seconds =
                round(time() - started, digits = 3)
            # Julia block-buffers `stderr` when it is not a terminal, so a redirected log stays
            # empty until the process exits — measured: a server that had failed a run showed a
            # zero-byte file for as long as it kept running. A log nobody can read while the
            # server is up is not a log, so every request flushes on its way out.
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

function json_read(stream::HTTP.Stream)
    return JSON.parse(read(stream, String))
end

function json_read(req::HTTP.Request)
    return JSON.parse(String(req.body))
end

function json_response(d; omit_null::Bool = false)
    headers = vcat(CORS_RES_HEADERS, ["Content-Type" => "application/json"])
    return HTTP.Response(200, headers = headers, body = JSON.json(d; omit_null))
end

function stream_data(
        stream::HTTP.Stream, path::AbstractString, content_type::AbstractString;
        pre::AbstractString = "", post::AbstractString = ""
    )

    nbytes = filesize(path) + ncodeunits(pre) + ncodeunits(post)

    HTTP.setstatus(stream, 200)
    foreach(Base.Fix1(HTTP.setheader, stream), CORS_RES_HEADERS)
    HTTP.setheader(stream, "Content-Type" => content_type)
    HTTP.setheader(stream, "Content-Length" => string(nbytes))

    startwrite(stream)
    print(stream, pre)
    open(Fix1(write, stream), path)
    print(stream, post)
    closewrite(stream)
    closeread(stream)
    return
end
