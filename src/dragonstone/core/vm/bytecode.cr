require "../../shared/runtime/ffi_module"
require "../../shared/runtime/symbol"

module Dragonstone
    module Bytecode
        alias Value = Nil | Bool | Int32 | Int64 | Float64 | String | Char | SymbolValue | Array(Value) | CompiledCode | NamedTuple(name: String, params: Array(Value), code: CompiledCode) | FFIModule
    end

    record CompiledCode,
        code : Array(Int32),
        consts : Array(Bytecode::Value),
        names : Array(String),
        locals_count : Int32
end
