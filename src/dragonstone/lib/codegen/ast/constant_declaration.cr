module Dragonstone
    module AST
        class ConstantDeclaration < Node
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
                visitor.visit_constant_declaration(self)
            end
        end
    end
end
