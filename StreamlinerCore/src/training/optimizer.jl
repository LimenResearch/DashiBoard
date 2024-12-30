function get_optimizer(config::Config)
    optimizer_config = SymbolDict(config.optimizer)
    optimizer_name = pop!(optimizer_config, :name)
    method = PARSER[].optimizers[optimizer_name]
    return method(; optimizer_config...)
end
