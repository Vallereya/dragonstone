module Dragonstone
    module AST
        class AttributeAssignment < Node
            getter receiver : Node
            getter name : String
            getter value : Node
            getter operator : Symbol?

            def initialize(receiver : Node, name : String, value : Node, operator : Symbol? = nil, location : Location? = nil)
                super(location: location)
                @receiver = receiver
                @name = name
                @value = value
                @operator = operator
            end

            def accept(visitor)
                visitor.visit_attribute_assignment(self)
            end
        end
    end
end
