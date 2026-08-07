const CORS_RES_HEADERS = ["Access-Control-Allow-Origin" => "*"]

const CORS_OPTIONS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Headers" => "*",
    "Access-Control-Allow-Methods" => "GET, POST, OPTIONS",
]

stringify_visualization(::Nothing) = nothing
stringify_visualization(x) = sprint(show, MIME"image/svg+xml"(), x)

function stream_data(
        stream::HTTP.Stream, path::AbstractString, content_type::AbstractString;
        pre::AbstractString = "", post::AbstractString = ""
    )

    nbytes = filesize(path) + ncodeunits(pre) + ncodeunits(post)

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

# TODO: consider reading / writing directly from the stream

function json_read(stream::HTTP.Stream)
    return JSON.parse(read(stream, String))
end

function json_read(req::HTTP.Request)
    return JSON.parse(String(req.body))
end

function json_response(d)
    headers = vcat(CORS_RES_HEADERS, ["Content-Type" => "application/json"])
    return HTTP.Response(200, headers = headers, body = JSON.json(d))
end

function _register!(
        router::HTTP.Router,
        method::AbstractString,
        path::AbstractString,
        handler,
        settings::Settings
    )

    scoped_handler = ScopedHandler(handler, settings)
    HTTP.register!(router, method, path, scoped_handler)
    HTTP.register!(router, "OPTIONS", path, HTTP.streamhandler(options_handler))
    return
end

options_handler(::HTTP.Request) = HTTP.Response(200, headers = CORS_OPTIONS_HEADERS)
cors404(::HTTP.Request) = HTTP.Response(404, headers = CORS_RES_HEADERS, body = "")
cors405(::HTTP.Request) = HTTP.Response(405, headers = CORS_RES_HEADERS, body = "")
