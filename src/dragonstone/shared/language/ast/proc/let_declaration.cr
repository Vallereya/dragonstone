module Dragonstone
    module AST
        class LetDeclaration < Node
            getter name : String
            getter value : Node
            getter type_annotation : TypeExpression?

            def initialize(name : String, value : Node, type_annotation : TypeExpression? = nil, location : Location? = nil)
                super(location: location)
                @name = name
                @value = value
                @type_annotation = type_annotation
            end

            def accept(visitor)
                if visitor.responds_to?(:visit_let_declaration)
                    visitor.visit_let_declaration(self)
                else
                    nil
                end
            end

            def to_source(io : IO)
                io << "let " << @name
                if type = @type_annotation
                    io << ": "
                    type.to_source(io)
                end
                io << " = "
                @value.to_source(io)
            end
        end
    end
end
