module Dragonstone
    module AST
        class AliasDefinition < Node
            getter name : String
            getter type_expression : TypeExpression

            def initialize(name : String, type_expression : TypeExpression, location : Location? = nil)
                super(location: location)
                @name = name
                @type_expression = type_expression
            end

            def accept(visitor)
                visitor.visit_alias_definition(self)
            end
        end
    end
end
