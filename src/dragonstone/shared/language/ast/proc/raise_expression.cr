module Dragonstone
    module AST
        class RaiseExpression < Node
            getter expression : Node?

            def initialize(expression : Node? = nil, location : Location? = nil)
                super(location: location)
                @expression = expression
            end

            def accept(visitor)
                visitor.visit_raise_expression(self)
            end

            def to_source(io : IO)
                io << "raise"
                if exp = @expression
                    io << " "
                    exp.to_source(io)
                end
            end
        end
    end
end
