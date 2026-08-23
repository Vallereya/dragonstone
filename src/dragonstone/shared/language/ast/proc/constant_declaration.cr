module Dragonstone
    module AST
        class ConstantDeclaration < Node
            getter name : String
            getter value : Node
            getter type_annotation : TypeExpression?
            getter visibility : Symbol

            def initialize(
                name : String,
                value : Node,
                type_annotation : TypeExpression? = nil,
                visibility : Symbol = :public,
                location : Location? = nil
            )
                super(location: location)
                @name = name
                @value = value
                @type_annotation = type_annotation
                @visibility = visibility
            end

            def accept(visitor)
                visitor.visit_constant_declaration(self)
            end

            def to_source(io : IO)
                io << visibility << " " unless visibility == :public
                io << "con " << name
                if type = type_annotation
                    io << " : "
                    type.to_source(io)
                end
                io << " = "
                value.to_source(io)
            end
        end
    end
end
