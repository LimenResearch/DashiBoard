const ALLOWED_ORIGINS = ["Access-Control-Allow-Origin" => "*"]

const CORS_HEADERS = [
    ALLOWED_ORIGINS...,
    "Access-Control-Allow-Headers" => "*",
    "Access-Control-Allow-Methods" => "GET, POST",
]

function CorsHandler(handle)
    return function (req::HTTP.Request)
        # return headers on OPTIONS request
        if HTTP.method(req) == "OPTIONS"
            return HTTP.Response(200, CORS_HEADERS)
        else
            r = handle(req)
            append!(r.headers, ALLOWED_ORIGINS)
            return r
        end
    end
end

function acceptable_files(data_directory)
    return Iterators.flatmap(walkdir(data_directory)) do (root, _, files)
        rel_root = relpath(root, data_directory)
        return (normpath(rel_root, file) for file in files if is_supported(file))
    end
end

function stream_file(stream::IO, path::AbstractString, chunksize::Integer)
    buffer = Vector{UInt8}(undef, chunksize)
    open(path, "r") do io
        while !eof(io)
            n = readbytes!(io, buffer)
            write(stream, view(buffer, 1:n))
        end
    end
end

function stream_data(
        stream::HTTP.Stream,
        repository::Repository,
        path::AbstractString;
        chunksize::Integer = 2^12,
        schema::Union{AbstractString, Nothing} = nothing
    )

    export_table(repository, path; schema)

    HTTP.setheader(stream, "Content-Type" => "text/csv")
    HTTP.setheader(stream, "Transfer-Encoding" => "chunked")
    HTTP.setheader(stream, "Content-Length" => filesize(path))

    startwrite(stream)
    stream_file(stream, path, chunksize)
    closewrite(stream)
end

function launch(
        data_directory;
        host = "127.0.0.1",
        port = 8080,
        async = false,
        training_directory,
        model_directory,
    )

    # TODO: clarify `post` vs `get`
    @post "/list" function (req::HTTP.Request)
        files = collect(String, acceptable_files(data_directory))
        return JSON3.write(files)
    end

    @post "/load" function (req::HTTP.Request)
        spec = json(req)
        files = joinpath.(data_directory, spec["files"])
        DataIngestion.load_files(REPOSITORY[], files)
        summaries = DataIngestion.summarize(REPOSITORY[], "source")
        return JSON3.write(summaries)
    end

    @post "/card-configurations" function (req::HTTP.Request)
        spec = json(req) |> to_config
        configs = @with(
            Pipelines.PARSER => Pipelines.default_parser(),
            Pipelines.MODEL_DIR => model_directory,
            Pipelines.TRAINING_DIR => training_directory,
            Pipelines.card_configurations(; spec...)
        )
        return JSON3.write(configs)
    end

    @post "/pipeline" function (req::HTTP.Request)
        spec = json(req)
        filters = get_filter.(spec["filters"])
        cards = get_card.(spec["cards"])
        DataIngestion.select(REPOSITORY[], filters)
        Pipelines.evaluate(REPOSITORY[], cards, "selection")
        summaries = DataIngestion.summarize(REPOSITORY[], "selection")
        return JSON3.write(summaries)
    end

    @post "/fetch" function (req::HTTP.Request)
        spec = json(req)
        table = spec["processed"] ? "selection" : "source"
        io = IOBuffer()
        print(io, "{\"values\": ")
        DBInterface.execute(
            x -> arraytable(io, Tables.columns(x)),
            REPOSITORY[],
            "FROM $table LIMIT ? OFFSET ?;",
            [spec["limit"], spec["offset"]]
        )
        count = DBInterface.execute(
            first,
            REPOSITORY[],
            "SELECT count(*) AS nrows FROM $table;"
        )
        print(io, " , \"length\": ", count.nrows, "}")
        return String(take!(io))
    end

    @stream "/processed-data" function (stream::HTTP.Stream)
        mktempdir() do dir
            path = joinpath(dir, "processed-data.csv")
            stream_data(stream, REPOSITORY[], path)
        end
    end

    serve(; middleware = [CorsHandler], host, port, async)
end
