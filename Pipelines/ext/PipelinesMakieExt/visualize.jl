function Pipelines._visualize(nodes::AbstractVector)
    fig = Figure()
    ax = Axis(fig[1, 1])
    scatter!(ax, rand(10), rand(10))
    return fig
end