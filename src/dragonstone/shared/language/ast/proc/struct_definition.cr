module Dragonstone
    module AST
        class StructDefinition < Node
            getter name : String
            getter body : NodeArray
            getter annotations : Array(Annotation)

            def initialize(name : String, body : NodeArray, annotations : Array(Annotation) = [] of Annotation, location : Location? = nil)
                super(location: location)
                @name = name
                @body = body
                @annotations = annotations
            end

            def accept(visitor)
                visitor.visit_struct_definition(self)
            end
        end
    end
end
