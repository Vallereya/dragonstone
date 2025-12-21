module Dragonstone
    module AST
        class ModuleVariable < Node
            getter name : String

            def initialize(name : String, location : Location? = nil)
                super(location: location)
                @name = name
            end

            def accept(visitor)
                if visitor.responds_to?(:visit_module_variable)
                    visitor.visit_module_variable(self)
                else
                    nil
                end
            end

            def to_source(io : IO)
                io << "@@@" << @name
            end
        end
    end
end

