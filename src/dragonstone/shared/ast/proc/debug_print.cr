module Dragonstone
    module AST
        class DebugPrint < Node
            getter expression : Node

            def initialize(expression : Node, location : Location? = nil)
                super(location: location)
                @expression = expression
            end

            def accept(visitor)
                visitor.visit_debug_print(self)
            end

            def to_source : String
                expression.to_source
            end
        end
    end
end
