module Dragonstone
    module Typing
        alias ConstantLookup = Proc(String, RuntimeValue?)
        alias ConstantMatcher = Proc(RuntimeValue, RuntimeValue, Bool)
        alias AliasLookup = Proc(String, Descriptor?)

        class UnknownTypeError < Exception
            getter type_name : String

            def initialize(@type_name : String)
                super("Unknown type '#{type_name}'")
            end
        end

        class RecursiveAliasError < Exception
            getter alias_name : String

            def initialize(@alias_name : String)
                super("Recursive alias '#{alias_name}' detected")
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
                "map"     => ->(value : RuntimeValue) { value.is_a?(MapValue) },
                "nil"     => ->(value : RuntimeValue) { value.nil? },
                "any"     => ->(_value : RuntimeValue) { true }
            }

            def matcher_for(name : String)
                MATCHERS[name.downcase]?
            end
        end

        struct Context
            def initialize(@constant_lookup : ConstantLookup, @constant_matcher : ConstantMatcher, @alias_lookup : AliasLookup? = nil)
                @alias_stack = [] of String
            end

            def resolve_constant(name : String)
                @constant_lookup.call(name)
            end

            def matches_constant?(constant, value)
                @constant_matcher.call(constant, value)
            end

            def alias_descriptor(name : String) : Descriptor?
                return nil unless @alias_lookup
                @alias_lookup.not_nil!.call(name)
            end

            def alias_in_progress?(name : String) : Bool
                @alias_stack.includes?(name)
            end

            def push_alias(name : String)
                @alias_stack << name
            end

            def pop_alias
                @alias_stack.pop
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
                if alias_descriptor = context.alias_descriptor(@name)
                    if context.alias_in_progress?(@name)
                        raise RecursiveAliasError.new(@name)
                    end
                    context.push_alias(@name)
                    begin
                        return alias_descriptor.satisfied_by?(value, context)
                    ensure
                        context.pop_alias
                    end
                end

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

        class ArrayDescriptor < Descriptor
            getter element : Descriptor

            def initialize(@element : Descriptor)
            end

            def satisfied_by?(value, context : Context) : Bool
                return false unless value.is_a?(Array)
                value.each do |element|
                    return false unless @element.satisfied_by?(element, context)
                end
                true
            end

            def to_s : String
                "Array(#{@element.to_s})"
            end
        end

        class HashDescriptor < Descriptor
            getter key_descriptor : Descriptor
            getter value_descriptor : Descriptor

            def initialize(@key_descriptor : Descriptor, @value_descriptor : Descriptor)
            end

            def satisfied_by?(value, context : Context) : Bool
                return false unless value.is_a?(MapValue)
                value.entries.each do |key, val|
                    return false unless @key_descriptor.satisfied_by?(key, context)
                    return false unless @value_descriptor.satisfied_by?(val, context)
                end
                true
            end

            def to_s : String
                "Hash(#{@key_descriptor.to_s}, #{@value_descriptor.to_s})"
            end
        end

        class RangeDescriptor < Descriptor
            getter begin_descriptor : Descriptor
            getter end_descriptor : Descriptor

            def initialize(@begin_descriptor : Descriptor, @end_descriptor : Descriptor)
            end

            def satisfied_by?(value, context : Context) : Bool
                return false unless value.is_a?(Range)
                @begin_descriptor.satisfied_by?(value.begin, context) &&
                    @end_descriptor.satisfied_by?(value.end, context)
            end

            def to_s : String
                "Range(#{@begin_descriptor.to_s}, #{@end_descriptor.to_s})"
            end
        end

        class BagDescriptor < Descriptor
            getter element : Descriptor

            def initialize(@element : Descriptor)
            end

            def satisfied_by?(value, context : Context) : Bool
                return false unless value.is_a?(BagValue)
                value.elements.all? { |element| @element.satisfied_by?(element, context) }
            end

            def to_s : String
                "bag(#{@element.to_s})"
            end
        end

        class ParaDescriptor < Descriptor
            getter parameter_descriptors : Array(Descriptor)
            getter return_descriptor : Descriptor

            def initialize(@parameter_descriptors : Array(Descriptor), @return_descriptor : Descriptor)
            end

            def satisfied_by?(value, context : Context) : Bool
                return false unless value.is_a?(Function)
                value.parameters.size == @parameter_descriptors.size
            end

            def to_s : String
                parts = @parameter_descriptors.map(&.to_s)
                parts << @return_descriptor.to_s
                "para(#{parts.join(", ")})"
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
            when AST::GenericTypeExpression
                build_generic_descriptor(expr)
            else
                raise ArgumentError.new("Unknown type expression #{expr.class}")
            end
        end

        private def self.build_generic_descriptor(expr : AST::GenericTypeExpression) : Descriptor
            name = expr.name.downcase
            args = expr.arguments
            case name
            when "array"
                raise ArgumentError.new("Array expects 1 type argument") unless args.size == 1
                ArrayDescriptor.new(build_descriptor(args.first))
            when "hash", "map"
                raise ArgumentError.new("Hash expects 2 type arguments") unless args.size == 2
                key_descriptor = build_descriptor(args[0])
                value_descriptor = build_descriptor(args[1])
                HashDescriptor.new(key_descriptor, value_descriptor)
            when "range"
                raise ArgumentError.new("Range expects 2 type arguments") unless args.size == 2
                begin_descriptor = build_descriptor(args[0])
                end_descriptor = build_descriptor(args[1])
                RangeDescriptor.new(begin_descriptor, end_descriptor)
            when "bag"
                raise ArgumentError.new("bag expects 1 type argument") unless args.size == 1
                BagDescriptor.new(build_descriptor(args.first))
            when "para"
                raise ArgumentError.new("para expects at least 1 type argument") if args.empty?
                params = args[0...-1].map { |arg| build_descriptor(arg) }
                return_descriptor = build_descriptor(args.last)
                ParaDescriptor.new(params, return_descriptor)
            else
                raise UnknownTypeError.new(expr.name)
            end
        end
    end
end
