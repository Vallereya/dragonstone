module Dragonstone
    module AST
        class DebugEcho < Node
            getter expression : Node
            getter inline : Bool

            def initialize(expression : Node, @inline : Bool = false, location : Location? = nil)
                super(location: location)
                @expression = expression
            end

            def accept(visitor)
                visitor.visit_debug_echo(self)
            end

            def to_source : String
                expression.to_source
            end
        end
    end
end
