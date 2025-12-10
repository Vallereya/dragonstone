module Dragonstone
    module AST
        class RescueClause < Node
            getter exceptions : Array(String)
            getter exception_variable : String?
            getter body : NodeArray

            def initialize(exceptions : Array(String), exception_variable : String?, body : NodeArray, location : Location? = nil)
                super(location: location)
                @exceptions = exceptions
                @exception_variable = exception_variable
                @body = body
            end

            def accept(visitor)
                if visitor.responds_to?(:visit_rescue_clause)
                    visitor.visit_rescue_clause(self)
                else
                    nil
                end
            end

            def to_source(io : IO)
                io << "rescue"
                if !exceptions.empty?
                    io << " "
                    exceptions.each_with_index do |type, i|
                        io << ", " if i > 0
                        io << type
                    end
                end
                if v = exception_variable
                    io << " => "
                    io << v
                end
                io << "\n"
                body.each do |stmt|
                    stmt.to_source(io)
                    io << "\n"
                end
            end
        end
    end
end
