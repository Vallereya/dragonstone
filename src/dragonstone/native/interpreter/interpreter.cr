# ---------------------------------
# ---------- Interpreter ----------
# ---------------------------------
require "../../shared/language/diagnostics/errors"
require "../../shared/language/ast/ast"
require "../../shared/language/sema/type_checker"
require "../../shared/language/resolver/resolver"
require "../../shared/typing/types"
require "../../shared/runtime/ffi_module"
require "../../shared/runtime/symbol"
require "../../shared/ffi/ffi"
require "../../shared/ir/program"
require "../runtime/values"
require "./values/signals"
require "./values/runtime_helpers"
require "./env/context"
require "./builtins/dispatch"
require "./builtins/runtime_calls"
require "./evaluator/visitor"
require "./repl/session"

module Dragonstone
    class Interpreter
        getter output : String
        getter argv : Array(String)
        getter argv_value : Array(RuntimeValue)
        getter builtin_stdout : BuiltinStream
        getter builtin_stderr : BuiltinStream
        getter builtin_stdin : BuiltinStdin
        getter builtin_argf : BuiltinArgf
        @type_scopes : Array(TypeScope)
        @typing_context : Typing::Context?
        @descriptor_cache : Typing::DescriptorCache
        @module_graph : ModuleGraph?

        def initialize(argv : Array(String) = [] of String, log_to_stdout : Bool = false, typing_enabled : Bool = false)
            @global_scope = Scope.new
            @scopes = [@global_scope]
            @type_scopes = [new_type_scope]
            @typing_enabled = typing_enabled
            @descriptor_cache = Typing::DescriptorCache.new
            @typing_context = nil
            @output = String.new
            @log_to_stdout = log_to_stdout
            @debug_inline_sources = [] of String
            @debug_inline_values = [] of String
            @argv = argv.dup
            @argv_value = @argv.map { |arg| arg.as(RuntimeValue) }
            @container_stack = [] of DragonModule
            @loop_depth = 0
            @rescue_depth = 0
            @exception_stack = [] of InterpreterError
            @container_definition_depth = 0
            @type_aliases = {} of String => AST::TypeExpression
            @alias_descriptor_cache = {} of String => Typing::Descriptor
            @block_stack = [] of Function?
            @method_call_stack = [] of MethodCallFrame
            @singleton_classes = {} of UInt64 => SingletonClass
            @module_graph = nil
            set_variable("ffi", FFIModule.new)
            @gc_manager = Runtime::GC::Manager(RuntimeValue).new(
                ->(value : RuntimeValue) : RuntimeValue { Runtime::GC.deep_copy_runtime(value) },
                -> { ::GC.disable },
                -> { ::GC.enable }
            )
            set_variable("gc", Runtime::GC::Host.new(@gc_manager))
            @builtin_stdout = BuiltinStream.new(BuiltinStream::Kind::Stdout)
            @builtin_stderr = BuiltinStream.new(BuiltinStream::Kind::Stderr)
            @builtin_stdin = BuiltinStdin.new
            @builtin_argf = BuiltinArgf.new
        end

        def typing_enabled? : Bool
            @typing_enabled
        end

        def interpret(program : IR::Program, graph : ModuleGraph) : String
            interpret(program.ast, graph, program.analysis)
        end

        def interpret(ast : AST::Program, graph : ModuleGraph, _analysis : Language::Sema::AnalysisResult? = nil) : String
            previous_graph = @module_graph
            @module_graph = graph
            ast.accept(self)
            flush_debug_inline
            @output
        ensure
            @module_graph = previous_graph
        end
    end
end
