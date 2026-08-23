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

# Trailing `if` and `unless` modifiers previously worked 
# only with `break`, `next`, `redo`, and `retry`, because 
# those statements parsed the modifier themselves. Other 
# statements—such as assignments, `echo`, and 
# `return`—failed with `Expected END, got EOF`.
#
# Modifiers are now parsed once in `parse_statement`, so 
# they work consistently with every statement type.
describe "statement modifiers" do
    describe "if" do
        it "guards an assignment" do
            both_backends("c = true\nx = 1 if c\necho x\n", "1\n")
        end

        it "skips the assignment when false" do
            both_backends("d = false\ny = 0\ny = 1 if d\necho y\n", "0\n")
        end

        it "guards an echo" do
            both_backends("c = true\necho \"shown\" if c\necho \"also\" if false\n", "shown\n")
        end

        it "guards a return, giving the early-exit form" do
            source = <<-DS
            def f(n)
                return "big" if n > 10
                return "small"
            end
            echo f(20)
            echo f(2)
            DS
            both_backends(source + "\n", "big\nsmall\n")
        end
    end

    describe "unless" do
        it "guards an assignment" do
            both_backends("d = false\nz = 5 unless d\necho z\n", "5\n")
        end

        it "guards a return" do
            source = <<-DS
            def g(n)
                return "neg" unless n >= 0
                return "pos"
            end
            echo g(-1)
            echo g(1)
            DS
            both_backends(source + "\n", "neg\npos\n")
        end
    end

    describe "loop control" do
        it "still honours next and break modifiers" do
            source = <<-DS
            n = 0
            while n < 5
                n = n + 1
                next if n == 2
                break if n == 4
                echo n
            end
            DS
            both_backends(source + "\n", "1\n3\n")
        end

        it "honours an unless modifier on next" do
            source = <<-DS
            m = 0
            while m < 5
                m = m + 1
                next unless m == 3
                echo m
            end
            DS
            both_backends(source + "\n", "3\n")
        end
    end

    # The parser does not preserve newline tokens, so it must use source-line
    # positions to distinguish a trailing `if` modifier from an `if` block.
    #
    # An `if` is a modifier only when it appears on the same line as the preceding
    # statement. On a later line, it begins a block; treating it as a modifier
    # would allow `next` or `break` to consume the `if` and leave its `end`
    # unmatched.
    describe "line boundaries" do
        it "treats an if on the next line as a statement, not a modifier" do
            source = <<-DS
            c = true
            w = 1
            if c
                echo "block ran"
            end
            echo w
            DS
            both_backends(source + "\n", "block ran\n1\n")
        end

        it "does not let next swallow a following if block" do
            source = <<-DS
            n = 0
            while n < 3
                n = n + 1
                next
                if true
                    echo "unreachable"
                end
            end
            echo n
            DS
            both_backends(source + "\n", "3\n")
        end

        it "does not let break swallow a following if block" do
            source = <<-DS
            n = 0
            while n < 3
                n = n + 1
                break
                if true
                    echo "unreachable"
                end
            end
            echo n
            DS
            both_backends(source + "\n", "1\n")
        end
    end

    it "chains modifiers right-to-left" do
        both_backends("a = true\nb = false\nx = 0\nx = 1 if a unless b\necho x\n", "1\n")
    end
end
