module Dragonstone
    module AST
        class Assignment < Node
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
                visitor.visit_assignment(self)
            end

            def to_source : String
                if operator
                    "#{name} #{operator} = #{value.to_source}"
                else
                    "#{name} = #{value.to_source}"
                end
            end
        end
    end
end
