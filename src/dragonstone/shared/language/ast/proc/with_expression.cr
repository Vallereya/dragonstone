module Dragonstone
    module AST
        class WithExpression < Node
            getter receiver : Node
            getter body : NodeArray

            def initialize(@receiver : Node, @body : NodeArray, location : Location? = nil)
                super(location: location)
            end

            def accept(visitor)
                visitor.visit_with_expression(self)
            end

            def to_source : String
                body_source = body.map(&.to_source).join("; ")
                "with #{receiver.to_source} do #{body_source} end"
            end
        end
    end
end
