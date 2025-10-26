module Dragonstone
    module Typing
        alias ConstantLookup = Proc(String, RuntimeValue?)
        alias ConstantMatcher = Proc(RuntimeValue, RuntimeValue, Bool)
        class UnknownTypeError < Exception
            getter type_name : String

            def initialize(@type_name : String)
                super("Unknown type '#{type_name}'")
            end
        end

        module Builtins
            extend self

            MATCHERS = {
                "string"  => ->(value : RuntimeValue) { value.is_a?(String) },
                "str"     => ->(value : RuntimeValue) { value.is_a?(String) },
                "int"     => ->(value : RuntimeValue) { value.is_a?(Int32) || value.is_a?(Int64) },
                "integer" => ->(value : RuntimeValue) { value.is_a?(Int32) || value.is_a?(Int64) },
                "float"   => ->(value : RuntimeValue) { value.is_a?(Float32) || value.is_a?(Float64) },
                "bool"    => ->(value : RuntimeValue) { value.is_a?(Bool) },
                "boolean" => ->(value : RuntimeValue) { value.is_a?(Bool) },
                "char"    => ->(value : RuntimeValue) { value.is_a?(Char) },
                "array"   => ->(value : RuntimeValue) { value.is_a?(Array) },
                "nil"     => ->(value : RuntimeValue) { value.nil? },
                "any"     => ->(_value : RuntimeValue) { true }
            }

            def matcher_for(name : String)
                MATCHERS[name.downcase]?
            end
        end

        struct Context
            def initialize(@constant_lookup : ConstantLookup, @constant_matcher : ConstantMatcher)
            end

            def resolve_constant(name : String)
                @constant_lookup.call(name)
            end

            def matches_constant?(constant, value)
                @constant_matcher.call(constant, value)
            end
        end

        abstract class Descriptor
            abstract def satisfied_by?(value, context : Context) : Bool
            abstract def to_s : String
        end

        class SimpleDescriptor < Descriptor
            getter name : String

            def initialize(@name : String)
            end

            def satisfied_by?(value, context : Context) : Bool
                if matcher = Builtins.matcher_for(@name)
                    return matcher.call(value)
                end

                constant = context.resolve_constant(@name)
                raise UnknownTypeError.new(@name) unless constant
                context.matches_constant?(constant, value)
            end

            def to_s : String
                @name
            end
        end

        class UnionDescriptor < Descriptor
            getter members : Array(Descriptor)

            def initialize(@members : Array(Descriptor))
            end

            def satisfied_by?(value, context : Context) : Bool
                @members.any? { |member| member.satisfied_by?(value, context) }
            end

            def to_s : String
                @members.map(&.to_s).join(" | ")
            end
        end

        class OptionalDescriptor < Descriptor
            getter inner : Descriptor

            def initialize(@inner : Descriptor)
            end

            def satisfied_by?(value, context : Context) : Bool
                value.nil? || @inner.satisfied_by?(value, context)
            end

            def to_s : String
                "#{@inner.to_s}?"
            end
        end

        class DescriptorCache
            def initialize
                @cache = {} of UInt64 => Descriptor
            end

            def fetch(expr : AST::TypeExpression) : Descriptor
                key = expr.object_id
                cached = @cache[key]?
                return cached if cached

                descriptor = Typing.build_descriptor(expr)
                @cache[key] = descriptor
                descriptor
            end
        end

        def self.build_descriptor(expr : AST::TypeExpression) : Descriptor
            case expr
            when AST::SimpleTypeExpression
                SimpleDescriptor.new(expr.name)
            when AST::UnionTypeExpression
                members = expr.members.map { |member| build_descriptor(member) }
                UnionDescriptor.new(members)
            when AST::OptionalTypeExpression
                OptionalDescriptor.new(build_descriptor(expr.inner))
            else
                raise ArgumentError.new("Unknown type expression #{expr.class}")
            end
        end
    end
end
