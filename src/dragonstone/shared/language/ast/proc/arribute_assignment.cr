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

            def to_source(io : IO)
                receiver.to_source(io)
                io << "." << name
                # `x.y += 1`, not `x.y + = 1`.
                io << " "
                io << operator if operator
                io << "= "
                value.to_source(io)
            end
        end
    end
end
