# Regenerates `card-ir.json`, the payload the UI tests render against.
#
#   julia --project=DashiBoard dashiboard-ui/src/fixtures/card-ir.regenerate.jl
#
# Run it whenever the IR changes shape in `DashiBase`/`Pipelines`. It exists because a fixture
# captured by hand drifts from the route in ways the tests cannot see: the first regeneration
# written as an inline command dropped `omit_null = true` (so every unset field came back as an
# explicit `null`, which is not what any client ever receives) and omitted the `trivial` wild card
# (which `DashiBoard/test/dashiboard.jl` registers, and which is why the suite expects ten types).
#
# Everything below mirrors `DashiBoard.get_card_ir` — same `VariableConfig`, same `omit_null`. The
# vocabularies are the ones the DashiBoard test server serves: the pollution dataset's columns, the
# `weather` group and the two nodes in `DashiBoard/test/static/pipeline.json`.

using Pipelines, JSON

# The `trivial` wild card, verbatim from `DashiBoard/test/dashiboard.jl`. A `WildCard` is registered
# by the *host*, not by Pipelines, so without this the fixture describes nine card types and the UI
# would never see how a registered wild card renders.
Pipelines._train(wc::Pipelines.WildCard{:trivial}, t, id_var) = nothing
function (wc::Pipelines.WildCard{:trivial})(model, t, id_var)
    id = t[id_var]
    nrows = length(id)
    return Dict(id_var => id, (k => zeros(nrows) for k in wc.outputs)...)
end
Pipelines.register_wild_card(
    :trivial, "Trivial";
    settings = Pipelines.WildCardSettings(
        needs_order = false,
        needs_targets = false,
        allows_partition = false,
        allows_weights = false,
    )
)

variable_config = Pipelines.VariableConfig(
    cols = ["No", "year", "month", "day", "hour", "pm2.5", "DEWP", "TEMP", "PRES", "cbwd", "Iws", "Is", "Ir"],
    groups = ["weather"],
    nodes = ["rescale", "split"],
)

defs = Pipelines.ir_definitions(variable_config)
cards = Dict{String, Any}(k => Pipelines.card_ir(k) for k in keys(Pipelines.CARD_SPECS))

# `omit_null = true` is the route's own setting, and it is load-bearing rather than cosmetic: the IR
# uses `nothing` for "the type declares no default", and a serialised `null` turns that absence into
# a present value. `defaultsFor` then hands a card `{type: null}` instead of leaving it unset.
path = joinpath(@__DIR__, "card-ir.json")
open(path, "w") do io
    JSON.json(io, (; defs, cards); omit_null = true)
end
@info "wrote $path" cards = length(cards)
