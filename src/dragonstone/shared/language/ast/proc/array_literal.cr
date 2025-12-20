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

            def to_source : String
                rendered = "[#{elements.map(&.to_source).join(", ")}]"
                if t = @element_type
                    "#{rendered} as #{t.to_source}"
                else
                    rendered
                end
            end
        end
    end
end
