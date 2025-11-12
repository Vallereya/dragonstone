module Dragonstone
    module AST
        class ClassDefinition < Node
            getter name : String
            getter body : NodeArray
            getter superclass : String?

            def initialize(name : String, body : NodeArray, superclass : String? = nil, location : Location? = nil)
                super(location: location)
                @name = name
                @body = body
                @superclass = superclass
            end

            def accept(visitor)
                visitor.visit_class_definition(self)
            end
        end
    end
end
