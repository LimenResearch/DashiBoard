using Documenter
using DataIngestion, Pipelines

makedocs(
    sitename = "DashiBoard",
    format = Documenter.HTML(inventory_version = v"1.0.0-DEV"),
    modules = [DataIngestion, Pipelines],
    pages = [
            "Overview" => "index.md",
            ]
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
deploydocs(
    repo = "github.com/LimenResearch/DashiBoard.git",
)