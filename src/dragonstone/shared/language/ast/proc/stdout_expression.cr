module Dragonstone
    module AST
        class StdoutExpression < Node
            def accept(visitor)
                visitor.visit_stdout_expression(self)
            end

            def to_source(io : IO)
                io << "stdout"
            end
        end
    end
end
