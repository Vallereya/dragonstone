module Dragonstone
    module AST
        class ModuleDefinition < Node
            getter name : String
            getter body : NodeArray
            getter annotations : Array(Annotation)
            getter visibility : Symbol

            def initialize(
                name : String,
                body : NodeArray,
                annotations : Array(Annotation) = [] of Annotation,
                visibility : Symbol = :public,
                location : Location? = nil
            )
                super(location: location)
                @name = name
                @body = body
                @annotations = annotations
                @visibility = visibility
            end

            def accept(visitor)
                visitor.visit_module_definition(self)
            end

            def to_source : String
                body_source = body.map(&.to_source).join("; ")
                header = visibility == :public ? "module #{name}" : "#{visibility} module #{name}"
                if body_source.empty?
                    "#{header}\nend"
                else
                    "#{header}\n  #{body_source}\nend"
                end
            end
        end
    end
end
