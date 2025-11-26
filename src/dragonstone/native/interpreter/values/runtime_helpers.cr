module Dragonstone
    class Interpreter
        private def get_type_name(value) : String
            case value

            when String
                "String"

            when Int64
                "Integer"

            when Int32
                "Integer"

            when Float64
                "Float"

            when Bool
                "Boolean"

            when Nil
                "Nil"

            when SymbolValue
                "Symbol"

            when Array(RuntimeValue)
                "Array"

            when Hash(RuntimeValue, RuntimeValue)
                "Map"

            when TupleValue
                "Tuple"

            when NamedTupleValue
                "NamedTuple"

            when FFIModule
                "FFIModule"

            when DragonClass
                "Class"

            when DragonInstance
                value.klass.name

            when DragonModule
                "Module"

            when Function
                "Function"

            when Range(Int64, Int64), Range(Char, Char)
                "Range"

            else
                value.class.name

            end
        end

        private def display_value(value) : String
            case value

            when Nil
                ""

            when String
                value

            when SymbolValue
                value.name

            when Array(RuntimeValue)
                "[#{value.map { |v| display_value(v) }.join(", ")}]"

            when MapValue
                pairs = value.map { |k, v| "#{display_value(k)} -> #{display_value(v)}" }.join(", ")
                "{#{pairs}}"

            when TupleValue
                "{#{value.elements.map { |element| display_value(element) }.join(", ")}}"

            when NamedTupleValue
                pairs = value.entries.map { |key, val| "#{key.name}: #{display_value(val)}" }.join(", ")
                "{#{pairs}}"

            when Bool
                value.to_s

            when Int64
                value.to_s

            when Int32
                value.to_i64.to_s

            when Float64
                value.to_s

            when Char
                value.to_s

            when FFIModule
                "ffi"

            when DragonInstance
                "#<#{value.klass.name}:0x#{value.object_id.to_s(16)}>"

            when DragonClass
                value.name

            when DragonModule
                value.name

            when DragonEnumMember
                value.name

            when BagValue
                "[#{value.elements.map { |element| display_value(element) }.join(", ")}]"

            when BagConstructor
                value.to_s

            when Function
                name = value.name || "<anonymous>"
                "#<Function #{name}>"

            when RaisedException
                value.to_s

            when Range(Int64, Int64), Range(Char, Char)
                value.to_s

            else
                value.to_s

            end
        end

        private def format_value(value) : String
            case value

            when String
                value.inspect

            when Array(RuntimeValue)
                "[#{value.map { |v| format_value(v) }.join(", ")}]"

            when Hash(RuntimeValue, RuntimeValue)
                pairs = value.map { |k, v| "#{format_value(k)} -> #{format_value(v)}" }.join(", ")
                "{#{pairs}}"

            when TupleValue
                "{#{value.elements.map { |element| format_value(element) }.join(", ")}}"

            when NamedTupleValue
                pairs = value.entries.map { |key, val| "#{key.name}: #{format_value(val)}" }.join(", ")
                "{#{pairs}}"

            when Nil
                "nil"

            when Bool
                value.to_s

            when FFIModule
                "ffi"

            when SymbolValue
                value.inspect

            when DragonInstance
                "#<#{value.klass.name}:0x#{value.object_id.to_s(16)}>"

            when DragonClass
                value.name

            when DragonModule
                value.name

            else
                value.to_s

            end
        end

        private def literal_node_for(value, node : AST::Node) : AST::Literal
            case value

            when Nil
                AST::Literal.new(nil, location: node.location)

            when Bool
                AST::Literal.new(value, location: node.location)

            when Int64
                AST::Literal.new(value, location: node.location)

            when Float64
                AST::Literal.new(value, location: node.location)

            when String
                AST::Literal.new(value, location: node.location)

            when Char
                AST::Literal.new(value, location: node.location)

            else
                runtime_error(InterpreterError, "Cannot use value of type #{value.class} in attribute assignment", node)
            
            end
        end

        private def evaluate_interpolation(content : String)
            lexer = Lexer.new(content)
            tokens = lexer.tokenize
            parser = Parser.new(tokens)
            expression = parser.parse_expression_entry
            expression.accept(self)
        rescue e : LexerError
            runtime_error(InterpreterError, "Error evaluating interpolation #{content.inspect}: #{e.message}")
        rescue e : ParserError
            runtime_error(InterpreterError, "Error evaluating interpolation #{content.inspect}: #{e.message}")
        end
    end
end
