module Dragonstone
    module AST
        class TupleLiteral < Node
            getter elements : NodeArray

            def initialize(elements : NodeArray, location : Location? = nil)
                super(location: location)
                @elements = elements
            end

            def accept(visitor)
                visitor.visit_tuple_literal(self)
            end

            def to_source : String
                "{#{elements.map(&.to_source).join(", ")}}"
            end
        end
    end
end
