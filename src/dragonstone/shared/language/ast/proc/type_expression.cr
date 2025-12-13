module Dragonstone
    module AST
        abstract class TypeExpression
            getter location : Location?

            def initialize(@location : Location? = nil)

            end

            def to_source : String
                String.build do |io|
                    to_source(io)
                end
            end

            # abstract def to_source : String
            abstract def to_source(io : IO)
        end

        class SimpleTypeExpression < TypeExpression
            getter name : String

            def initialize(@name : String, location : Location? = nil)
                super(location: location)
            end

            # def to_source : String
            #     @name
            # end

            def to_source(io : IO)
                io << @name
            end
        end

        class GenericTypeExpression < TypeExpression
            getter name : String
            getter arguments : Array(TypeExpression)

            def initialize(@name : String, @arguments : Array(TypeExpression), location : Location? = nil)
                super(location: location)
            end

            # def to_source : String
            #     arg_source = @arguments.map(&.to_source).join(", ")
            #     "#{@name}(#{arg_source})"
            # end

            def to_source(io : IO)
                io << @name
                io << "("
                @arguments.each_with_index do |arg, index|
                    io << ", " if index > 0
                    arg.to_source(io)
                end
                io << ")"
            end
        end

        class UnionTypeExpression < TypeExpression
            getter members : Array(TypeExpression)

            def initialize(@members : Array(TypeExpression), location : Location? = nil)
                super(location: location)
            end

            # def to_source : String
            #     @members.map(&.to_source).join(" | ")
            # end

            def to_source(io : IO)
                @members.each_with_index do |member, index|
                    io << " | " if index > 0
                    member.to_source(io)
                end
            end
        end

        class OptionalTypeExpression < TypeExpression
            getter inner : TypeExpression

            def initialize(@inner : TypeExpression, location : Location? = nil)
                super(location: location)
            end

            # def to_source : String
            #     "#{@inner.to_source}?"
            # end

            def to_source(io : IO)
                @inner.to_source(io)
                io << "?"
            end
        end

        struct TypedParameter
            getter name : String
            getter type : TypeExpression?
            getter instance_var_name : String?

            def initialize(@name : String, @type : TypeExpression? = nil, @instance_var_name : String? = nil)
                @instance_var_name = instance_var_name
                @type = type
            end

            def to_source(io : IO)
                if ivar = @instance_var_name
                    io << "@" << ivar
                else
                    io << name
                end

                if t = @type
                    io << ": "
                    t.to_source(io)
                end
            end

            def to_source : String
                # param_name = instance_var_name ? "@#{instance_var_name}" : name
                # return param_name unless type
                # "#{param_name}: #{type.not_nil!.to_source}"

                String.build do |io|
                    to_source(io)
                end
            end

            def assigns_instance_variable? : Bool
                !!@instance_var_name
            end
        end
    end
end
