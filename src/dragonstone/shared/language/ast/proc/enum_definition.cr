module Dragonstone
    module AST
        class EnumDefinition < Node
            getter name : String
            getter members : Array(EnumMember)
            getter value_name : String?
            getter value_type : TypeExpression?
            getter annotations : Array(Annotation)

            def initialize(name : String, members : Array(EnumMember), value_name : String? = nil, value_type : TypeExpression? = nil, annotations : Array(Annotation) = [] of Annotation, location : Location? = nil)
                super(location: location)
                @name = name
                @members = members
                @value_name = value_name
                @value_type = value_type
                @annotations = annotations
            end

            def accept(visitor)
                visitor.visit_enum_definition(self)
            end

            # def to_source : String
            #     String.build do |io|
            #         io << name
            #         if v = value
            #             io << " = " << v.to_source
            #         end
            #     end
            # end
        end
    end
end
