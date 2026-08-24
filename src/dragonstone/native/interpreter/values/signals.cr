module Dragonstone
    class ReturnValue < Exception
        getter value : RuntimeValue?
        getter target : UInt64?

        def initialize(@value : RuntimeValue?, @target : UInt64? = nil)
            super()
        end

        def claimed_by?(frame_id : UInt64) : Bool
            target = @target
            target.nil? || target == frame_id
        end
    end

    class BreakSignal < Exception; end
    class NextSignal  < Exception; end
    class RedoSignal  < Exception; end
    class RetrySignal < Exception; end
end
