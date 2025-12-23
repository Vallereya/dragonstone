module Dragonstone
    module AST
        class StdinExpression < Node
            def accept(visitor)
                visitor.visit_stdin_expression(self)
            end

            def to_source(io : IO)
                io << "stdin"
            end
        end
    end
end
