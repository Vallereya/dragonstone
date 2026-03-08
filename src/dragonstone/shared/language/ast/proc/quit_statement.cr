module Dragonstone
    module AST
        class QuitStatement < Node
            getter status : Node?

            def initialize(status : Node?, location : Location? = nil)
                super(location: location)
                @status = status
            end

            def accept(visitor)
                visitor.visit_quit_statement(self)
            end

            def to_source : String
                if status
                    "quit #{status.not_nil!.to_source}"
                else
                    "quit"
                end
            end
        end
    end
end
