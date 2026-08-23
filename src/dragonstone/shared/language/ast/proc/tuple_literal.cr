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

            def to_source(io : IO)
                io << "{"
                elements.each_with_index do |element, index|
                    io << ", " if index > 0
                    element.to_source(io)
                end
                io << "}"
            end
        end
    end
end
