# Point the repository at a throwaway directory *before* DashiBoard loads: its `__init__`
# opens a DuckDB file, and the default scratchspace path is shared with any running server,
# whose lock would make this suite unloadable.
ENV["DASHIBOARD_CACHE"] = mktempdir()

include("dashiboard.jl")

include("../../DuckDBUtils/test/runtests.jl")
include("../../DataIngestion/test/runtests.jl")
include("../../Pipelines/test/runtests.jl")
include("../../StreamlinerCore/test/runtests.jl")
