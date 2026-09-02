using StructUtils: @kwarg

@kwarg struct TestStruct
    x::Int = 1
    y::String & (dashi = StringIR(enum = ["a", "b"]),)
end
