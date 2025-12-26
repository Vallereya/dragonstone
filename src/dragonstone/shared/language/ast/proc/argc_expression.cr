module Dragonstone
    module AST
        class ArgcExpression < Node
            def accept(visitor)
                visitor.visit_argc_expression(self)
            end

            def to_source(io : IO)
                io << "argc"
            end
        end
    end
end
