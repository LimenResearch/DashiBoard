function list_handler(stream::HTTP.Stream)
    _ = json_read(stream)
    files = collect(String, acceptable_paths())
    json_write(stream, files)
    return
end

function load_handler(stream::HTTP.Stream)
    spec = json_read(stream)
    DataIngestion.load_files(REPOSITORY[], spec)
    summaries = DataIngestion.summarize(REPOSITORY[], "source")
    json_write(stream, summaries)
    return
end

function card_configurations_handler(stream::HTTP.Stream)
    spec = json_read(stream)
    configs = Pipelines.card_configurations(spec)
    json_write(stream, configs)
    return
end

function pipeline_handler(stream::HTTP.Stream)
    spec = json_read(stream)
    filters = Filter.(spec["filters"])
    cards = Card.(spec["cards"])
    DataIngestion.select(REPOSITORY[], filters)
    nodes = Pipelines.evaluate(REPOSITORY[], cards, "selection")
    report = Pipelines.report(REPOSITORY[], nodes) |> jsonify
    vs = Pipelines.visualize(REPOSITORY[], nodes)
    visualization = stringify_visualization.(vs)
    summaries = DataIngestion.summarize(REPOSITORY[], "selection")
    json_write(stream, (; summaries, visualization, report))
    return
end

function fetch_handler(stream::HTTP.Stream)
    spec = json_read(stream)
    table = spec["processed"] ? "selection" : "source"
    limit::Int, offset::Int = spec["limit"], spec["offset"]

    mktempdir() do dir
        path = joinpath(dir, "data.json")
        DBInterface.execute(
            Returns(nothing),
            REPOSITORY[],
            """
            COPY (FROM "$table" LIMIT \$limit OFFSET \$offset)
            TO '$path' (FORMAT json, ARRAY true);
            """,
            (; limit, offset)
        )
        nrows = DBInterface.execute(
            x -> only(x).count,
            REPOSITORY[],
            """
            SELECT count(*) AS "count" FROM "$table";
            """
        )

        HTTP.setheader(stream, "Content-Type" => "application/json")
        startwrite(stream)

        print(stream, "{\"values\": ")
        stream_file(stream, path)
        print(stream, " , \"length\": ", nrows, "}")
    end
    return
end

function processed_data_handler(stream::HTTP.Stream)
    mktempdir() do dir
        path = joinpath(dir, "processed-data.csv")
        export_table(REPOSITORY[], path)

        HTTP.setheader(stream, "Content-Type" => "text/csv")
        HTTP.setheader(stream, "Transfer-Encoding" => "chunked")
        HTTP.setheader(stream, "Content-Length" => string(filesize(path)))

        startwrite(stream)
        stream_file(stream, path)
    end
    return
end
