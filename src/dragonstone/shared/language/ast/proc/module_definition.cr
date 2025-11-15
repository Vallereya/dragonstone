module Dragonstone
    module AST
        class ModuleDefinition < Node
            getter name : String
            getter body : NodeArray

            def initialize(name : String, body : NodeArray, location : Location? = nil)
                super(location: location)
                @name = name
                @body = body
            end

            def accept(visitor)
                visitor.visit_module_definition(self)
            end
        end
    end
end
