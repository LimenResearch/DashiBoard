using Documenter
using DataIngestion, Pipelines

makedocs(
    sitename = "DashiBoard",
    format = Documenter.LaTeX(),
    authors = "Pietro Vertechi",
    modules = [DataIngestion, Pipelines],
    pages = [
        "Overview" => "index.md",
        "Getting Started" => "getting-started.md",
        "UI Guide" => "ui-guide.md",
        "DataIngestion API" => "DataIngestion.md",
        "Pipelines API" => "Pipelines.md",
    ]
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
deploydocs(
    repo = "github.com/LimenResearch/DashiBoard.git",
)
