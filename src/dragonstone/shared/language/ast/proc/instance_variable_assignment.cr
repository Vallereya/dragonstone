module Dragonstone
    module AST
        class InstanceVariableAssignment < Node
            getter name : String
            getter value : Node
            getter operator : Symbol?

            def initialize(name : String, value : Node, operator : Symbol? = nil, location : Location? = nil)
                super(location: location)
                @name = name
                @value = value
                @operator = operator
            end

            def accept(visitor)
                visitor.visit_instance_variable_assignment(self)
            end

            def to_source(io : IO)
                io << "@" << @name
                # `@x += 1`, not `@x + = 1`.
                io << " "
                io << operator if operator
                io << "= "
                value.to_source(io)
            end
        end
    end
end
