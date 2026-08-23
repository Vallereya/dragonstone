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

# These callable forms differ primarily in how `return` behaves:
#
# - `|...|` blocks capture their surrounding context and can only be passed
#   directly as method arguments. Their `return` is non-local: it returns from
#   the method that defined the block.
# - `fun` is a non-capturing function pointer, similar to a C function pointer.
#   Its `return` exits only that function.
# - `para` is a capturing lambda, similar to a C++ lambda. Its `return` exits
#   only that lambda.
#
# Previously, a `return` inside a block was handled at the call site instead of
# returning from the enclosing method. The enclosing method then continued
# executing and returned the value produced after the loop.
describe "return from a block" do
    it "returns from the method that wrote the block, not from the iterator" do
        source = <<-DS
        def pick(items)
            items.each do |x|
                if x == "b"
                    return x
                end
            end
            return "not found"
        end
        echo pick(["a", "b", "c"])
        DS
        both_backends(source + "\n", "b\n")
    end

    it "still falls through when the block never returns" do
        source = <<-DS
        def pick(items)
            items.each do |x|
                if x == "zzz"
                    return x
                end
            end
            return "not found"
        end
        echo pick(["a", "b"])
        DS
        both_backends(source + "\n", "not found\n")
    end

    # This case verifies that a block's `return` retains its original target.
    # `takes_block` creates a real call frame between the block and its defining
    # method, but it must not intercept the return.
    it "passes through a method that merely yielded to the block" do
        source = <<-DS
        def takes_block
            yield 1
            yield 2
            return "yield finished"
        end

        def outer
            takes_block do |n|
                if n == 1
                    return "returned from outer"
                end
            end
            return "outer finished"
        end
        echo outer()
        DS
        both_backends(source + "\n", "returned from outer\n")
    end

    it "returns through nested blocks to the enclosing method" do
        source = <<-DS
        def nested
            [1, 2].each do |a|
                [10, 20].each do |b|
                    if b == 20
                        return "nested"
                    end
                end
            end
            return "nested finished"
        end
        echo nested()
        DS
        both_backends(source + "\n", "nested\n")
    end

    it "does not disturb a block that yields a value normally" do
        source = <<-DS
        def doubled(items)
            return items.map do |x|
                x * 2
            end
        end
        echo doubled([1, 2, 3])
        DS
        both_backends(source + "\n", "[2, 4, 6]\n")
    end

    # `fun` is a non-capturing function pointer: its `return` is its own.
    it "keeps return local inside a fun literal" do
        source = <<-'DS'
        doubler = fun(x)
            return x * 2
        end

        def uses_fun(f)
            r = f.call(5)
            return "got #{r}"
        end
        echo uses_fun(doubler)
        DS
        both_backends(source + "\n", "got 10\n")
    end

    # `para` is a capturing lambda: also its own return, despite capturing.
    it "keeps return local inside a para literal" do
        source = <<-'DS'
        def uses_para
            p = ->(x: int) {
                return x + 100
            }
            r = p.call(5)
            return "got #{r}"
        end
        echo uses_para()
        DS
        both_backends(source + "\n", "got 105\n")
    end

    # A block body executes in a new inner scope. Previously, `self` was read
    # only from that scope, so bare method calls and `@ivar` access inside blocks
    # failed—even though the same expressions worked outside the block.
    describe "self inside a block" do
        it "finds a sibling method called bare" do
            source = <<-DS
            class C
                def initialize
                end
                def double(x)
                    return x * 2
                end
                def run(items)
                    out = [] as int
                    items.each do |i|
                        out << double(i)
                    end
                    return out
                end
            end
            echo C.new.run([1, 2])
            DS
            both_backends(source + "
", "[2, 4]
")
        end

        it "reads an instance variable" do
            source = <<-DS
            class C
                def initialize
                    @n = 10
                end
                def run(items)
                    total = 0
                    items.each do |i|
                        total = total + @n
                    end
                    return total
                end
            end
            echo C.new.run([1, 2])
            DS
            both_backends(source + "
", "20
")
        end
    end

    it "leaves break and next alone" do
        source = <<-DS
        def scan(items)
            seen = [] as str
            items.each do |x|
                next if x == "skip"
                break if x == "stop"
                seen << x
            end
            return seen.join(",")
        end
        echo scan(["a", "skip", "b", "stop", "c"])
        DS
        both_backends(source + "\n", "a,b\n")
    end
end
