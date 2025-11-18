require "../../shared/language/ast/ast"
require "../../shared/runtime/ffi_module"
require "../../shared/runtime/symbol"

module Dragonstone
    module Bytecode
        alias Value = Nil | Bool | Int32 | Int64 | Float64 | String | Char | SymbolValue | Array(Value) | CompiledCode | FunctionSignature | FunctionValue | BlockValue | BagConstructorValue | BagValue | AST::TypeExpression | FFIModule

        class ParameterSpec
            getter name_index : Int32
            getter type_expression : AST::TypeExpression?

            def initialize(@name_index : Int32, @type_expression : AST::TypeExpression?)
            end
        end

        class FunctionSignature
            getter parameters : Array(ParameterSpec)
            getter return_type : AST::TypeExpression?

            def initialize(@parameters : Array(ParameterSpec), @return_type : AST::TypeExpression?)
            end
        end

        class FunctionValue
            getter name : String
            getter signature : FunctionSignature
            getter code : CompiledCode

            def initialize(@name : String, @signature : FunctionSignature, @code : CompiledCode)
            end
        end

        class BlockValue
            getter signature : FunctionSignature
            getter code : CompiledCode

            def initialize(@signature : FunctionSignature, @code : CompiledCode)
            end
        end

        class BagConstructorValue
            getter element_type : AST::TypeExpression?

            def initialize(@element_type : AST::TypeExpression?)
            end
        end

        class BagValue
            getter element_type : AST::TypeExpression?
            getter elements : Array(Value)

            def initialize(@element_type : AST::TypeExpression?)
                @elements = [] of Value
            end

            def size : Int64
                @elements.size.to_i64
            end

            def includes?(value : Value) : Bool
                @elements.any? { |element| element == value }
            end

            def add(value : Value)
                @elements << value unless includes?(value)
                self
            end
        end
    end

    record CompiledCode,
        code : Array(Int32),
        consts : Array(Bytecode::Value),
        names : Array(String),
        locals_count : Int32
end
