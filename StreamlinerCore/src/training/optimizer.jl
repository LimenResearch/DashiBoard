function parse_optimizer(metadata::AbstractDict)
    options = make(SymbolDict, metadata["optimizer"])
    name = pop!(options, :name)
    method = PARSER[].optimizers[name]
    return method(; options...)
end
