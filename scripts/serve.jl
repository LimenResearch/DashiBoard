using HTTP, Pipelines, Oxygen

@post "/" function(req::HTTP.Request)
    query = json(req, Pipelines.Query)
    return sprint(Pipelines.print_query, query)
end

serve()
