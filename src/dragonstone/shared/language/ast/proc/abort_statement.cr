module Dragonstone
    module AST
        class AbortStatement < Node
            getter message : Node?

            def initialize(message : Node?, location : Location? = nil)
                super(location: location)
                @message = message
            end

            def accept(visitor)
                visitor.visit_abort_statement(self)
            end

            def to_source : String
                if message
                    "abort #{message.not_nil!.to_source}"
                else
                    "abort"
                end
            end
        end
    end
end
