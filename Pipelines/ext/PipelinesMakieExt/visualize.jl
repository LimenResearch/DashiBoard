function Pipelines.visualize(
        repo::Repository,
        card::StreamlinerCard,
        state::CardState
    )

    # TODO: create richer visualization and test
    stats = jldopen(IOBuffer(state.content)) do file
        file["stats"]
    end

    fig = Figure()
    ax = Axis(fig[1, 1], title = "Loss")
    lines!(ax, stats[1, 1, :], label = "Training")
    lines!(ax, stats[1, 2, :], label = "Validation")
    axislegend(ax)
    return fig
end
