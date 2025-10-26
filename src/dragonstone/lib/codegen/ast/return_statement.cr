module Dragonstone
    module AST
        class ReturnStatement < Node
            getter value : Node?

            def initialize(value : Node?, location : Location? = nil)
                super(location: location)
                @value = value
            end

            def accept(visitor)
                visitor.visit_return_statement(self)
            end

            def to_source : String
                if value
                    "return #{value.not_nil!.to_source}"
                else
                    "return"
                end
            end
        end
    end
end
