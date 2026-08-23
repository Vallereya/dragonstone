module Dragonstone
    module AST
        class ConditionalExpression < Node
            getter condition : Node
            getter then_branch : Node
            getter else_branch : Node

            def initialize(condition : Node, then_branch : Node, else_branch : Node, location : Location? = nil)
                super(location: location)
                @condition = condition
                @then_branch = then_branch
                @else_branch = else_branch
            end

            def accept(visitor)
                visitor.visit_conditional_expression(self)
            end

            def to_source(io : IO)
                @condition.to_source(io)
                io << " ? "
                @then_branch.to_source(io)
                io << " : "
                @else_branch.to_source(io)
            end

        end
    end
end
