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

            def to_source : String
                "#{condition.to_source} ? #{then_branch.to_source} : #{else_branch.to_source}"
            end
        end
    end
end
