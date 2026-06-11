function get_groups(n::Node)
    grps = n.groups
    return isempty(grps) ? Dict(n.label => Colon()) : grps
end

extract_group(n::Node, ::Colon) = get_node_outputs(n)

function _get_input_groups(d::AbstractDict)
    return if length(d) == 1 && only(keys(d)) == "-s"
        String[d["-s"]]
    else
        reduce(vcat, [_get_input_groups(v) for v in values(d)])
    end
end

function _get_input_groups(v::AbstractVector)
    nested_groups::Vector{Vector{String}} = _get_input_groups.(v)
    return reduce(vcat, nested_groups)
end

_get_input_groups(x::Any) = String[]

get_input_groups(d::AbstractDict) = _get_input_groups(d)

function get_output_groups(d::AbstractDict)
    grps = get(d, "groups", StringDict())
    return collect(String, keys(grps))
end

function parse_nodes_with_groups(ds::AbstractVector)
    N = length(ds)
    nodes = similar(Vector{Node}, N)
    eg = EnrichedDiGraph(get_input_groups, get_output_groups, ds)
    groups = StringDict()
    for i in topological_sort(eg.g)
        i ≤ N || continue
        d = apply_helpers(ds[i], groups; recursive = 0)
        node = Node(d)
        nodes[i] = node
        for (k, v) in get_groups(node)
            groups[k] = v
        end
    end
    return nodes, groups
end
