@enum(
    JSONErrorCode,
    parse_error = −32700,
    invalid_request = −32600,
    method_not_found = −32601,
    invalid_params = −32602,
    internal_error = −32603,
)

const DEFAULT_MESSAGES = Dict{JSONErrorCode, String}(
    parse_error => "Parse error",
    invalid_request => "Invalid Request",
    method_not_found => "Method not found",
    invalid_params => "Invalid params",
    internal_error => "Internal error"
)

struct StructuredException <: Exception
    data::StringDict
end

function explicit_error_message(f::F, code::JSONErrorCode) where {F}
    return sprint() do io
        print(io, "*")
        print(io, DEFAULT_MESSAGES[code])
        println(io, "*")
        f(io)
    end
end

function explicit_error_message(code::JSONErrorCode, error::Exception)
    return explicit_error_message(Base.Fix2(showerror, error), code)
end

function explicit_error_message(code::JSONErrorCode, msg::AbstractString)
    return explicit_error_message(Base.Fix2(print, msg), code)
end

@kwarg struct JSONRequest
    jsonrpc::String = "2.0"
    id::Union{Int, Nothing} = nothing
    method::String
    params::Any
end

@kwarg struct JSONSuccess
    jsonrpc::String = "2.0"
    id::Union{Int, Nothing} = nothing
    result::Any
end

@defaults struct JSONError
    code::Int
    message::String
    data::Maybe{StringDict} = nothing
end

function json_error(code::JSONErrorCode, info::Union{Exception, AbstractString})
    return JSONError(Int(code), explicit_error_message(code, info))
end

function json_error(code::JSONErrorCode, info::StructuredException)
    return JSONError(Int(code), "Structured Exception", info.data)
end

@kwarg struct JSONFailure
    jsonrpc::String = "2.0"
    id::Union{Int, Nothing} = nothing
    error::JSONError
end

macro return_failure(x)
    return quote
        local v = $(esc(x))
        v isa JSONFailure ? (return v) : v
    end
end

function parse_json(s::AbstractString)
    try
        JSON.parse(s)
    catch e
        error = json_error(parse_error, e)
        return JSONFailure(; error)
    end
end

function _get_request(d::AbstractDict)
    id = get(d, "id", nothing)
    # Ids are integers here, a narrowing of the spec's string-or-number. One that is not cannot
    # be echoed back, so the failure carries `null`, as the spec says for an undetectable id.
    # `Int` rather than `Integer`: `true` is an `Integer` and would be answered as id 1, and a
    # `BigInt` cannot be stored in the reply.
    if !(id isa Union{Int, Nothing})
        error = json_error(invalid_request, "`id` must be an integer")
        return JSONFailure(; error)
    end
    if get(d, "jsonrpc", nothing) != "2.0"
        error = json_error(invalid_request, "`jsonrpc` must be \"2.0\"")
        return JSONFailure(; id, error)
    end
    return try
        StructUtils.make(JSONRequest, d)
    catch e
        error = json_error(invalid_request, e)
        JSONFailure(; id, error)
    end
end

# An element of a batch that is not an object is a request of its own, and invalid.
function _get_request(::Any)
    error = json_error(invalid_request, "Pass an object as a request.")
    return JSONFailure(; error)
end

get_request(d::AbstractDict) = _get_request(d)

function get_request(v::AbstractVector)
    return if isempty(v)
        error = json_error(invalid_request, "Pass at least one request.")
        JSONFailure(; error)
    else
        map(_get_request, v)
    end
end

function get_request(_::Any)
    error = json_error(invalid_request, "Pass an object or list of objects as a request.")
    return JSONFailure(; error)
end

function get_method(handlers::AbstractDict, req::JSONRequest)
    return get(handlers, req.method) do
        error = json_error(method_not_found, "Method $(req.method) not found")
        JSONFailure(; req.id, error)
    end
end

function validate_method(method, req)
    return try
        method(req.params)
    catch e
        error = json_error(invalid_params, e)
        JSONFailure(; req.id, error)
    end
end

function handle_request(instance, req::JSONRequest, path::Maybe{AbstractString})
    return try
        result, writer = isnothing(path) ? (instance(), nothing) : instance(path)
        JSONSuccess(; req.id, result), writer
    catch e
        error = json_error(internal_error, e)
        JSONFailure(; req.id, error)
    end
end

function apply_handlers(handlers::AbstractDict, s::AbstractString, path::Maybe{AbstractString} = nothing)
    x = @return_failure parse_json(s)
    req = @return_failure get_request(x)
    # A streamed reply is one body, so a batch has nowhere to go.
    if req isa AbstractVector && !isnothing(path)
        error = json_error(invalid_request, "A streamed request cannot be a batch.")
        return JSONFailure(; error)
    end
    return isnothing(path) ? apply_handlers(handlers, req) : apply_handlers(handlers, req, path)
end

# An element of a batch that is not a valid request is answered in place, with its own failure.
apply_handlers(::AbstractDict, failure::JSONFailure) = failure

function apply_handlers(handlers::AbstractDict, req::JSONRequest, path::Maybe{AbstractString} = nothing)
    res = _apply_handlers(handlers, req, path)
    # A notification is never answered, whatever came of it.
    return isnothing(req.id) ? nothing : res
end

function _apply_handlers(handlers::AbstractDict, req::JSONRequest, path::Maybe{AbstractString})
    method = @return_failure get_method(handlers, req)
    instance = @return_failure validate_method(method, req)
    res, writer = @return_failure handle_request(instance, req, path)
    return isnothing(path) ? res : (res, writer)
end

function apply_handlers(handlers::AbstractDict, reqs::AbstractVector)
    res = map(Base.Fix1(apply_handlers, handlers), reqs)
    filtered_res = filter(!isnothing, res)
    return isempty(filtered_res) ? nothing : filtered_res
end

probe(x) = nothing

struct ProbedThunk{T, P}
    thunk::T
    probe::P
end

(p::ProbedThunk)(args...) = p.thunk(args...)

probe(p::ProbedThunk) = p.probe

struct ScopedThunk{T, P <: Tuple}
    thunk::T
    pairs::P
end

(s::ScopedThunk)(args...) = @with s.pairs... s.thunk(args...)

probe(s::ScopedThunk) = @with s.pairs... probe(s.thunk)

# Middleware

function apply_middleware(middleware, handlers::AbstractDict)
    handlers′ = StringDict(handlers)
    map!(middleware, values(handlers′))
    return handlers′
end

# Runs `handler` for validation but replaces thunk with a trivial `Returns(nothing)`
probe_middleware(handler) = Returns ∘ probe ∘ handler

struct ScopedMiddleware{T <: Tuple{Vararg{Pair}}}
    pairs::T
end

ScopedMiddleware(pairs::Pair...) = ScopedMiddleware(pairs)

(sm::ScopedMiddleware)(handler) = spec -> ScopedThunk(@with(sm.pairs..., handler(spec)), sm.pairs)
