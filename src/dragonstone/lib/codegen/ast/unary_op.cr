module Dragonstone
    module AST
        class UnaryOp < Node
            getter operator : Symbol
            getter operand : Node

            def initialize(operator : Symbol, operand : Node, location : Location? = nil)
                super(location: location)
                @operator = operator
                @operand = operand
            end

            def accept(visitor)
                visitor.visit_unary_op(self)
            end

            def to_source : String
                "#{operator}#{operand.to_source}"
            end
        end
    end
end
