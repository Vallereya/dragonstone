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

            def to_source : String
                lhs = "@#{@name}"
                if operator
                    "#{lhs} #{operator} = #{value.to_source}"
                else
                    "#{lhs} = #{value.to_source}"
                end
            end
        end
    end
end
