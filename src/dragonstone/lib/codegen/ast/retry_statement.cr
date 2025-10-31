module Dragonstone
    module AST
        class RetryStatement < Node
            getter condition : Node?
            getter condition_type : Symbol?

            def initialize(condition : Node? = nil, condition_type : Symbol? = nil, location : Location? = nil)
                super(location: location)
                @condition = condition
                @condition_type = condition_type
            end

            def accept(visitor)
                visitor.visit_retry_statement(self)
            end
        end
    end
end
