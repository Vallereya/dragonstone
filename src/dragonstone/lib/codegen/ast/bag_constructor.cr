module Dragonstone
    module AST
        class BagConstructor < Node
            getter element_type : TypeExpression

            def initialize(@element_type : TypeExpression, location : Location? = nil)
                super(location: location)
            end

            def accept(visitor)
                visitor.visit_bag_constructor(self)
            end

            def to_source : String
                "bag(#{element_type.to_source})"
            end
        end
    end
end
