module Dragonstone
    module AST
        class Assignment < Node
            getter name : String
            getter value : Node
            getter operator : Symbol?
            getter type_annotation : TypeExpression?

            def initialize(name : String, value : Node, operator : Symbol? = nil, type_annotation : TypeExpression? = nil, location : Location? = nil)
                super(location: location)
                @name = name
                @value = value
                @operator = operator
                @type_annotation = type_annotation
            end

            def accept(visitor)
                visitor.visit_assignment(self)
            end

            def to_source : String
                lhs = if type_annotation
                    "#{name}: #{type_annotation.not_nil!.to_source}"
                else
                    name
                end

                if operator
                    "#{lhs} #{operator} = #{value.to_source}"
                else
                    "#{lhs} = #{value.to_source}"
                end
            end

            def to_source(io : IO)
                io << name
                io << " " << operator if operator
                io << " = "
                value.to_source(io)
            end
        end
    end
end
