push!(LOAD_PATH, dirname(@__DIR__))

using Documenter
using StreamlinerCore

makedocs(
    sitename = "StreamlinerCore",
    format = Documenter.HTML(prettyurls = get(ENV, "CI", nothing) == "true"),
    modules = [StreamlinerCore],
    pages = [
        "Overview" => "index.md",
        "Reference" => "reference.md",
    ],
    checkdocs = :none
)
