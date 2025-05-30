const CORS_RES_HEADERS = ["Access-Control-Allow-Origin" => "*"]

const CORS_OPTIONS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Headers" => "*",
    "Access-Control-Allow-Methods" => "GET, POST, OPTIONS",
]

function CorsHandlerRequest(handler)
    return function (req::HTTP.Request)
        return if HTTP.method(req) == "OPTIONS"
            HTTP.Response(200, CORS_OPTIONS_HEADERS)
        else
            r = handler(req)
            r isa HTTP.Response ? r : HTTP.Response(200, CORS_RES_HEADERS, r)
        end
    end
end

request_middleware(handler) = HTTP.streamhandler(CorsHandlerRequest(handler))

setheaders(stream::HTTP.Stream, headers) = foreach(Fix1(HTTP.setheader, stream), headers)

function CorsHandlerStream(handler)
    return function (stream::HTTP.Stream)
        if HTTP.method(stream.message) == "OPTIONS"
            setheaders(stream, CORS_OPTIONS_HEADERS)
        else
            setheaders(stream, CORS_RES_HEADERS)
            handler(stream)
        end
        return
    end
end

stream_middleware(handler) = CorsHandlerStream(handler)

cors404(::HTTP.Request) = HTTP.Response(404, CORS_RES_HEADERS, "")
cors405(::HTTP.Request) = HTTP.Response(405, CORS_RES_HEADERS, "")
