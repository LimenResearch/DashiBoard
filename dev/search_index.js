var documenterSearchIndex = {"docs":
[{"location":"ui-guide/#UI-Guide","page":"UI Guide","title":"UI Guide","text":"","category":"section"},{"location":"ui-guide/#Home-screen","page":"UI Guide","title":"Home screen","text":"","category":"section"},{"location":"ui-guide/","page":"UI Guide","title":"UI Guide","text":"After opening the browser at the starting page (see Getting Started), you will be greeted by the following page.","category":"page"},{"location":"ui-guide/","page":"UI Guide","title":"UI Guide","text":"(Image: UI home page)","category":"page"},{"location":"ui-guide/#Loading-data","page":"UI Guide","title":"Loading data","text":"","category":"section"},{"location":"ui-guide/","page":"UI Guide","title":"UI Guide","text":"To load data, simply select one or more files from the \"Choose files\" dropdown.","category":"page"},{"location":"ui-guide/","page":"UI Guide","title":"UI Guide","text":"You will have access to all the files available in you data directory, provided that their format is supported. See also DataIngestion.is_supported.","category":"page"},{"location":"ui-guide/","page":"UI Guide","title":"UI Guide","text":"(Image: UI file selection)","category":"page"},{"location":"ui-guide/","page":"UI Guide","title":"UI Guide","text":"Upon pressing the Load button, the data is loaded in the Source table, displayed on the top right.","category":"page"},{"location":"ui-guide/","page":"UI Guide","title":"UI Guide","text":"(Image: loaded data)","category":"page"},{"location":"ui-guide/#Filtering-data","page":"UI Guide","title":"Filtering data","text":"","category":"section"},{"location":"ui-guide/","page":"UI Guide","title":"UI Guide","text":"The Filter tab allows users to filter their data. At the moment, we support checkboxes for categorical columns and min / max selectors for continuous ones.","category":"page"},{"location":"ui-guide/","page":"UI Guide","title":"UI Guide","text":"Upon clicking on Submit, the filtered data is loaded in the Selection table, displayed on the bottom right.","category":"page"},{"location":"ui-guide/","page":"UI Guide","title":"UI Guide","text":"(Image: filtered data)","category":"page"},{"location":"ui-guide/#Processing-data","page":"UI Guide","title":"Processing data","text":"","category":"section"},{"location":"ui-guide/","page":"UI Guide","title":"UI Guide","text":"Data is processed via cards, small building blocks that add new columns to the  filtered data.","category":"page"},{"location":"ui-guide/","page":"UI Guide","title":"UI Guide","text":"To add a new card, click on the ＋ and select the type of card you wish to add.","category":"page"},{"location":"ui-guide/","page":"UI Guide","title":"UI Guide","text":"(Image: adding a new card)","category":"page"},{"location":"ui-guide/","page":"UI Guide","title":"UI Guide","text":"You can add and compile as many cards as you wish.","category":"page"},{"location":"ui-guide/","page":"UI Guide","title":"UI Guide","text":"Upon clicking on Submit, the additional columns are added to the Selection table.","category":"page"},{"location":"ui-guide/","page":"UI Guide","title":"UI Guide","text":"(Image: processed data)","category":"page"},{"location":"lib/DataIngestion/#DataIngestion","page":"DataIngestion API","title":"DataIngestion","text":"","category":"section"},{"location":"lib/DataIngestion/","page":"DataIngestion API","title":"DataIngestion API","text":"CurrentModule = DataIngestion","category":"page"},{"location":"lib/DataIngestion/#Ingestion-interface","page":"DataIngestion API","title":"Ingestion interface","text":"","category":"section"},{"location":"lib/DataIngestion/","page":"DataIngestion API","title":"DataIngestion API","text":"DataIngestion.is_supported\nDataIngestion.load_files","category":"page"},{"location":"lib/DataIngestion/#DataIngestion.is_supported","page":"DataIngestion API","title":"DataIngestion.is_supported","text":"is_supported(file::AbstractString)\n\nDenote whether a file is of one of the available formats:\n\ncsv,\ntsv,\ntxt,\njson,\nparquet.\n\n\n\n\n\n","category":"function"},{"location":"lib/DataIngestion/#DataIngestion.load_files","page":"DataIngestion API","title":"DataIngestion.load_files","text":"load_files(\n    repository::Repository, files::AbstractVector{<:AbstractString},\n    [format::AbstractString];\n    schema = nothing,\n    union_by_name = true, kwargs...)\n)\n\nLoad files into a table called TABLE_NAMES.source inside repository.db within the schema schema (defaults to main schema).\n\nThe format is inferred or can be passed explicitly.\n\nThe following formats are supported:\n\ncsv,\ntsv,\ntxt,\njson,\nparquet.\n\nThe keyword arguments are forwarded to the reader for the given format.\n\n\n\n\n\n","category":"function"},{"location":"lib/DataIngestion/#Metadata-for-filter-generation","page":"DataIngestion API","title":"Metadata for filter generation","text":"","category":"section"},{"location":"lib/DataIngestion/","page":"DataIngestion API","title":"DataIngestion API","text":"DataIngestion.summarize","category":"page"},{"location":"lib/DataIngestion/#DataIngestion.summarize","page":"DataIngestion API","title":"DataIngestion.summarize","text":"summarize(repo::Repository, tbl::AbstractString; schema = nothing)\n\nCompute summaries of variables in table tbl within the database repo.db. The summary of a variable depends on its type, according to the following rules.\n\nCategorical variable => list of unique types.\nContinuous variable => extrema.\n\n\n\n\n\n","category":"function"},{"location":"lib/DataIngestion/#Filtering-interface","page":"DataIngestion API","title":"Filtering interface","text":"","category":"section"},{"location":"lib/DataIngestion/","page":"DataIngestion API","title":"DataIngestion API","text":"DataIngestion.AbstractFilter\nDataIngestion.get_filter\nDataIngestion.select","category":"page"},{"location":"lib/DataIngestion/#DataIngestion.AbstractFilter","page":"DataIngestion API","title":"DataIngestion.AbstractFilter","text":"abstract type AbstractFilter end\n\nAbstract supertype to encompass all possible filters.\n\nCurrent implementations:\n\nIntervalFilter,\nListFilter.\n\n\n\n\n\n","category":"type"},{"location":"lib/DataIngestion/#DataIngestion.get_filter","page":"DataIngestion API","title":"DataIngestion.get_filter","text":"get_filter(d::AbstractDict)\n\nGenerate an AbstractFilter based on a configuration dictionary.\n\n\n\n\n\n","category":"function"},{"location":"lib/DataIngestion/#DataIngestion.select","page":"DataIngestion API","title":"DataIngestion.select","text":"select(repo::Repository, filters::AbstractVector; schema = nothing)\n\nCreate a table with name TABLE_NAMES.selection within the database repo.db, where repo is a Repository. The table TABLE_NAMES.selection is filled with rows from the table TABLE_NAMES.source that are kept by the filters in filters.\n\nEach filter should be an instance of AbstractFilter.\n\n\n\n\n\n","category":"function"},{"location":"lib/DataIngestion/#Filters","page":"DataIngestion API","title":"Filters","text":"","category":"section"},{"location":"lib/DataIngestion/","page":"DataIngestion API","title":"DataIngestion API","text":"DataIngestion.IntervalFilter\nDataIngestion.ListFilter","category":"page"},{"location":"lib/DataIngestion/#DataIngestion.IntervalFilter","page":"DataIngestion API","title":"DataIngestion.IntervalFilter","text":"struct IntervalFilter{T} <: AbstractFilter\n    colname::String\n    interval::ClosedInterval{T}\nend\n\nObject to retain only those rows for which the variable colname lies inside the interval.\n\n\n\n\n\n","category":"type"},{"location":"lib/DataIngestion/#DataIngestion.ListFilter","page":"DataIngestion API","title":"DataIngestion.ListFilter","text":"struct ListFilter{T} <: AbstractFilter\n    colname::String\n    list::Vector{T}\nend\n\nObject to retain only those rows for which the variable colname belongs to a list of options.\n\n\n\n\n\n","category":"type"},{"location":"getting-started/#Getting-Started","page":"Getting Started","title":"Getting Started","text":"","category":"section"},{"location":"getting-started/","page":"Getting Started","title":"Getting Started","text":"DashiBoard is still in development, thus installing requires a few passages.","category":"page"},{"location":"getting-started/#Installation-dependencies","page":"Getting Started","title":"Installation dependencies","text":"","category":"section"},{"location":"getting-started/","page":"Getting Started","title":"Getting Started","text":"Julia programming language (minimum version 1.11, installable via juliaup).\nJavaScript package manager pnpm.","category":"page"},{"location":"getting-started/#Launching-the-server","page":"Getting Started","title":"Launching the server","text":"","category":"section"},{"location":"getting-started/","page":"Getting Started","title":"Getting Started","text":"Open a terminal at the top-level of the repository.","category":"page"},{"location":"getting-started/","page":"Getting Started","title":"Getting Started","text":"Install all required dependencies with the following command:","category":"page"},{"location":"getting-started/","page":"Getting Started","title":"Getting Started","text":"julia --project -e 'using Pkg; Pkg.add(Pkg.PackageSpec(name=\"DuckDB\", rev=\"main\")); Pkg.instantiate()'","category":"page"},{"location":"getting-started/","page":"Getting Started","title":"Getting Started","text":"Then, launch the server with the following command:","category":"page"},{"location":"getting-started/","page":"Getting Started","title":"Getting Started","text":"julia --project bin/launch.jl path/to/data","category":"page"},{"location":"getting-started/","page":"Getting Started","title":"Getting Started","text":"where path/to/data represents the data folder you wish to make accessible to DashiBoard.","category":"page"},{"location":"getting-started/#Launching-the-frontend","page":"Getting Started","title":"Launching the frontend","text":"","category":"section"},{"location":"getting-started/","page":"Getting Started","title":"Getting Started","text":"Open a terminal in the frontend folder.","category":"page"},{"location":"getting-started/","page":"Getting Started","title":"Getting Started","text":"Install all required dependencies with the following command:","category":"page"},{"location":"getting-started/","page":"Getting Started","title":"Getting Started","text":"pnpm install","category":"page"},{"location":"getting-started/","page":"Getting Started","title":"Getting Started","text":"Then, launch the frontend with the following command:","category":"page"},{"location":"getting-started/","page":"Getting Started","title":"Getting Started","text":"pnpm run start","category":"page"},{"location":"getting-started/","page":"Getting Started","title":"Getting Started","text":"To interact with the UI, open your browser and navigate to the page http://localhost:3000.","category":"page"},{"location":"lib/Pipelines/#Pipelines","page":"Pipelines API","title":"Pipelines","text":"","category":"section"},{"location":"lib/Pipelines/","page":"Pipelines API","title":"Pipelines API","text":"CurrentModule = Pipelines","category":"page"},{"location":"lib/Pipelines/","page":"Pipelines API","title":"Pipelines API","text":"Pipelines is a library designed to generate and evaluate data analysis pipelines.","category":"page"},{"location":"lib/Pipelines/#Transformation-interface","page":"Pipelines API","title":"Transformation interface","text":"","category":"section"},{"location":"lib/Pipelines/","page":"Pipelines API","title":"Pipelines API","text":"Pipelines.AbstractCard\nPipelines.train\nPipelines.evaluate\nPipelines.inputs\nPipelines.outputs","category":"page"},{"location":"lib/Pipelines/#Pipelines.AbstractCard","page":"Pipelines API","title":"Pipelines.AbstractCard","text":"abstract type AbstractCard end\n\nAbstract supertype to encompass all possible filters.\n\nCurrent implementations:\n\nRescaleCard,\nSplitCard,\nGLMCard.\n\n\n\n\n\n","category":"type"},{"location":"lib/Pipelines/#Pipelines.train","page":"Pipelines API","title":"Pipelines.train","text":"train(repo::Repository, card::AbstractCard, source; schema = nothing)\n\nReturn a trained model for a given card on a table table in the database repo.db.\n\n\n\n\n\n","category":"function"},{"location":"lib/Pipelines/#Pipelines.evaluate","page":"Pipelines API","title":"Pipelines.evaluate","text":"evaluate(repo::Repository, card::AbstractCard, m, (source, target)::Pair; schema = nothing)\n\nReplace table target in the database repo.db with the outcome of executing the card on the table source.\n\nHere, m represents the result of train(repo, card, source; schema). See also train.\n\n\n\n\n\n","category":"function"},{"location":"lib/Pipelines/#Pipelines.inputs","page":"Pipelines API","title":"Pipelines.inputs","text":"outputs(c::AbstractCard)\n\nReturn the list of outputs for a given card.\n\n\n\n\n\n","category":"function"},{"location":"lib/Pipelines/#Pipelines.outputs","page":"Pipelines API","title":"Pipelines.outputs","text":"inputs(c::AbstractCard)\n\nReturn the list of inputs for a given card.\n\n\n\n\n\n","category":"function"},{"location":"lib/Pipelines/#Pipeline-computation","page":"Pipelines API","title":"Pipeline computation","text":"","category":"section"},{"location":"lib/Pipelines/","page":"Pipelines API","title":"Pipelines API","text":"Pipelines.get_card\nPipelines.evaluate(repo::Repository, cards::AbstractVector, table::AbstractString; schema = nothing)","category":"page"},{"location":"lib/Pipelines/#Pipelines.get_card","page":"Pipelines API","title":"Pipelines.get_card","text":"get_card(d::AbstractDict)\n\nGenerate an AbstractCard based on a configuration dictionary.\n\n\n\n\n\n","category":"function"},{"location":"lib/Pipelines/#Pipelines.evaluate-Tuple{Repository, AbstractVector, AbstractString}","page":"Pipelines API","title":"Pipelines.evaluate","text":"evaluate(repo::Repository, cards::AbstractVector, table::AbstractString; schema = nothing)\n\nReplace table in the database repo.db with the outcome of executing all the transformations in cards.\n\n\n\n\n\n","category":"method"},{"location":"lib/Pipelines/#Cards","page":"Pipelines API","title":"Cards","text":"","category":"section"},{"location":"lib/Pipelines/","page":"Pipelines API","title":"Pipelines API","text":"Pipelines.RescaleCard\nPipelines.SplitCard\nPipelines.GLMCard","category":"page"},{"location":"lib/Pipelines/#Pipelines.RescaleCard","page":"Pipelines API","title":"Pipelines.RescaleCard","text":"struct RescaleCard <: AbstractCard\n    method::String\n    by::Vector{String} = String[]\n    columns::Vector{String}\n    suffix::String = \"rescaled\"\nend\n\nCard to rescale of one or more columns according to a given method. The supported methods are\n\nzscore,\nmaxabs,\nminmax,\nlog,\nlogistic.\n\nThe resulting rescaled variable is added to the table under the name \"$(originalname)_$(suffix)\". \n\n\n\n\n\n","category":"type"},{"location":"lib/Pipelines/#Pipelines.SplitCard","page":"Pipelines API","title":"Pipelines.SplitCard","text":"struct SplitCard <: AbstractCard\n    method::String\n    order_by::Vector{String}\n    by::Vector{String} = String[]\n    output::String\n    p::Float64 = NaN\n    tiles::Vector{Int} = Int[]\nend\n\nCard to split the data into two groups according to a given method.\n\nCurrently supported methods are\n\ntiles (requires tiles argument, e.g., tiles = [1, 1, 2, 1, 1, 2]),\npercentile (requires p argument, e.g. p = 0.9).\n\n\n\n\n\n","category":"type"},{"location":"lib/Pipelines/#Pipelines.GLMCard","page":"Pipelines API","title":"Pipelines.GLMCard","text":"struct GLMCard <: AbstractCard\n    predictors::Vector{Any} = Any[]\n    target::String\n    weights::Union{String, Nothing} = nothing\n    distribution::String = \"normal\"\n    link::Union{String, Nothing} = nothing\n    link_params::Vector{Any} = Any[]\n    suffix::String = \"hat\"\nend\n\nRun a GLM \n\n\n\n\n\n","category":"type"},{"location":"lib/StreamlinerCore/#StreamlinerCore","page":"StreamlinerCore API","title":"StreamlinerCore","text":"","category":"section"},{"location":"lib/StreamlinerCore/","page":"StreamlinerCore API","title":"StreamlinerCore API","text":"CurrentModule = StreamlinerCore","category":"page"},{"location":"lib/StreamlinerCore/","page":"StreamlinerCore API","title":"StreamlinerCore API","text":"StreamlinerCore is a julia library to generate, train and evaluate models defined via some configuration files.","category":"page"},{"location":"lib/StreamlinerCore/#Data-interface","page":"StreamlinerCore API","title":"Data interface","text":"","category":"section"},{"location":"lib/StreamlinerCore/","page":"StreamlinerCore API","title":"StreamlinerCore API","text":"StreamlinerCore.AbstractData\nStreamlinerCore.stream\nStreamlinerCore.ingest\nStreamlinerCore.get_templates\nStreamlinerCore.get_metadata\nStreamlinerCore.get_summary\nStreamlinerCore.get_nsamples\nStreamlinerCore.Template","category":"page"},{"location":"lib/StreamlinerCore/#StreamlinerCore.AbstractData","page":"StreamlinerCore API","title":"StreamlinerCore.AbstractData","text":"AbstactData{N}\n\nAbstract type representing streamers of N datasets. In general, StreamlinerCore will use N = 1 to validate and evaluate trained models and N = 2 to train models via a training and a validation datasets.\n\nSubtypes of AbstractData are meant to implement the following methods:\n\nstream,\nget_templates,\nget_metadata,\nget_summary (optional).\n\n\n\n\n\n","category":"type"},{"location":"lib/StreamlinerCore/#StreamlinerCore.stream","page":"StreamlinerCore API","title":"StreamlinerCore.stream","text":"stream(f, data::AbstractData, partition::Integer, streaming::Streaming)\n\nStream partition of data by batches of batchsize on a given device. Return the result of applying f on the resulting batch iterator. Shuffling is optional and controlled by shuffle (boolean) and by the random number generator rng.\n\nThe options device, batchsize, shuffle, rng are passed via the configuration struct streaming::Streaming. See also Streaming.\n\n\n\n\n\n","category":"function"},{"location":"lib/StreamlinerCore/#StreamlinerCore.ingest","page":"StreamlinerCore API","title":"StreamlinerCore.ingest","text":"ingest(data::AbstractData{1}, eval_stream, select)\n\nIngest output of evaluate into a suitable database, tensor or iterator. select determines which fields of the model output to keep.\n\n\n\n\n\n","category":"function"},{"location":"lib/StreamlinerCore/#StreamlinerCore.get_templates","page":"StreamlinerCore API","title":"StreamlinerCore.get_templates","text":"get_templates(data::AbstractData)\n\nExtract templates for data. Templates encode type and size of the arrays that data will stream. See also Template\n\n\n\n\n\n","category":"function"},{"location":"lib/StreamlinerCore/#StreamlinerCore.get_metadata","page":"StreamlinerCore API","title":"StreamlinerCore.get_metadata","text":"get_metadata(x)::Dict{String, Any}\n\nExtract metadata for x. metadata should be a dictionary of information that identifies x univoquely. After training, it will be stored in the MongoDB together. get_metadata has methods for AbstractData, Model, and Training.\n\n\n\n\n\n","category":"function"},{"location":"lib/StreamlinerCore/#StreamlinerCore.get_summary","page":"StreamlinerCore API","title":"StreamlinerCore.get_summary","text":"get_summary(data::AbstractData)::Dict{String, Any}\n\nExtract summary for data. summary should be a dictionary of summary statistics for data. Common choices of statistics to report are mean and standard deviation, as well as unique values for categorical variables.\n\n\n\n\n\n","category":"function"},{"location":"lib/StreamlinerCore/#StreamlinerCore.get_nsamples","page":"StreamlinerCore API","title":"StreamlinerCore.get_nsamples","text":"get_nsamples(data::AbstractData{N})::NTuple{N, Int} where {N}\n\nReturn number of samples for data.\n\n\n\n\n\n","category":"function"},{"location":"lib/StreamlinerCore/#StreamlinerCore.Template","page":"StreamlinerCore API","title":"StreamlinerCore.Template","text":"Template(::Type{T}, size::NTuple{N, Int}) where {T, N}\n\nCreate an object of type Template. It represents arrays with eltype T and size size. Note that size does not include the minibatch dimension.\n\n\n\n\n\n","category":"type"},{"location":"lib/StreamlinerCore/#Parser","page":"StreamlinerCore API","title":"Parser","text":"","category":"section"},{"location":"lib/StreamlinerCore/","page":"StreamlinerCore API","title":"StreamlinerCore API","text":"StreamlinerCore.Parser\nStreamlinerCore.default_parser","category":"page"},{"location":"lib/StreamlinerCore/#StreamlinerCore.Parser","page":"StreamlinerCore API","title":"StreamlinerCore.Parser","text":"Parser(;\n    model, layers, sigmas, aggregators, metrics, regularizations,\n    optimizers, schedules, stoppers, devices\n)\n\nCollection of dictionaries to performance the necessary conversion from the user-specified configuration file or dictionary to julia objects.\n\nFor most usecases, one should define a default parser\n\nparser = default_parser()\n\nand pass it to Model and Training upon construction.\n\nA parser object is also required to use interface functions that read from the MongoDB:\n\nfinetune,\nloadmodel,\nvalidate,\nevaluate.\n\nSee default_parser for more advanced uses.\n\n\n\n\n\n","category":"type"},{"location":"lib/StreamlinerCore/#StreamlinerCore.default_parser","page":"StreamlinerCore API","title":"StreamlinerCore.default_parser","text":"default_parser(; plugins::AbstractVector{Parser}=Parser[])\n\nReturn a parser::Parser object that includes StreamlinerCore defaults together with optional plugins.\n\n\n\n\n\n","category":"function"},{"location":"lib/StreamlinerCore/#Parsed-objects","page":"StreamlinerCore API","title":"Parsed objects","text":"","category":"section"},{"location":"lib/StreamlinerCore/","page":"StreamlinerCore API","title":"StreamlinerCore API","text":"StreamlinerCore.Model\nStreamlinerCore.Training\nStreamlinerCore.Streaming","category":"page"},{"location":"lib/StreamlinerCore/#StreamlinerCore.Model","page":"StreamlinerCore API","title":"StreamlinerCore.Model","text":"Model(parser::Parser, metadata::AbstractDict)\n\nModel(parser::Parser, path::AbstractString, [vars::AbstractDict])\n\nCreate a Model object from a configuration dictionary metadata or, alternatively, from a configuration dictionary stored at path in TOML format. The optional argument vars is a dictionary of variables the can be used to fill the template given in path.\n\nThe parser::Parser handles conversion from configuration variables to julia objects.\n\nGiven a model::Model object, use model(data) where data::AbstractData to instantiate the corresponding neural network or machine.\n\n\n\n\n\n","category":"type"},{"location":"lib/StreamlinerCore/#StreamlinerCore.Training","page":"StreamlinerCore API","title":"StreamlinerCore.Training","text":"Training(parser::Parser, metadata::AbstractDict)\n\nTraining(parser::Parser, path::AbstractString, [vars::AbstractDict])\n\nCreate a Training object from a configuration dictionary metadata or, alternatively, from a configuration dictionary stored at path in TOML format. The optional argument vars is a dictionary of variables the can be used to fill the template given in path.\n\nThe parser::Parser handles conversion from configuration variables to julia objects.\n\n\n\n\n\n","category":"type"},{"location":"lib/StreamlinerCore/#StreamlinerCore.Streaming","page":"StreamlinerCore API","title":"StreamlinerCore.Streaming","text":"Streaming(parser::Parser, metadata::AbstractDict)\n\nStreaming(parser::Parser, path::AbstractString, [vars::AbstractDict])\n\nCreate a Streaming object from a configuration dictionary metadata or, alternatively, from a configuration dictionary stored at path in TOML format. The optional argument vars is a dictionary of variables the can be used to fill the template given in path.\n\nThe parser::Parser handles conversion from configuration variables to julia objects.\n\n\n\n\n\n","category":"type"},{"location":"lib/StreamlinerCore/#Training-and-evaluation","page":"StreamlinerCore API","title":"Training and evaluation","text":"","category":"section"},{"location":"lib/StreamlinerCore/","page":"StreamlinerCore API","title":"StreamlinerCore API","text":"Result\ntrain\nfinetune\nloadmodel\nvalidate\nevaluate\nsummarize","category":"page"},{"location":"lib/StreamlinerCore/#StreamlinerCore.Result","page":"StreamlinerCore API","title":"StreamlinerCore.Result","text":"@kwdef struct Result{N, P, M<:Model}\n    model::M\n    prefix::P\n    uuid::UUID\n    iteration::Int\n    stats::NTuple{N, Vector{Float64}}\n    trained::Bool\n    resumed::Maybe{Bool} = nothing\n    successful::Maybe{Bool} = nothing\nend\n\nStructure to encode the result of train, finetune, or validate. Stores configuration of model, metrics, and information on the location of the model weights.\n\n\n\n\n\n","category":"type"},{"location":"lib/StreamlinerCore/#StreamlinerCore.train","page":"StreamlinerCore API","title":"StreamlinerCore.train","text":"train(\n    model::Model, data::AbstractData{2}, training::Training;\n    callback = default_callback, outputdir,\n    tempdir::AbstractString = Base.tempdir()\n)\n\nTrain model using the training configuration on data.\n\nThe keyword arguments are as follows.\n\noutputdir represents the path where StreamlinerCore saves model weights (can be local or remote).\ntempdir represents a folder where StreamlinerCore will store temporary data during training.\ncallback(m, trace) will be called after every epoch.\n\nThe arguments of callback work as follows.\n\nm is the instantiated neural network or machine,\ntrace is an object encoding additional information, i.e.,\nstats (average of metrics computed so far),\nmetrics (functions used to compute stats), and\niteration.\n\n\n\n\n\n","category":"function"},{"location":"lib/StreamlinerCore/#StreamlinerCore.finetune","page":"StreamlinerCore API","title":"StreamlinerCore.finetune","text":"finetune(\n    result::Result, data::AbstractData{2}, training::Training;\n    resume::Bool, callback = default_callback,\n    outputdir, tempdir::AbstractString = Base.tempdir()\n)\n\nLoad model encoded in result and retrain it using the training configuration on data. Use resume = true to restart training where it left off. Same other keyword arguments as train.\n\n\n\n\n\n","category":"function"},{"location":"lib/StreamlinerCore/#StreamlinerCore.loadmodel","page":"StreamlinerCore API","title":"StreamlinerCore.loadmodel","text":"loadmodel(model::Model, data::AbstractData, device)\n\nLoad model encoded in model on the device. The object data is required as the model can only be initialized once the data dimensions are known.\n\n\n\n\n\nloadmodel(result::Result, data::AbstractData, device)\n\nLoad model encoded in result on the device. The object data is required as the model can only be initialized once the data dimensions are known.\n\nwarning: Warning\nIt is recommended to call has_weights beforehand. Only call loadmodel if has_weights(result) returns true.\n\n\n\n\n\n","category":"function"},{"location":"lib/StreamlinerCore/#StreamlinerCore.validate","page":"StreamlinerCore API","title":"StreamlinerCore.validate","text":"validate(result::Result, data::AbstractData{1}, streaming::Streaming)\n\nLoad model encoded in result and validate it on data.\n\n\n\n\n\n","category":"function"},{"location":"lib/StreamlinerCore/#StreamlinerCore.evaluate","page":"StreamlinerCore API","title":"StreamlinerCore.evaluate","text":"evaluate(\n        device_m, data::AbstractData{1}, streaming::Streaming,\n        select::SymbolTuple = (:prediction,)\n    )\n\nEvaluate model device_m on data using streaming options streaming.\n\n\n\n\n\nevaluate(\n    result::Result, data::AbstractData{1}, streaming::Streaming,\n    select::SymbolTuple = (:prediction,)\n)\n\nLoad model encoded in result and evaluate it on data.\n\n\n\n\n\n","category":"function"},{"location":"lib/StreamlinerCore/#StreamlinerCore.summarize","page":"StreamlinerCore API","title":"StreamlinerCore.summarize","text":"summarize(io::IO, model::Model, data::AbstractData, training::Training)\n\nDisplay summary information concerning model (structure and number of parameters) and data (number of batches and size of each batch).\n\n\n\n\n\n","category":"function"},{"location":"lib/StreamlinerCore/#Utilities","page":"StreamlinerCore API","title":"Utilities","text":"","category":"section"},{"location":"lib/StreamlinerCore/","page":"StreamlinerCore API","title":"StreamlinerCore API","text":"StreamlinerCore.has_weights","category":"page"},{"location":"lib/StreamlinerCore/#StreamlinerCore.has_weights","page":"StreamlinerCore API","title":"StreamlinerCore.has_weights","text":"has_weights(result::Result)\n\nReturn true if result is a successful training result, false otherwise.\n\n\n\n\n\n","category":"function"},{"location":"#Overview-of-DashiBoard","page":"Overview","title":"Overview of DashiBoard","text":"","category":"section"},{"location":"","page":"Overview","title":"Overview","text":"DashiBoard is a data visualization GUI written in the Julia programming language.","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"The backend is powered by three libraries:","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"DuckDBUtils,\nDataIngestion,\nPipelines,\nStreamlinerCore.","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"The frontend is powered by SolidJS.","category":"page"},{"location":"","page":"Overview","title":"Overview","text":"To see how to get started, proceed to the next section.","category":"page"},{"location":"lib/DuckDBUtils/#DuckDBUtils","page":"DuckDBUtils API","title":"DuckDBUtils","text":"","category":"section"},{"location":"lib/DuckDBUtils/","page":"DuckDBUtils API","title":"DuckDBUtils API","text":"CurrentModule = DuckDBUtils","category":"page"},{"location":"lib/DuckDBUtils/#Database-interface","page":"DuckDBUtils API","title":"Database interface","text":"","category":"section"},{"location":"lib/DuckDBUtils/","page":"DuckDBUtils API","title":"DuckDBUtils API","text":"Repository\nget_catalog\nacquire_connection\nrelease_connection\nwith_connection\nrender_params\nto_sql","category":"page"},{"location":"lib/DuckDBUtils/#DuckDBUtils.Repository","page":"DuckDBUtils API","title":"DuckDBUtils.Repository","text":"Repository(db::DuckDB.DB)\n\nConstruct a Repository object that holds a DuckDB.DB as well as a pool of connections.\n\nUse DBInterface.(f::Base.Callable, repo::Repository, sql::AbstractString, [params]) to run a function on the result of a query sql on an available connection in the pool.\n\n\n\n\n\n","category":"type"},{"location":"lib/DuckDBUtils/#DuckDBUtils.get_catalog","page":"DuckDBUtils API","title":"DuckDBUtils.get_catalog","text":"get_catalog(repo::Repository; schema = nothing)\n\nExtract the catalog of available tables from a Repository repo.\n\n\n\n\n\n","category":"function"},{"location":"lib/DuckDBUtils/#DuckDBUtils.acquire_connection","page":"DuckDBUtils API","title":"DuckDBUtils.acquire_connection","text":"acquire_connection(repo::Repository)\n\nAcquire an open connection to the database repo.db from the pool repo.pool. See also release_connection.\n\nnote: Note\nA command con = acquire_connection(repo) must always be followed by a matching command release_connection(repo, con) (after the connection has been used).\n\n\n\n\n\n","category":"function"},{"location":"lib/DuckDBUtils/#DuckDBUtils.release_connection","page":"DuckDBUtils API","title":"DuckDBUtils.release_connection","text":"release_connection(repo::Repository, con)\n\nRelease connection con to the pool repo.pool\n\n\n\n\n\n","category":"function"},{"location":"lib/DuckDBUtils/#DuckDBUtils.with_connection","page":"DuckDBUtils API","title":"DuckDBUtils.with_connection","text":"with_connection(f, repo::Repository, [N])\n\nAcquire a connection con from the pool repo.pool. Then, execute f(con) and release the connection to the pool. An optional parameter N can be passed to determine the number of connections to be acquired (defaults to 1).\n\n\n\n\n\n","category":"function"},{"location":"lib/DuckDBUtils/#DuckDBUtils.render_params","page":"DuckDBUtils API","title":"DuckDBUtils.render_params","text":"render_params(catalog::SQLCatalog, node::SQLNode, params = (;))\n\nReturn query string and parameter list from query expressed as node.\n\n\n\n\n\n","category":"function"},{"location":"lib/DuckDBUtils/#DuckDBUtils.to_sql","page":"DuckDBUtils API","title":"DuckDBUtils.to_sql","text":"to_sql(x)\n\nConvert a julia value x to its SQL representation.\n\n\n\n\n\n","category":"function"},{"location":"lib/DuckDBUtils/#Table-tools","page":"DuckDBUtils API","title":"Table tools","text":"","category":"section"},{"location":"lib/DuckDBUtils/","page":"DuckDBUtils API","title":"DuckDBUtils API","text":"with_table\ncolnames","category":"page"},{"location":"lib/DuckDBUtils/#DuckDBUtils.with_table","page":"DuckDBUtils API","title":"DuckDBUtils.with_table","text":"with_table(f, repo::Repository, table; schema = nothing)\n\nRegister a table under a random unique name name, apply f(name), and then unregister the table.\n\n\n\n\n\n","category":"function"},{"location":"lib/DuckDBUtils/#DuckDBUtils.colnames","page":"DuckDBUtils API","title":"DuckDBUtils.colnames","text":"colnames(repo::Repository, table::AbstractString; schema = nothing)\n\nReturn list of columns for a given table.\n\n\n\n\n\n","category":"function"},{"location":"lib/DuckDBUtils/#Batched-iteration","page":"DuckDBUtils API","title":"Batched iteration","text":"","category":"section"},{"location":"lib/DuckDBUtils/","page":"DuckDBUtils API","title":"DuckDBUtils API","text":"Batches","category":"page"},{"location":"lib/DuckDBUtils/#DuckDBUtils.Batches","page":"DuckDBUtils API","title":"DuckDBUtils.Batches","text":"struct Batches{T}\n    chunks::T\n    batchsize::Int\n    nrows::Int\nend\n\nLet chunks be a partitioned table with nrows in total. Then, return an iterator of column-based tables with batchsize rows each.\n\nnote: Note\nchunks can in general be obtained as the output of Tables.partitions.\n\n\n\n\n\n","category":"type"},{"location":"lib/DuckDBUtils/#Internal-functions","page":"DuckDBUtils API","title":"Internal functions","text":"","category":"section"},{"location":"lib/DuckDBUtils/","page":"DuckDBUtils API","title":"DuckDBUtils API","text":"DuckDBUtils._numobs\nDuckDBUtils._init\nDuckDBUtils._append!\nDuckDBUtils.in_schema","category":"page"},{"location":"lib/DuckDBUtils/#DuckDBUtils._numobs","page":"DuckDBUtils API","title":"DuckDBUtils._numobs","text":"_numobs(cols)\n\nCompute the number of rows of a column-based table cols.\n\n\n\n\n\n","category":"function"},{"location":"lib/DuckDBUtils/#DuckDBUtils._init","page":"DuckDBUtils API","title":"DuckDBUtils._init","text":"_init(cols)\n\nInitialize an empty table with the same schema as the column-based table cols.\n\n\n\n\n\n","category":"function"},{"location":"lib/DuckDBUtils/#DuckDBUtils._append!","page":"DuckDBUtils API","title":"DuckDBUtils._append!","text":"_append!(batch::AbstractDict, cols, rg = Colon())\n\nAppend rows rg of column-based table cols to the dict table batch.\n\n\n\n\n\n","category":"function"},{"location":"lib/DuckDBUtils/#DuckDBUtils.in_schema","page":"DuckDBUtils API","title":"DuckDBUtils.in_schema","text":"in_schema(name::AbstractString, schema::Union{AbstractString, Nothing})\n\nUtility to create a name to refer to a table within the schema.\n\nFor instance\n\njulia> print(in_schema(\"tbl\", nothing))\n\"tbl\"\njulia> print(in_schema(\"tbl\", \"schm\"))\n\"schm\".\"tbl\"\n\n\n\n\n\n","category":"function"}]
}
