require "set"
require "../../shared/language/ast/ast"
require "../../shared/runtime/ffi_module"
require "../../shared/runtime/symbol"
require "../../shared/runtime/gc/gc"

module Dragonstone
    module Bytecode
        class GCHost
            getter manager : ::Dragonstone::Runtime::GC::Manager(Value)

            def initialize(@manager : ::Dragonstone::Runtime::GC::Manager(Value))
            end
        end

        class BuiltinStream
            enum Kind
                Stdout
                Stderr
            end

            getter kind : Kind

            def initialize(@kind : Kind)
            end
        end

        class BuiltinStdin
        end

        class BuiltinArgf
        end

        alias RangeValue = Range(Int64, Int64) | Range(Char, Char)
        alias Value = Nil | Bool | Int32 | Int64 | Float64 | String | Char | SymbolValue | Array(Value) | TupleValue | NamedTupleValue | RangeValue | CompiledCode | FunctionSignature | FunctionValue | ParaValue | BlockValue | BagConstructorValue | BagValue | MapValue | ModuleValue | ClassValue | StructValue | InstanceValue | EnumValue | EnumMemberValue | RaisedExceptionValue | AST::TypeExpression | FFIModule | BuiltinStream | BuiltinStdin | BuiltinArgf | ::Dragonstone::Runtime::GC::Area(Value) | GCHost

        class ParameterSpec
            getter name_index : Int32
            getter type_expression : AST::TypeExpression?
            getter ivar_name : String?

            def initialize(@name_index : Int32, @type_expression : AST::TypeExpression?, @ivar_name : String? = nil)
            end
        end

        class FunctionSignature
            getter parameters : Array(ParameterSpec)
            getter return_type : AST::TypeExpression?
            getter? abstract : Bool
            getter gc_flags : ::Dragonstone::Runtime::GC::Flags

            def initialize(@parameters : Array(ParameterSpec), @return_type : AST::TypeExpression?, is_abstract : Bool = false, gc_flags : ::Dragonstone::Runtime::GC::Flags = ::Dragonstone::Runtime::GC::Flags.new)
                @abstract = is_abstract
                @gc_flags = gc_flags
            end
        end

        class FunctionValue
            getter name : String
            getter signature : FunctionSignature
            getter code : CompiledCode
            getter? abstract : Bool

            def initialize(@name : String, @signature : FunctionSignature, @code : CompiledCode, is_abstract : Bool = false)
                @abstract = is_abstract
            end
        end

        class ParaValue
            getter signature : FunctionSignature
            getter code : CompiledCode
            getter env : Hash(String, Value)

            def initialize(@signature : FunctionSignature, @code : CompiledCode, @env : Hash(String, Value))
            end
        end

        class BlockValue
            getter signature : FunctionSignature
            getter code : CompiledCode

            def initialize(@signature : FunctionSignature, @code : CompiledCode)
            end
        end

        class BagConstructorValue
            getter element_type : AST::TypeExpression?

            def initialize(@element_type : AST::TypeExpression?)
            end
        end

        class BagValue
            getter element_type : AST::TypeExpression?
            getter elements : Array(Value)

            def initialize(@element_type : AST::TypeExpression?)
                @elements = [] of Value
            end

            def size : Int64
                @elements.size.to_i64
            end

            def includes?(value : Value) : Bool
                @elements.any? { |element| element == value }
            end

            def add(value : Value)
                @elements << value unless includes?(value)
                self
            end
        end

        class MapValue
            getter entries : Hash(Value, Value)

            def initialize
                @entries = {} of Value => Value
            end

            def size : Int64
                @entries.size.to_i64
            end

            def keys : Array(Value)
                result = [] of Value
                @entries.each_key { |key| result << key }
                result
            end

            def values : Array(Value)
                result = [] of Value
                @entries.each_value { |value| result << value }
                result
            end

            def empty? : Bool
                @entries.empty?
            end

            def [](key : Value) : Value
                @entries[key]?
            end

            def []?(key : Value) : Value
                @entries[key]?
            end

            def []=(key : Value, value : Value) : Value
                @entries[key] = value
            end

            def delete(key : Value) : Value
                @entries.delete(key)
            end

            def each
                @entries.each do |key, value|
                    yield key, value
                end
            end
        end

        class TupleValue
            getter elements : Array(Value)

            def initialize(@elements : Array(Value))
            end
        end

        class NamedTupleValue
            getter entries : Hash(SymbolValue, Value)

            def initialize
                @entries = {} of SymbolValue => Value
            end
        end

        class ModuleValue
            getter name : String
            getter constants : Hash(String, Value)
            getter ivars : Hash(String, Value)
            getter methods : Hash(String, FunctionValue)

            def initialize(@name : String)
                @constants = {} of String => Value
                @ivars = {} of String => Value
                @methods = {} of String => FunctionValue
            end

            def define_constant(name : String, value : Value)
                @constants[name] = value
            end

            def fetch_constant(name : String) : Value?
                @constants[name]?
            end

            def define_method(name : String, fn : FunctionValue)
                @methods[name] = fn
            end

            def lookup_method(name : String)
                @methods[name]?
            end
        end

        class ClassValue < ModuleValue
            getter superclass : ClassValue?
            getter? abstract : Bool

            def initialize(name : String, @superclass : ClassValue? = nil, is_abstract : Bool = false)
                super(name)
                @abstract = is_abstract
            end

            def lookup_method(name : String)
                super || @superclass.try &.lookup_method(name)
            end

            def lookup_method_with_owner(name : String) : NamedTuple(method: FunctionValue, owner: ClassValue)?
                if fn = methods[name]?
                    return {method: fn, owner: self}
                end
                @superclass.try &.lookup_method_with_owner(name)
            end

            def mark_abstract!
                @abstract = true
            end

            def unimplemented_abstract_methods : Set(String)
                lineage = [] of ClassValue
                current : ClassValue? = self
                while current
                    lineage << current
                    current = current.superclass
                end

                pending = Set(String).new
                lineage.reverse_each do |klass|
                    klass.methods.each do |name, method|
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

        class StructValue < ClassValue
        end

        class InstanceValue
            getter klass : ClassValue
            getter ivars : Hash(String, Value)

            def initialize(@klass : ClassValue)
                @ivars = {} of String => Value
            end
        end

        class EnumMemberValue
            getter enum : EnumValue
            getter name : String
            getter value : Int64

            def initialize(@enum : EnumValue, @name : String, @value : Int64)
            end

            def to_s
                @name
            end
        end

        class EnumValue < ModuleValue
            getter value_method_name : String
            getter members : Array(EnumMemberValue)
            getter members_by_name : Hash(String, EnumMemberValue)
            getter members_by_value : Hash(Int64, EnumMemberValue)
            property last_value : Int64

            def initialize(name : String, @value_method_name : String = "value")
                super(name)
                @members = [] of EnumMemberValue
                @members_by_name = {} of String => EnumMemberValue
                @members_by_value = {} of Int64 => EnumMemberValue
                @last_value = -1_i64
            end

            def define_member(name : String, value : Int64)
                member = EnumMemberValue.new(self, name, value)
                @members << member
                @members_by_name[name] = member
                @members_by_value[value] = member
                define_constant(name, member)
                @last_value = value
                member
            end

            def member(name : String)
                @members_by_name[name]?
            end

            def member_for_value(value : Int64)
                @members_by_value[value]?
            end
        end

        class RaisedExceptionValue
            getter value : Value?

            def initialize(@value : Value?)
            end

            def message : String
                value.nil? ? "" : value.to_s
            end
        end

        module ::Dragonstone::Runtime::GC
            def self.deep_copy_bytecode(value : ::Dragonstone::Bytecode::Value) : ::Dragonstone::Bytecode::Value
                case value
                when Array(::Dragonstone::Bytecode::Value)
                    value.map { |element| deep_copy_bytecode(element) }
                when ::Dragonstone::Bytecode::MapValue
                    copied = ::Dragonstone::Bytecode::MapValue.new
                    value.entries.each do |k, v|
                        copied[deep_copy_bytecode(k)] = deep_copy_bytecode(v)
                    end
                    copied
                when ::Dragonstone::Bytecode::TupleValue
                    ::Dragonstone::Bytecode::TupleValue.new(value.elements.map { |element| deep_copy_bytecode(element) })
                when ::Dragonstone::Bytecode::NamedTupleValue
                    copied = {} of ::Dragonstone::SymbolValue => ::Dragonstone::Bytecode::Value
                    value.entries.each do |key, entry_value|
                        copied[key] = deep_copy_bytecode(entry_value)
                    end
                    nt = ::Dragonstone::Bytecode::NamedTupleValue.new
                    copied.each { |k, v| nt.entries[k] = v }
                    nt
                when ::Dragonstone::Bytecode::BagValue
                    bag = ::Dragonstone::Bytecode::BagValue.new(value.element_type)
                    value.elements.each { |element| bag.add(deep_copy_bytecode(element)) }
                    bag
                else
                    value
                end
            end
        end
    end

    record CompiledCode,
        code : Array(Int32),
        consts : Array(Bytecode::Value),
        names : Array(String),
        locals_count : Int32
end
