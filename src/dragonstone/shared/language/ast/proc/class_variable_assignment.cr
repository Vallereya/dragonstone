module Dragonstone
    module AST
        class ClassVariableAssignment < Node
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
                if visitor.responds_to?(:visit_class_variable_assignment)
                    visitor.visit_class_variable_assignment(self)
                else
                    nil
                end
            end

            def to_source(io : IO)
                io << "@@" << @name
                io << " " << @operator if @operator
                io << " = "
                @value.to_source(io)
            end
        end
    end
end

