function get_acceptable_paths(stream::HTTP.Stream)
    _ = json_read(stream)
    files = collect(String, acceptable_paths())
    json_write(stream, files)
    return
end

function load_files(stream::HTTP.Stream)
    spec = json_read(stream)
    DataIngestion.load_files(REPOSITORY[], spec)
    summaries = DataIngestion.summarize(REPOSITORY[], "source")
    json_write(stream, summaries)
    return
end

function get_card_configurations(stream::HTTP.Stream)
    spec = json_read(stream)
    configs = Pipelines.card_configurations(spec)
    json_write(stream, configs)
    return
end

function evaluate_pipeline(stream::HTTP.Stream)
    spec = json_read(stream)
    filters = Filter.(spec["filters"])
    cards = Card.(spec["cards"])
    nodes = Pipelines.Node.(cards)
    DataIngestion.select(REPOSITORY[], filters)
    g, vars = Pipelines.train_evaluate!(REPOSITORY[], nodes, "selection")

    report = Pipelines.report(REPOSITORY[], nodes) |> jsonify
    vs = Pipelines.visualize(REPOSITORY[], nodes)
    visualization = stringify_visualization.(vs)
    graph = sprint(Pipelines.graphviz, g, nodes, vars)
    summaries = DataIngestion.summarize(REPOSITORY[], "selection")
    json_write(stream, (; summaries, visualization, graph, report))
    return
end

struct Sorter
    colname::String
    sort::SQLNode
end

const ASC_DICT = Dict("asc" => Asc(), "desc" => Desc())

Sorter(d::AbstractDict) = Sorter(d["colId"], ASC_DICT[d["sort"]])

function fetch_data(stream::HTTP.Stream)
    spec = json_read(stream)
    table = spec["processed"] ? "selection" : "source"
    ns = Set{String}(colnames(REPOSITORY[], table))
    limit::Int, offset::Int = spec["limit"], spec["offset"]
    sort_model::Vector = get(spec, "sortModel", [])
    sorters = Sorter.(sort_model)
    sorter_nodes = [Get(s.colname) |> s.sort for s in sorters if s.colname in ns]

    mktempdir() do dir
        path = joinpath(dir, "data.json")
        q = From(table) |> Order(by = sorter_nodes) |> Limit(; limit, offset)
        export_table(
            REPOSITORY[], q, path;
            format = "json", array = true
        )

        nrows = DBInterface.execute(
            to_nrow,
            REPOSITORY[],
            From(table) |> Group() |> Select("Count" => Agg.count())
        )

        HTTP.setheader(stream, "Content-Type" => "application/json")
        startwrite(stream)

        print(stream, "{\"values\": ")
        stream_file(stream, path)
        print(stream, " , \"length\": ", nrows, "}")
    end
    return
end

function get_processed_data(stream::HTTP.Stream)
    mktempdir() do dir
        path = joinpath(dir, "processed-data.csv")
        export_table(REPOSITORY[], From("selection"), path)

        HTTP.setheader(stream, "Content-Type" => "text/csv")
        HTTP.setheader(stream, "Transfer-Encoding" => "chunked")
        HTTP.setheader(stream, "Content-Length" => string(filesize(path)))

        startwrite(stream)
        stream_file(stream, path)
    end
    return
end
