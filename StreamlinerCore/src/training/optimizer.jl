function get_optimizer(config::AbstractDict)
    optimizer_config, optimizer_name = pop(config[:optimizer], :name)
    method = PARSER[].optimizers[optimizer_name]
    return method(; optimizer_config...)
end
