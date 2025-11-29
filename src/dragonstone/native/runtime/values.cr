require "set"
require "../../shared/language/ast/ast"
require "../../shared/language/diagnostics/errors"
require "../../shared/typing/types"
require "../../shared/runtime/ffi_module"
require "../../shared/runtime/symbol"

module Dragonstone
    class RaisedException
        getter error : InterpreterError

        def initialize(@error : InterpreterError)
        end

        def message : String
            @error.original_message
        end

        def to_s : String
            class_name = error.class.name.split("::").last
            "#{class_name}: #{message}"
        end
    end

    alias RangeValue = Range(Int64, Int64) | Range(Char, Char)
    alias RuntimeValue = Nil | Bool | Int32 | Int64 | Float64 | String | Char | SymbolValue | Array(RuntimeValue) | Hash(RuntimeValue, RuntimeValue) | TupleValue | NamedTupleValue | DragonModule | DragonClass | DragonInstance | Function | RangeValue | FFIModule | DragonEnumMember | RaisedException | BagConstructor | BagValue
    alias MapValue = Hash(RuntimeValue, RuntimeValue)

    class TupleValue
        getter elements : Array(RuntimeValue)

        def initialize(elements : Array(RuntimeValue))
            @elements = elements
        end
    end

    class NamedTupleValue
        getter entries : Hash(SymbolValue, RuntimeValue)

        def initialize(entries : Hash(SymbolValue, RuntimeValue))
            @entries = entries
        end
    end

    class BagConstructor
        getter element_descriptor : Typing::Descriptor
        getter element_type : AST::TypeExpression

        def initialize(@element_descriptor : Typing::Descriptor, @element_type : AST::TypeExpression)
        end

        def to_s : String
            "bag(#{element_descriptor.to_s})"
        end
    end

    class BagValue
        getter element_descriptor : Typing::Descriptor?
        getter elements : Array(RuntimeValue)

        def initialize(@element_descriptor : Typing::Descriptor?)
            @elements = [] of RuntimeValue
        end

        def size : Int64
            @elements.size.to_i64
        end

        def includes?(value : RuntimeValue) : Bool
            @elements.any? { |existing| existing == value }
        end

        def add(value : RuntimeValue)
            unless includes?(value)
                @elements << value
            end
            self
        end
    end

    class ConstantBinding
        getter value : RuntimeValue

        def initialize(@value : RuntimeValue)
        end
    end

    alias ScopeValue = RuntimeValue | ConstantBinding
    alias Scope = Hash(String, ScopeValue)
    alias TypeScope = Hash(String, Typing::Descriptor)

    class Function
        getter name : String?
        getter typed_parameters : Array(AST::TypedParameter)
        getter body : Array(AST::Node)
        getter closure : Scope
        getter type_closure : TypeScope
        getter rescue_clauses : Array(AST::RescueClause)
        getter return_type : AST::TypeExpression?
        @parameter_names : Array(String)

        def initialize(@name : String?, typed_parameters : Array(AST::TypedParameter), @body : Array(AST::Node), @closure : Scope, @type_closure : TypeScope, @rescue_clauses : Array(AST::RescueClause) = [] of AST::RescueClause, @return_type : AST::TypeExpression? = nil)
            @typed_parameters = typed_parameters
            @parameter_names = typed_parameters.map(&.name)
        end

        def parameters : Array(String)
            @parameter_names
        end
    end

    class MethodDefinition
        getter name : String
        getter typed_parameters : Array(AST::TypedParameter)
        getter body : Array(AST::Node)
        getter closure : Scope
        getter type_closure : TypeScope
        getter rescue_clauses : Array(AST::RescueClause)
        getter return_type : AST::TypeExpression?
        getter visibility : Symbol
        getter owner : DragonModule
        getter? abstract : Bool
        @parameter_names : Array(String)

        def initialize(@name : String, typed_parameters : Array(AST::TypedParameter), @body : Array(AST::Node), @closure : Scope, @type_closure : TypeScope, @owner : DragonModule, @rescue_clauses : Array(AST::RescueClause) = [] of AST::RescueClause, @return_type : AST::TypeExpression? = nil, visibility : Symbol = :public, is_abstract : Bool = false)
            @typed_parameters = typed_parameters
            @parameter_names = typed_parameters.map(&.name)
            @visibility = visibility
            @abstract = is_abstract
        end

        def parameters : Array(String)
            @parameter_names
        end

        def dup_with_owner(new_owner : DragonModule) : MethodDefinition
            MethodDefinition.new(
                @name,
                @typed_parameters.dup,
                @body.dup,
                @closure.dup,
                @type_closure.dup,
                new_owner,
                @rescue_clauses.dup,
                @return_type,
                visibility: @visibility,
                is_abstract: @abstract
            )
        end
    end

    class DragonModule
        getter name : String

        def initialize(@name : String)
            @methods = {} of String => MethodDefinition
            @constants = {} of String => RuntimeValue
        end

        def define_method(name : String, method : MethodDefinition)
            @methods[name] = method
        end

        def lookup_method(name : String) : MethodDefinition?
            @methods[name]?
        end

        def each_method
            @methods.each do |name, method|
                yield name, method
            end
        end

        def constant?(name : String) : Bool
            @constants.has_key?(name)
        end

        def define_constant(name : String, value : RuntimeValue)
            @constants[name] = value
        end

        def fetch_constant(name : String) : RuntimeValue
            @constants[name]
        end
    end

    class DragonClass < DragonModule
        getter superclass : DragonClass?
        getter ivar_type_annotations : Hash(String, AST::TypeExpression?)
        getter ivar_type_descriptors : Hash(String, Typing::Descriptor?)
        getter? abstract : Bool

        def initialize(name : String, @superclass : DragonClass? = nil, is_abstract : Bool = false)
            super(name)
            if @superclass
                parent = @superclass.not_nil!
                @ivar_type_annotations = parent.ivar_type_annotations.dup
                @ivar_type_descriptors = parent.ivar_type_descriptors.dup
            else
                @ivar_type_annotations = {} of String => AST::TypeExpression?
                @ivar_type_descriptors = {} of String => Typing::Descriptor?
            end
            @abstract = is_abstract
        end

        def lookup_method(name : String) : MethodDefinition?
            super || @superclass.try &.lookup_method(name)
        end

        def register_ivar_type(name : String, type : AST::TypeExpression?)
            if type
                @ivar_type_annotations[name] = type
            else
                @ivar_type_annotations[name] = nil unless @ivar_type_annotations.has_key?(name)
            end
            @ivar_type_descriptors.delete(name)
        end

        def ivar_type_annotation(name : String) : AST::TypeExpression?
            @ivar_type_annotations[name]?
        end

        def ivar_type_descriptor(name : String) : Typing::Descriptor?
            @ivar_type_descriptors[name]?
        end

        def cache_ivar_descriptor(name : String, descriptor : Typing::Descriptor)
            @ivar_type_descriptors[name] = descriptor
        end

        def mark_abstract!
            @abstract = true
        end

        def unimplemented_abstract_methods : Set(String)
            lineage = [] of DragonClass
            current : DragonClass? = self
            while current
                lineage << current
                current = current.superclass
            end

            pending = Set(String).new
            lineage.reverse_each do |klass|
                klass.@methods.each do |name, method|
                    if method.abstract?
                        pending.add(name)
                    else
                        pending.delete(name)
                    end
                end
            end
            pending
        end
    end

    class DragonStruct < DragonClass
        def initialize(name : String)
            super(name)
        end
    end

    class DragonEnum < DragonModule
        getter value_method_name : String
        getter value_type_annotation : AST::TypeExpression?

        def initialize(name : String, value_method_name : String = "value", value_type_annotation : AST::TypeExpression? = nil)
            super(name)
            @value_method_name = value_method_name.empty? ? "value" : value_method_name
            @value_type_annotation = value_type_annotation
            @members = [] of DragonEnumMember
            @members_by_name = {} of String => DragonEnumMember
            @members_by_value = {} of Int64 => DragonEnumMember
        end

        def member(name : String) : DragonEnumMember?
            @members_by_name[name]?
        end

        def member_for_value(value : Int64) : DragonEnumMember?
            @members_by_value[value]?
        end

        def define_member(name : String, value : Int64) : DragonEnumMember
            member = DragonEnumMember.new(self, name, value)
            @members << member
            @members_by_name[name] = member
            @members_by_value[value] = member
            define_constant(name, member)
            member
        end

        def members : Array(DragonEnumMember)
            @members.dup
        end
    end

    class DragonEnumMember
        getter enum : DragonEnum
        getter name : String
        getter value : Int64

        def initialize(@enum : DragonEnum, @name : String, @value : Int64)
        end

        def to_s : String
            @name
        end
    end

    class SingletonClass < DragonModule
        getter target_id : UInt64
        property parent : DragonModule?

        def initialize(@target_id : UInt64, name : String, @parent : DragonModule? = nil)
            super(name)
        end
    end

    class DragonInstance
        getter klass : DragonClass
        getter ivars : Hash(String, RuntimeValue)

        def initialize(@klass : DragonClass)
            @ivars = {} of String => RuntimeValue
        end
    end
end
