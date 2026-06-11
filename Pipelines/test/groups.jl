d = JSON.parsefile(joinpath(@__DIR__, "static", "configs", "groups.json"))
nodes = Node.(d)
