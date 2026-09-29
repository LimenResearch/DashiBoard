function Pipelines.visualize(
        repo::Repository,
        card::StreamlinerCard,
        (; stats)
    )

    # TODO: create richer visualization and test
    fig = Figure()
    ax = Axis(fig[1, 1], title = "Loss")
    lines!(ax, stats[1, 1, :], label = "Training")
    lines!(ax, stats[1, 2, :], label = "Validation")
    axislegend(ax)
    return fig
end
