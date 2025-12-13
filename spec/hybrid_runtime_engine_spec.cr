require "spec"
require "../src/dragonstone/shared/language/lexer/lexer"
require "../src/dragonstone/shared/language/parser/parser"
require "../src/dragonstone/shared/language/sema/type_checker"
require "../src/dragonstone/shared/ir/program"
require "../src/dragonstone/hybrid/runtime_engine"

class SpecFakeBackend < Dragonstone::Runtime::Backend
    getter executed : Bool

    def initialize(@should_fail : Bool = false, @label : String = "spec-backend", @mode : Dragonstone::BackendMode = Dragonstone::BackendMode::Auto)
        super(false)
        @executed = false
        @bindings = {} of String => Dragonstone::Runtime::ExportValue
    end

    def import_variable(name : String, value : Dragonstone::Runtime::ExportValue) : Nil
        @bindings[name] = value
    end

    def import_constant(name : String, value : Dragonstone::Runtime::ExportValue) : Nil
        @bindings[name] = value
    end

    def export_namespace : Hash(String, Dragonstone::Runtime::ExportValue)
        @bindings.dup
    end

    def backend_mode : Dragonstone::BackendMode
        @mode
    end

    def execute(program : Dragonstone::IR::Program) : Nil
        @executed = true
        raise "backend failure" if @should_fail
        @output = @label
    end
end

class SpecRuntimeEngine < Dragonstone::Runtime::Engine
    def initialize(resolver : Dragonstone::ModuleResolver, @static_backends : Array(Dragonstone::Runtime::Backend))
        super(resolver)
    end

    private def backend_candidates(program : Dragonstone::IR::Program, typing_flag : Bool, preferred_backend : Dragonstone::BackendMode?) : Array(Dragonstone::Runtime::Backend)
        @static_backends
    end
end

private def build_program(source : String)
    lexer = Dragonstone::Lexer.new(source, source_name: "<spec>")
    tokens = lexer.tokenize
    parser = Dragonstone::Parser.new(tokens)
    ast = parser.parse
    analysis = Dragonstone::Language::Sema::TypeChecker.new.analyze(ast, typed: false)
    program = Dragonstone::IR::Program.new(ast, analysis)

    path = File.expand_path("spec_fallback.ds", Dir.current)
    resolver = Dragonstone::ModuleResolver.new(Dragonstone::ModuleConfig.new([Dir.current]))
    resolver.graph.add(Dragonstone::ModuleNode.new(path, ast, false))
    resolver.cache.set(path, ast)

    {program, resolver, path}
end

describe Dragonstone::Runtime::Engine do
    it "falls back to the interpreter backend when the compiled backend fails" do
        program, resolver, path = build_program(%(echo "fallback"))
        vm_backend = SpecFakeBackend.new(should_fail: true, label: "vm-backend", mode: Dragonstone::BackendMode::Core)
        native_backend = SpecFakeBackend.new(false, "native-backend", Dragonstone::BackendMode::Native)
        backends = [] of Dragonstone::Runtime::Backend
        backends << vm_backend
        backends << native_backend

        engine = SpecRuntimeEngine.new(resolver, backends)
        unit = engine.compile_or_eval(program, path, false)

        vm_backend.executed.should be_true
        native_backend.executed.should be_true
        unit.backend.should eq(native_backend)
        unit.output.should eq("native-backend")
    end
end
