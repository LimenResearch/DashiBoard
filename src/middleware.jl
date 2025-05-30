const CORS_RES_HEADERS = ["Access-Control-Allow-Origin" => "*"]

const CORS_OPTIONS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Headers" => "*",
    "Access-Control-Allow-Methods" => "GET, POST, OPTIONS",
]

function request_middleware(handler)
    return function (req::HTTP.Request)
        r = handler(req)
        return HTTP.Response(200, CORS_RES_HEADERS, r)
    end
end

function stream_middleware(handler)
    return function (stream::HTTP.Stream)
        for header in CORS_RES_HEADERS
            HTTP.setheader(stream, header)
        end
        handler(stream)
        return
    end
end

function register_handler!(
        router::HTTP.Router,
        method::AbstractString,
        path::AbstractString,
        handler;
        stream::Bool = false
    )

    handler′ = stream ? stream_middleware(handler) : HTTP.streamhandler(request_middleware(handler))
    HTTP.register!(router, method, path, handler′)
    HTTP.register!(router, "OPTIONS", path, HTTP.streamhandler(options_handler))
    return
end

options_handler(::HTTP.Request) = HTTP.Response(200, CORS_OPTIONS_HEADERS)
cors404(::HTTP.Request) = HTTP.Response(404, CORS_RES_HEADERS, "")
cors405(::HTTP.Request) = HTTP.Response(405, CORS_RES_HEADERS, "")
