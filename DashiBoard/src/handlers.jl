function get_acceptable_paths(req::HTTP.Request)
    _ = json_read(req)
    files = collect(String, acceptable_paths())
    return json_response(files)
end

function load_files(req::HTTP.Request)
    spec = json_read(req)
    DataIngestion.load_files(REPOSITORY[], spec)
    summaries = DataIngestion.summarize(REPOSITORY[], "source")
    return json_response(summaries)
end

function get_card_widgets(req::HTTP.Request)
    spec = json_read(req)
    configs = Pipelines.card_widgets(spec)
    return json_response(configs)
end

"""
    get_card_ir(req)

Serve the renderer's artefact: the IR for every registered card, plus the shared `\$defs` once
in the envelope rather than duplicated per card. The schema path (`get-card-widgets` today) is
unchanged — these are the two artefacts of one traversal, §13.
"""
function get_card_ir(req::HTTP.Request)
    spec = json_read(req)
    variables = collect(String, get(spec, "variables", String[]))
    defs = Pipelines.ir_definitions(variables)
    cards = Dict{String, Any}(k => Pipelines.card_ir(k) for k in keys(Pipelines.CARD_SPECS))
    return json_response((; defs, cards); omit_null = true)
end

function evaluate_pipeline(req::HTTP.Request)
    spec = json_read(req)
    filters = Filter.(spec["filters"])
    cards = Card.(spec["cards"])
    nodes = Pipelines.Node.(cards)

    orig = From("source") |> Partition() |> Define(ID_VAR[] => Agg.row_number())
    DataIngestion.select(REPOSITORY[], filters, orig => "selection")
    p = Pipelines.train_evaljoin!(REPOSITORY[], nodes, "selection", ID_VAR[])

    report = Pipelines.report(REPOSITORY[], nodes)
    vs = Pipelines.visualize(REPOSITORY[], nodes)
    visualization = stringify_visualization.(vs)
    graph = sprint(Pipelines.graphviz, p)
    summaries = DataIngestion.summarize(REPOSITORY[], "selection")
    return json_response((; summaries, visualization, graph, report))
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

        stream_data(
            stream, path, "application/json";
            pre = "{\"values\":", post = string(",\"length\":", nrows, "}")
        )
    end
    return
end

function get_processed_data(stream::HTTP.Stream)
    mktempdir() do dir
        path = joinpath(dir, "processed-data.csv")
        export_table(REPOSITORY[], From("selection"), path)
        stream_data(stream, path, "text/csv")
    end
    return
end
