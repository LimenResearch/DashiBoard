function colnames(catalog::SQLCatalog, name::AbstractString)
    tbl = catalog[name]
    return [String(k) for (k, _) in tbl]
end
