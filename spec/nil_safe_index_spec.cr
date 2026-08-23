require "spec"
require "../src/dragonstone"
require "../src/dragonstone/shared/language/lexer/lexer"
require "../src/dragonstone/shared/language/parser/parser"
require "../src/dragonstone/shared/language/sema/type_checker"
require "../src/dragonstone/shared/ir/program"
require "../src/dragonstone/core/compiler/compiler"
require "../src/dragonstone/core/vm/vm"

private def run_on_vm(source : String) : String
    tokens = Dragonstone::Lexer.new(source).tokenize
    ast = Dragonstone::Parser.new(tokens).parse
    checker = Dragonstone::Language::Sema::TypeChecker.new
    analysis = checker.analyze(ast)
    program = Dragonstone::IR::Program.new(ast, analysis)
    bytecode = Dragonstone::Core::Compiler.build(program).bytecode.not_nil!

    output = IO::Memory.new
    Dragonstone::VM.new(bytecode, stdout_io: output).run
    output.to_s
end

private def both_backends(source : String, expected : String)
    Dragonstone.run(source).output.should eq(expected)
    run_on_vm(source).should eq(expected)
end

    # `obj[i]?` returns `nil` when `obj` is `nil`. The VM previously rejected
    # this form entirely, which prevented it from running `ast.ds`, a dependency
    # used throughout the rest of the system.
describe "nil-safe index access" do
    it "reads a present key" do
        both_backends("m = { \"a\" -> 1 }\necho m[\"a\"]?\n", "1\n")
    end

    it "yields nil for a missing key" do
        both_backends("m = { \"a\" -> 1 }\necho m[\"z\"]?.nil?\n", "true\n")
    end

    it "yields nil for a nil receiver instead of raising" do
        both_backends("n = nil\necho n[\"a\"]?.nil?\n", "true\n")
    end

    it "works on arrays, in range and out" do
        both_backends("a = [10, 20]\necho a[0]?\necho a[9]?.nil?\n", "10\ntrue\n")
    end

    # When the receiver is `nil`, the interpreter returns before evaluating the
    # index expression. The VM must preserve that lazy behavior, so it compiles
    # the operation as a conditional jump rather than handling `nil` inside the
    # indexing opcode. By the time an opcode executes, both operands have already
    # been evaluated and pushed onto the stack.
    it "does not evaluate the index when the receiver is nil" do
        source = <<-'DS'
        def side(tag)
            echo "evaluated #{tag}"
            return 0
        end
        z = nil
        echo z[side("nil-receiver")]?.nil?
        ok = [1]
        echo ok[side("live-receiver")]?
        DS
        both_backends(source + "\n", "true\nevaluated live-receiver\n1\n")
    end

    describe "assignment" do
        it "assigns through a live receiver" do
            both_backends("h = { \"k\" -> 1 }\nh[\"k\"]?= 5\necho h[\"k\"]?\n", "5\n")
        end

        it "is a no-op on a nil receiver" do
            both_backends("q = nil\nq[\"k\"]?= 9\necho \"survived\"\n", "survived\n")
        end
    end
end
