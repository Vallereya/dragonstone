module Dragonstone
    module AST
        abstract class TypeExpression
            getter location : Location?

            def initialize(@location : Location? = nil)
            end

            abstract def to_source : String
        end

        class SimpleTypeExpression < TypeExpression
            getter name : String

            def initialize(@name : String, location : Location? = nil)
                super(location: location)
            end

            def to_source : String
                @name
            end
        end

        class UnionTypeExpression < TypeExpression
            getter members : Array(TypeExpression)

            def initialize(@members : Array(TypeExpression), location : Location? = nil)
                super(location: location)
            end

            def to_source : String
                @members.map(&.to_source).join(" | ")
            end
        end

        class OptionalTypeExpression < TypeExpression
            getter inner : TypeExpression

            def initialize(@inner : TypeExpression, location : Location? = nil)
                super(location: location)
            end

            def to_source : String
                "#{@inner.to_source}?"
            end
        end

        struct TypedParameter
            getter name : String
            getter type : TypeExpression?

            def initialize(@name : String, @type : TypeExpression? = nil)
            end

            def to_source : String
                return name unless type
                "#{name}: #{type.not_nil!.to_source}"
            end
        end
    end
end
