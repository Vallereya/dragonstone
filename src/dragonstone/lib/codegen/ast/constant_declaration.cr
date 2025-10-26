module Dragonstone
    module AST
        class ConstantDeclaration < Node
            getter name : String
            getter value : Node

            def initialize(name : String, value : Node, location : Location? = nil)
                super(location: location)
                @name = name
                @value = value
            end

            def accept(visitor)
                visitor.visit_constant_declaration(self)
            end
        end
    end
end
