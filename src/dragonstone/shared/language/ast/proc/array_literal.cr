module Dragonstone
    module AST
        class ArrayLiteral < Node
            getter elements : NodeArray
            getter element_type : TypeExpression?

            def initialize(elements : NodeArray, @element_type : TypeExpression? = nil, location : Location? = nil)
                super(location: location)
                @elements = elements
            end

            def accept(visitor)
                visitor.visit_array_literal(self)
            end

            def to_source(io : IO)
                io << "["
                @elements.each_with_index do |element, index|
                    io << ", " if index > 0
                    element.to_source(io)
                end
                io << "]"

                if t = @element_type
                    io << " as " << t.to_source
                end
            end

        end
    end
end
