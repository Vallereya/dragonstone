require "../ir/program"
require "../../core/vm/bytecode"
require "../../native/runtime/values"

module Dragonstone
    module Runtime
        class ConstantBytecodeBinding
            getter value : Bytecode::Value

            def initialize(@value : Bytecode::Value)
            end
        end

        alias ExportValue = ScopeValue | Bytecode::Value | ConstantBytecodeBinding

        abstract class Backend
            getter output : String

            def initialize(@log_to_stdout : Bool)
                @output = ""
            end

            abstract def import_variable(name : String, value : ExportValue) : Nil
            abstract def import_constant(name : String, value : ExportValue) : Nil
            abstract def export_namespace : Hash(String, ExportValue)
            abstract def execute(program : IR::Program) : Nil
        end

        class Unit
            getter path : String
            getter backend : Backend
            getter exports : Hash(String, ExportValue)

            def initialize(@path : String, @backend : Backend)
                @exports = {} of String => ExportValue
            end

            def bind(name : String, value : ExportValue)
                @backend.import_variable(name, value)
            end

            def bind_namespace(namespace : Hash(String, ExportValue))
                namespace.each do |name, scope_value|
                    bind_scope_value(name, scope_value)
                end
            end

            def exported_lookup(name : String) : ExportValue?
                if value = @exports[name]?
                    case value
                    when ConstantBinding
                        value.value
                    when ConstantBytecodeBinding
                        value.value
                    else
                        value
                    end
                end
            end

            def default_namespace : Hash(String, ExportValue)
                @exports
            end

            def capture_exports!
                @exports = @backend.export_namespace
            end

            def execute(program : IR::Program) : Nil
                @backend.execute(program)
            end

            def output : String
                @backend.output
            end

            private def bind_scope_value(name : String, value : ExportValue)
                case value
                when ConstantBinding
                    @backend.import_constant(name, value.value)
                when ConstantBytecodeBinding
                    @backend.import_constant(name, value.value)
                else
                    @backend.import_variable(name, value)
                end
            end
        end
    end
end
