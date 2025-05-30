const POST_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Methods" => "GET, POST",
    "Access-Control-Allow-Credentials" => "true",
]

const OPTIONS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Headers" => "*",
    "Access-Control-Allow-Methods" => "GET, POST",
]

function CorsHandlerRequest(handler)
    return function (req::HTTP.Request)
        return if HTTP.method(req) == "OPTIONS"
            HTTP.Response(200, OPTIONS_HEADERS)
        else
            r = handler(req)
            r isa HTTP.Response ? r : HTTP.Response(200, POST_HEADERS, r)
        end
    end
end

request_middleware(handler) = HTTP.streamhandler(CorsHandlerRequest(handler))

setheaders(stream::HTTP.Stream, headers) = foreach(Fix1(HTTP.setheader, stream), headers)

function CorsHandlerStream(handler)
    return function (stream::HTTP.Stream)
        if HTTP.method(stream.message) == "OPTIONS"
            setheaders(stream, OPTIONS_HEADERS)
        else
            setheaders(stream, POST_HEADERS)
            handler(stream)
        end
        return
    end
end

stream_middleware(handler) = CorsHandlerStream(handler)
