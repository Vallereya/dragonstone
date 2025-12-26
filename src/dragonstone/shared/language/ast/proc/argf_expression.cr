module Dragonstone
    module AST
        class ArgfExpression < Node
            def accept(visitor)
                visitor.visit_argf_expression(self)
            end

            def to_source(io : IO)
                io << "argf"
            end
        end
    end
end
