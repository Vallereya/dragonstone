module Dragonstone
    class ReturnValue < Exception
        getter value : RuntimeValue?

        def initialize(@value : RuntimeValue?)
            super()
        end
    end

    class BreakSignal < Exception; end
    class NextSignal  < Exception; end
    class RedoSignal  < Exception; end
    class RetrySignal < Exception; end
end
