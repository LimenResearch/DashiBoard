const SPLIT_SPEC = CardSpec(
    type = SplitCard,
    label = "Split",
    needs_order = true,
    needs_targets = false,
    allows_weights = false,
    allows_partition = false
)

const WINDOW_FUNCTION_SPEC = CardSpec(
    type = WindowFunctionCard,
    label = "Window Function",
    needs_order = true,
    needs_targets = false,
    allows_weights = false,
    allows_partition = false
)

const RESCALE_SPEC = CardSpec(
    type = RescaleCard,
    label = "Rescale",
    needs_order = false,
    needs_targets = false,
    allows_weights = false,
    allows_partition = true
)

const CLUSTER_SPEC = CardSpec(
    type = ClusterCard,
    label = "Cluster",
    needs_order = false,
    needs_targets = false,
    allows_weights = true,
    allows_partition = true
)

const DIMENSIONALITY_REDUCTION_SPEC = CardSpec(
    type = DimensionalityReductionCard,
    label = "Dimensionality Reduction",
    needs_order = false,
    needs_targets = false,
    allows_weights = false,
    allows_partition = true
)

const GLM_SPEC = CardSpec(
    type = GLMCard,
    label = "GLM",
    needs_order = false,
    needs_targets = true,
    allows_weights = true,
    allows_partition = true
)

const MIXED_MODEL_SPEC = CardSpec(
    type = MixedModelCard,
    label = "Mixed Model",
    needs_order = false,
    needs_targets = true,
    allows_weights = true,
    allows_partition = true
)

const INTERP_SPEC = CardSpec(
    type = InterpCard,
    label = "Interpolation",
    needs_order = false,
    needs_targets = true,
    allows_weights = false,
    allows_partition = true
)

const GAUSSIAN_ENCODING_SPEC = CardSpec(
    type = GaussianEncodingCard,
    label = "Gaussian Encoding",
    needs_order = false,
    needs_targets = false,
    allows_weights = false,
    allows_partition = false
)

const STREAMLINER_SPEC = CardSpec(
    type = StreamlinerCard,
    label = "Streamliner",
    needs_order = true,
    needs_targets = true,
    allows_weights = false,
    allows_partition = true
)
