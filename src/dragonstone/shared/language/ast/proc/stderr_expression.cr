module Dragonstone
    module AST
        class StderrExpression < Node
            def accept(visitor)
                visitor.visit_stderr_expression(self)
            end

            def to_source(io : IO)
                io << "stderr"
            end
        end
    end
end
