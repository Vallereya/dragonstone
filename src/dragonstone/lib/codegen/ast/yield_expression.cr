module Dragonstone
    module AST
        class YieldExpression < Node
            getter arguments : NodeArray

            def initialize(@arguments : NodeArray, location : Location? = nil)
                super(location: location)
            end

            def accept(visitor)
                visitor.visit_yield_expression(self)
            end

            def to_source : String
                args = arguments.map(&.to_source).join(", ")
                args.empty? ? "yield" : "yield #{args}"
            end
        end
    end
end
