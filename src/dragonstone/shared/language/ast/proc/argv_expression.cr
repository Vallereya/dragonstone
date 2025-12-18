module Dragonstone
    module AST
        class ArgvExpression < Node
            def accept(visitor)
                visitor.visit_argv_expression(self)
            end

            def to_source(io : IO)
                io << "argv"
            end
        end
    end
end
