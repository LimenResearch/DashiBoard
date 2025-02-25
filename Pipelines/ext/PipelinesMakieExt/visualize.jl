function Pipelines.visualize(
        repo::Repository,
        card::StreamlinerCard,
        state::CardState
    )

    fig = Figure()
    ax = Axis(fig[1, 1])
    scatter!(ax, rand(10), rand(10))
    return fig
end
