module Dragonstone
    module AST
        class ClassDefinition < Node
            getter name : String
            getter body : NodeArray
            getter superclass : String?
            getter annotations : Array(Annotation)
            getter visibility : Symbol
            @abstract : Bool

            def initialize(
                name : String,
                body : NodeArray,
                superclass : String? = nil,
                is_abstract : Bool = false,
                annotations : Array(Annotation) = [] of Annotation,
                visibility : Symbol = :public,
                location : Location? = nil
            )
                super(location: location)
                @name = name
                @body = body
                @superclass = superclass
                @abstract = is_abstract
                @annotations = annotations
                @visibility = visibility
            end

            def accept(visitor)
                visitor.visit_class_definition(self)
            end

            def abstract? : Bool
                @abstract
            end

            def abstract : Bool
                abstract?
            end

            def to_source : String
                prefix = visibility == :public ? "" : "#{visibility} "
                header = abstract? ? "#{prefix}abstract class #{name}" : "#{prefix}class #{name}"
                header += " < #{superclass}" if superclass
                body_source = body.map(&.to_source).join("; ")
                if body_source.empty?
                    "#{header}\nend"
                else
                    "#{header}\n  #{body_source}\nend"
                end
            end
        end
    end
end
