const CORS_RES_HEADERS = ["Access-Control-Allow-Origin" => "*"]

const CORS_OPTIONS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Headers" => "*",
    "Access-Control-Allow-Methods" => "GET, POST, OPTIONS",
]

function stream_middleware(handler)
    return function (stream::HTTP.Stream)
        for header in CORS_RES_HEADERS
            HTTP.setheader(stream, header)
        end
        handler(stream)
        return
    end
end

function _register!(
        router::HTTP.Router,
        method::AbstractString,
        path::AbstractString,
        handler::Function,
        settings::Settings
    )

    scoped_handler = ScopedHandler(handler, settings)
    HTTP.register!(router, method, path, stream_middleware(scoped_handler))
    HTTP.register!(router, "OPTIONS", path, HTTP.streamhandler(options_handler))
    return
end

options_handler(::HTTP.Request) = HTTP.Response(200, CORS_OPTIONS_HEADERS)
cors404(::HTTP.Request) = HTTP.Response(404, CORS_RES_HEADERS, "")
cors405(::HTTP.Request) = HTTP.Response(405, CORS_RES_HEADERS, "")
