require "set"
require "../core/compiler/compiler"
require "../native/interpreter/interpreter"
require "../shared/ir/lowering"
require "../shared/language/resolver/resolver"
require "../shared/language/resolver/module_metadata"
require "../shared/language/resolver/loader"
require "../shared/language/sema/type_checker"
require "../shared/runtime/runtime_env"
require "../core/vm/bytecode"
require "../core/vm/vm"

module Dragonstone
    module Runtime
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
                when TupleValue
                    elements = value.elements.map { |element| runtime_to_bytecode(element) }
                    Bytecode::TupleValue.new(elements)
                when NamedTupleValue
                    tuple = Bytecode::NamedTupleValue.new
                    value.entries.each do |key, entry_value|
                        tuple.entries[key] = runtime_to_bytecode(entry_value)
                    end
                    tuple
                when DragonModule
                    Bytecode::ModuleValue.new(value.name)
                when DragonClass
                    Bytecode::ClassValue.new(value.name, nil, value.abstract?)
                when DragonInstance
                    Bytecode::InstanceValue.new(Bytecode::ClassValue.new(value.klass.name, nil, value.klass.abstract?))
                when DragonEnumMember
                    enum_val = Bytecode::EnumValue.new(value.enum.name)
                    Bytecode::EnumMemberValue.new(enum_val, value.name, value.value)
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
                when Bytecode::TupleValue
                    elements = [] of RuntimeValue
                    value.elements.each do |element|
                        elements << bytecode_to_runtime(element)
                    end
                    TupleValue.new(elements)
                when Bytecode::NamedTupleValue
                    entries = {} of SymbolValue => RuntimeValue
                    value.entries.each do |key, entry_value|
                        entries[key] = bytecode_to_runtime(entry_value)
                    end
                    NamedTupleValue.new(entries)
                when Bytecode::MapValue
                    map = MapValue.new
                    value.entries.each do |k, v|
                        map[bytecode_to_runtime(k)] = bytecode_to_runtime(v)
                    end
                    map
                when Bytecode::BagValue
                    bag = BagValue.new(nil)
                    value.elements.each { |element| bag.add(bytecode_to_runtime(element)) }
                    bag
                when Bytecode::BagConstructorValue
                    BagConstructor.new(Typing::SimpleDescriptor.new("dynamic"), AST::SimpleTypeExpression.new("dynamic"))
                when Bytecode::ModuleValue
                    DragonModule.new(value.name)
                when Bytecode::ClassValue
                    DragonClass.new(value.name, is_abstract: value.abstract?)
                when Bytecode::InstanceValue
                    DragonInstance.new(DragonClass.new(value.klass.name, is_abstract: value.klass.abstract?))
                when Bytecode::EnumValue
                    DragonEnum.new(value.name)
                when Bytecode::EnumMemberValue
                    DragonEnumMember.new(DragonEnum.new(value.enum.name), value.name, value.value)
                when Bytecode::GCHost
                    Runtime::GC::Host.new(Runtime::GC::Manager(RuntimeValue).new(
                        ->(v : RuntimeValue) { v },
                        -> { ::GC.disable },
                        -> { ::GC.enable }
                    ))
                when ::Dragonstone::Runtime::GC::Area(Bytecode::Value)
                    Runtime::GC::Area(RuntimeValue).new
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
                param_specs = [] of Bytecode::ParameterSpec
                func.typed_parameters.each do |param|
                    name = param.name
                    unless idx = name_lookup[name]?
                        raise "Parameter #{name} missing from compiled function names"
                    end
                    param_specs << Bytecode::ParameterSpec.new(idx, param.type, param.instance_var_name)
                end
                signature = Bytecode::FunctionSignature.new(param_specs, func.return_type, false)
                name = func.name || "<lambda>"
                Bytecode::FunctionValue.new(name, signature, chunk, signature.abstract?)
            end
        end

        class Backend
            include ValueConversion
        end

        class InterpreterBackend < Backend
            getter interpreter : Interpreter

            def initialize(interpreter : Interpreter, resolver : ModuleResolver, log_to_stdout : Bool)
                super(log_to_stdout)
                @interpreter = interpreter
                @resolver = resolver
            end

            def backend_mode : BackendMode
                BackendMode::Native
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

            def execute(program : IR::Program) : Nil
                graph = @resolver.graph
                @interpreter.interpret(program, graph)
                @output = @interpreter.output
            end
        end

        class VMBackend < Backend
            def initialize(log_to_stdout : Bool)
                super(log_to_stdout)
                @globals = {} of String => Bytecode::Value
                @constant_names = Set(String).new
            end

            def backend_mode : BackendMode
                BackendMode::Core
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

            def execute(program : IR::Program) : Nil
                options = Core::Compiler::BuildOptions.new(target: Core::Compiler::Target::Bytecode)
                artifact = Core::Compiler.build(program, options)
                compiled = artifact.bytecode
                raise "Bytecode generation failed for target #{options.target}" unless compiled
                stdout_io = IO::Memory.new
                vm = VM.new(
                    compiled,
                    globals: @globals,
                    stdout_io: stdout_io,
                    log_to_stdout: @log_to_stdout,
                    typing_enabled: program.typed?
                )
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

        class Engine
            getter unit_cache : Hash(Tuple(String, BackendMode), Unit)

            def initialize(
                @resolver : ModuleResolver,
                @log_to_stdout : Bool = false,
                @typing_enabled : Bool = false,
                @backend_mode : BackendMode = BackendMode::Auto
            )
                @unit_cache = {} of Tuple(String, BackendMode) => Unit
            end

            def compile_or_eval(
                ast : AST::Program,
                path : String,
                typed : Bool? = nil,
                analysis : Language::Sema::AnalysisResult? = nil,
                preferred_backend : BackendMode? = nil
            ) : Unit
                node = @resolver.graph[path]
                node_typed = node && node.typed
                typing_flag = if analysis
                    analysis.typed
                elsif !typed.nil?
                    typed
                elsif node_typed
                    true
                else
                    @typing_enabled
                end
                analysis ||= Language::Sema::TypeChecker.new.analyze(ast, typed: typing_flag)
                program = IR::Lowering.lower(ast, analysis)
                compile_or_eval(program, path, typing_flag, preferred_backend)
            end

            def compile_or_eval(
                program : IR::Program,
                path : String,
                typed : Bool? = nil,
                preferred_backend : BackendMode? = nil
            ) : Unit
                typing_flag = typed.nil? ? program.typed? : typed
                backends = backend_candidates(program, typing_flag, preferred_backend)
                last_error = nil

                backends.each_with_index do |backend, index|
                    unit = Unit.new(path, backend)
                    importer = Importer.new(@resolver, self)
                    begin
                        program.ast.use_decls.each do |use_decl|
                            importer.apply_imports(unit, use_decl, path)
                        end
                        unit.execute(program)
                        unit.capture_exports!
                        @unit_cache[{path, unit.backend.backend_mode}] = unit
                        return unit
                    rescue ex
                        last_error = ex
                        raise ex if index == backends.size - 1
                    end
                end

                raise last_error if last_error
                raise "Failed to build runtime unit for #{path}"
            end

            private def backend_candidates(program : IR::Program, typing_flag : Bool, preferred_backend : BackendMode?) : Array(Backend)
                candidates = [] of Backend
                native_only_modules = metadata_conflicts_for(BackendMode::Core)
                core_only_modules = metadata_conflicts_for(BackendMode::Native)

                case @backend_mode
                when BackendMode::Core
                    ensure_core_supported!(program, typing_flag)
                    ensure_no_metadata_conflicts!(BackendMode::Core, native_only_modules)
                    candidates << VMBackend.new(@log_to_stdout)
                when BackendMode::Native
                    ensure_no_metadata_conflicts!(BackendMode::Native, core_only_modules)
                    candidates << build_interpreter_backend(typing_flag)
                else
                    allow_vm = native_only_modules.empty? && !typing_flag && IR::Lowering::Supports.vm?(program.ast)
                    allow_interpreter = core_only_modules.empty?

                    # Reorder preference to keep imports on the same backend when possible.
                    if preferred_backend == BackendMode::Native
                        candidates << build_interpreter_backend(typing_flag) if allow_interpreter
                        candidates << VMBackend.new(@log_to_stdout) if allow_vm
                    else
                        candidates << VMBackend.new(@log_to_stdout) if allow_vm
                        candidates << build_interpreter_backend(typing_flag) if allow_interpreter
                    end

                    if candidates.empty?
                        raise_no_available_backend!(native_only_modules, core_only_modules)
                    end
                end

                candidates
            end

            private def build_interpreter_backend(typing_flag : Bool) : Backend
                interpreter = Interpreter.new(log_to_stdout: @log_to_stdout, typing_enabled: typing_flag)
                InterpreterBackend.new(interpreter, @resolver, @log_to_stdout)
            end

            private def ensure_core_supported!(program : IR::Program, typing_flag : Bool)
                unless IR::Lowering::Supports.vm?(program.ast)
                    failure = IR::Lowering::Supports.last_failure
                    detail = failure ? " (unsupported node: #{failure})" : ""
                    raise RuntimeError.new(
                        "Core backend cannot execute this program yet#{detail}.",
                        hint: "Use --backend native until VM coverage expands."
                    )
                end
            end

            private def metadata_conflicts_for(backend : BackendMode) : Array(Stdlib::ModuleMetadata)
                conflicts = [] of Stdlib::ModuleMetadata
                @resolver.graph.nodes.each_value do |node|
                    metadata = node.metadata
                    next unless metadata
                    conflicts << metadata unless metadata.supports_backend?(backend)
                end
                conflicts
            end

            private def ensure_no_metadata_conflicts!(backend : BackendMode, conflicts : Array(Stdlib::ModuleMetadata))
                return if conflicts.empty?
                names = conflicts.map(&.description).join(", ")
                message = case backend
                    when BackendMode::Core
                        "Native-only stdlib module(s) detected: #{names}."
                    when BackendMode::Native
                        "Core-only stdlib module(s) detected: #{names}."
                    else
                        "Incompatible stdlib module(s) detected: #{names}."
                    end
                hint = backend == BackendMode::Core ? "Use --backend native or drop the module(s)." : "Use --backend core or drop the module(s)."
                raise RuntimeError.new(
                    "Cannot use #{backend.label} backend. #{message}",
                    hint: hint
                )
            end

            private def raise_no_available_backend!(
                native_only : Array(Stdlib::ModuleMetadata),
                core_only : Array(Stdlib::ModuleMetadata)
            )
                parts = [] of String
                if native_only.any?
                    parts << "native-only modules: #{native_only.map(&.description).join(", ")}"
                end
                if core_only.any?
                    parts << "core-only modules: #{core_only.map(&.description).join(", ")}"
                end
                detail = parts.join("; ")
                raise RuntimeError.new(
                    "No compatible backend available for required stdlib modules (#{detail}).",
                    hint: "Remove conflicting modules or pin an explicit backend."
                )
            end
        end
    end
end
