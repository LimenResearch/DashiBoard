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

"""
    json_response(d; omit_null = false)

A 200 with `d` as JSON and the CORS headers.

Non-finite floats are written as `null`. `JSON.json` refuses `NaN` and `Inf` outright, so a run
whose z-score of a zero-variance column was `NaN` on every row was reported to the client as an
execution failure (A12, measured on `constant = 42`, 2026-09-13 and 2026-09-16) — the pipeline
had succeeded; only the response could not be written. `allownan = true` alone is not the fix:
the tokens it writes are not JSON and the browser's parser rejects them. `null` is what every
JSON client already reads as "no value", and it is what the rows path (`fetch_data`) produces too.
"""
function json_response(d; omit_null::Bool = false)
    headers = vcat(CORS_RES_HEADERS, ["Content-Type" => "application/json"])
    body = JSON.json(d; omit_null, allownan = true, nan = "null", inf = "null", ninf = "null")
    return HTTP.Response(200, headers = headers, body = body)
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
