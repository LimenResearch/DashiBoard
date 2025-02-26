using Documenter
using DuckDBUtils, DataIngestion, Pipelines, StreamlinerCore

makedocs(
    sitename = "DashiBoard",
    format = Documenter.HTML(),
    modules = [DuckDBUtils, DataIngestion, Pipelines, StreamlinerCore],
    pages = [
        "Overview" => "index.md",
        "Getting Started" => "getting-started.md",
        "UI Guide" => "ui-guide.md",
        "Deep Learning Guide" => "dl-guide.md",
        "DuckDBUtils API" => "lib/DuckDBUtils.md",
        "DataIngestion API" => "lib/DataIngestion.md",
        "Pipelines API" => "lib/Pipelines.md",
        "StreamlinerCore API" => "lib/StreamlinerCore.md",
    ]
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
deploydocs(
    repo = "github.com/LimenResearch/DashiBoard.git",
)
