require "set"
require "../compiler/compiler"
require "../interpreter/interpreter"
require "../resolver/loader"
require "../runtime/symbol"
require "../vm/vm"

module Dragonstone
    module Runtime
        module VMCompatibility
            extend self

            SUPPORTED_BINARY_OPERATORS = Set{:+, :"&+", :-, :"&-", :*, :"&*", :/, :==, :!=, :<, :<=, :>, :>=}
            SUPPORTED_UNARY_OPERATORS = Set{:+, :"&+", :-, :"&-", :!, :~}

            def supports?(program : AST::Program) : Bool
                nodes_supported?(program.statements)
            end

            private def nodes_supported?(nodes : Array(AST::Node)) : Bool
                nodes.all? { |node| node_supported?(node) }
            end

            private def node_supported?(node : AST::Node) : Bool
                case node
                when AST::Program
                    nodes_supported?(node.statements)
                when AST::Literal
                    true
                when AST::Variable
                    node.type_annotation.nil?
                when AST::Assignment
                    node.operator.nil? && node.type_annotation.nil? && node_supported?(node.value)
                when AST::BinaryOp
                    SUPPORTED_BINARY_OPERATORS.includes?(node.operator) &&
                        node_supported?(node.left) &&
                        node_supported?(node.right)
                when AST::UnaryOp
                    SUPPORTED_UNARY_OPERATORS.includes?(node.operator) &&
                        node_supported?(node.operand)
                when AST::MethodCall
                    return false if node.arguments.any? { |arg| arg.is_a?(AST::BlockLiteral) }
                    receiver_supported = node.receiver.nil? || node_supported?(node.receiver.not_nil!)
                    receiver_supported && nodes_supported?(node.arguments)
                when AST::IfStatement
                    cond_ok = node_supported?(node.condition)
                    then_ok = nodes_supported?(node.then_block)
                    elsif_ok = node.elsif_blocks.all? { |clause| node_supported?(clause.condition) && nodes_supported?(clause.block) }
                    else_ok = node.else_block.nil? || nodes_supported?(node.else_block.not_nil!)
                    cond_ok && then_ok && elsif_ok && else_ok
                when AST::WhileStatement
                    node_supported?(node.condition) && nodes_supported?(node.block)
                when AST::DebugPrint
                    node_supported?(node.expression)
                when AST::ArrayLiteral
                    nodes_supported?(node.elements)
                when AST::IndexAccess
                    !node.nil_safe && node_supported?(node.object) && node_supported?(node.index)
                when AST::InterpolatedString
                    interpolated_string_supported?(node)
                when AST::ReturnStatement
                    node.value.nil? || node_supported?(node.value.not_nil!)
                when AST::FunctionDef
                    function_supported?(node)
                else
                    false
                end
            end

            private def function_supported?(node : AST::FunctionDef) : Bool
                return false unless node.rescue_clauses.empty?
                return false unless node.typed_parameters.all? { |param| param.instance_var_name.nil? }
                nodes_supported?(node.body)
            end

            private def interpolated_string_supported?(node : AST::InterpolatedString) : Bool
                node.normalized_parts.all? do |type, content|
                    case type
                    when :string
                        true
                    when :expression
                        expression_node = interpolation_expression_node(content)
                        expression_node && node_supported?(expression_node)
                    else
                        false
                    end
                end
            end

            private def interpolation_expression_node(content) : AST::Node?
                return content.as(AST::Node) if content.is_a?(AST::Node)

                lexer = Lexer.new(content.to_s)
                tokens = lexer.tokenize
                parser = Parser.new(tokens)
                parser.parse_expression_entry
            rescue
                nil
            end
        end

        class ConstantBytecodeBinding
            getter value : Bytecode::Value

            def initialize(@value : Bytecode::Value)
            end
        end

        alias ExportValue = ScopeValue | Bytecode::Value | ConstantBytecodeBinding

        module ValueConversion
            private def ensure_runtime_value(value : ExportValue) : RuntimeValue
                case value
                when ConstantBinding
                    ensure_runtime_value(value.value)
                when ConstantBytecodeBinding
                    ensure_runtime_value(value.value)
                when Bytecode::Value
                    bytecode_to_runtime(value)
                else
                    value.as(RuntimeValue)
                end
            end

            private def ensure_bytecode_value(value : ExportValue) : Bytecode::Value
                case value
                when ConstantBinding
                    ensure_bytecode_value(value.value)
                when ConstantBytecodeBinding
                    ensure_bytecode_value(value.value)
                when Bytecode::Value
                    value
                else
                    runtime_to_bytecode(value.as(RuntimeValue))
                end
            end

            private def runtime_to_bytecode(value : RuntimeValue) : Bytecode::Value
                case value
                when Nil, Bool, Int32, Int64, Float64, String, Char, SymbolValue, FFIModule
                    value
                when Array
                    array = value.as(Array(RuntimeValue))
                    converted = [] of Bytecode::Value
                    array.each do |element|
                        converted << runtime_to_bytecode(element)
                    end
                    converted
                when Dragonstone::Function
                    convert_function_to_bytecode(value)
                else
                    raise "Cannot convert #{value.class} to bytecode value"
                end
            end

            private def bytecode_to_runtime(value : Bytecode::Value) : RuntimeValue
                case value
                when Nil, Bool, Int32, Int64, Float64, String, Char, SymbolValue, FFIModule
                    value
                when Array(Bytecode::Value)
                    array = value.as(Array(Bytecode::Value))
                    converted = [] of RuntimeValue
                    array.each do |element|
                        converted << bytecode_to_runtime(element)
                    end
                    converted
                else
                    raise "Cannot import #{value.class} into interpreter runtime"
                end
            end

            private def convert_function_to_bytecode(func : Dragonstone::Function) : Bytecode::Value
                raise "Cannot convert function with captured scope to bytecode value" unless func.closure.empty?
                raise "Cannot convert function with rescue clauses to bytecode value" unless func.rescue_clauses.empty?
                raise "Cannot convert function with instance variable parameters to bytecode value" unless func.typed_parameters.all? { |param| param.instance_var_name.nil? }

                compiler = Compiler.new
                chunk = compiler.compile_function_body(func.body)
                name_lookup = {} of String => Int32
                chunk.names.each_with_index do |candidate, index|
                    name_lookup[candidate] = index
                end
                params = [] of Bytecode::Value
                func.parameters.each do |param|
                    unless idx = name_lookup[param]?
                        raise "Parameter #{param} missing from compiled function names"
                    end
                    params << idx
                end
                name = func.name || "<lambda>"
                {name: name, params: params, code: chunk}
            end
        end

        abstract class Backend
            include ValueConversion

            getter output : String

            def initialize(@log_to_stdout : Bool)
                @output = ""
            end

            abstract def import_variable(name : String, value : ExportValue) : Nil
            abstract def import_constant(name : String, value : ExportValue) : Nil
            abstract def export_namespace : Hash(String, ExportValue)
            abstract def execute(ast : AST::Program) : Nil
        end

        class InterpreterBackend < Backend
            getter interpreter : Interpreter

            def initialize(interpreter : Interpreter, log_to_stdout : Bool)
                super(log_to_stdout)
                @interpreter = interpreter
            end

            def import_variable(name : String, value : ExportValue) : Nil
                runtime_value = ensure_runtime_value(value)
                @interpreter.import_variable(name, runtime_value)
            end

            def import_constant(name : String, value : ExportValue) : Nil
                runtime_value = ensure_runtime_value(value)
                @interpreter.import_constant(name, runtime_value)
            end

            def export_namespace : Hash(String, ExportValue)
                snapshot = {} of String => ExportValue
                @interpreter.export_scope_snapshot.each do |name, value|
                    snapshot[name] = value
                end
                snapshot
            end

            def execute(ast : AST::Program) : Nil
                @interpreter.interpret(ast)
                @output = @interpreter.output
            end
        end

        class VMBackend < Backend
            def initialize(log_to_stdout : Bool)
                super(log_to_stdout)
                @globals = {} of String => Bytecode::Value
                @constant_names = Set(String).new
            end

            def import_variable(name : String, value : ExportValue) : Nil
                @globals[name] = ensure_bytecode_value(value)
                @constant_names.delete(name)
            end

            def import_constant(name : String, value : ExportValue) : Nil
                @globals[name] = ensure_bytecode_value(value)
                @constant_names.add(name)
            end

            def export_namespace : Hash(String, ExportValue)
                snapshot = {} of String => ExportValue
                @globals.each do |name, value|
                    if @constant_names.includes?(name)
                        snapshot[name] = ConstantBytecodeBinding.new(value)
                    else
                        snapshot[name] = value
                    end
                end
                snapshot
            end

            def execute(ast : AST::Program) : Nil
                compiled = Compiler.compile(ast)
                stdout_io = IO::Memory.new
                vm = VM.new(compiled, globals: @globals, stdout_io: stdout_io, log_to_stdout: @log_to_stdout)
                vm.run
                @output = stdout_io.to_s
                @globals = vm.export_globals
                prune_constant_names
            end

            private def prune_constant_names : Nil
                kept = Set(String).new
                @constant_names.each do |name|
                    kept.add(name) if @globals.has_key?(name)
                end
                @constant_names = kept
            end
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

            def execute(ast : AST::Program) : Nil
                @backend.execute(ast)
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

        class Engine
            getter unit_cache : Hash(String, Unit)

            def initialize(@resolver : ModuleResolver, @log_to_stdout : Bool = false, @typing_enabled : Bool = false)
                @unit_cache = {} of String => Unit
            end

            def compile_or_eval(ast : AST::Program, path : String, typed : Bool? = nil) : Unit
                node = @resolver.graph[path]
                node_typed = node && node.typed
                typing_flag = if !typed.nil?
                    typed
                elsif node_typed
                    true
                else
                    @typing_enabled
                end

                backends = backend_candidates(ast, typing_flag)
                last_error = nil

                backends.each_with_index do |backend, index|
                    unit = Unit.new(path, backend)
                    importer = Importer.new(@resolver, self)
                    begin
                        ast.use_decls.each do |use_decl|
                            importer.apply_imports(unit, use_decl, path)
                        end
                        unit.execute(ast)
                        unit.capture_exports!
                        @unit_cache[path] = unit
                        return unit
                    rescue ex
                        last_error = ex
                        raise ex if index == backends.size - 1
                    end
                end

                raise last_error if last_error
                raise "Failed to build runtime unit for #{path}"
            end

            private def backend_candidates(ast : AST::Program, typing_flag : Bool) : Array(Backend)
                candidates = [] of Backend
                if !typing_flag && VMCompatibility.supports?(ast)
                    candidates << VMBackend.new(@log_to_stdout)
                end
                interpreter = Interpreter.new(log_to_stdout: @log_to_stdout, typing_enabled: typing_flag)
                candidates << InterpreterBackend.new(interpreter, @log_to_stdout)
                candidates
            end
        end
    end
end
