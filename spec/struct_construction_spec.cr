require "spec"
require "../src/dragonstone"
require "../src/dragonstone/shared/language/lexer/lexer"
require "../src/dragonstone/shared/language/parser/parser"
require "../src/dragonstone/shared/language/sema/type_checker"
require "../src/dragonstone/shared/ir/program"
require "../src/dragonstone/core/compiler/compiler"
require "../src/dragonstone/core/vm/vm"

# A struct without an explicit `initialize` method accepts its declared fields
# as named arguments. This behavior is implemented separately in
# `initialize_struct_instance` in the interpreter and in the VM.
#
# The VM implementation was unreachable because `invoke_method` checked
# `Bytecode::ClassValue` before `Bytecode::StructValue`. Since
# `StructValue < ClassValue`, every struct matched the class branch first.
# That branch created a valid-looking instance but discarded the supplied
# arguments, so no error was raised and `p.x` simply returned `nil`.
#
# Each case in this group runs explicitly on the VM. `Dragonstone.run` cannot
# reliably expose VM-only failures: with `--backend auto`, the engine tries the
# VM first and falls back to the interpreter if the VM fails. A test using only
# `Dragonstone.run` can therefore pass using the interpreter result even when
# the VM raises, returns a different value, or does not support the feature.
#
# The helper runs the snippet directly on the VM, without the engine or backend
# fallback.
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

private def both_backends_raise(source : String, error : T.class, message : Regex) forall T
    expect_raises(error, message) { Dragonstone.run(source) }
    expect_raises(error, message) { run_on_vm(source) }
end

private POINT = <<-DS
struct Point
    property x: int
    property y: int
end

DS

describe "struct construction" do
    describe "the implicit constructor" do
        it "binds declared fields from named arguments" do
            both_backends(
                POINT + "p = Point.new(x: 1, y: 2)\necho p.x\necho p.y\n",
                "1\n2\n"
            )
        end

        # The braced form is a single positional argument containing a named tuple,
        # not a collection of named arguments. Both implementations handle it through
        # a separate code path.
        it "binds declared fields from a braced named tuple" do
            both_backends(
                POINT + "p = Point.new({x: 1, y: 2})\necho p.x\necho p.y\n",
                "1\n2\n"
            )
        end

        # `property` is not the only way to declare a field. A declaration such as
        # `@a: int` defines a field without generating an accessor.
        #
        # A backend that derives its field list only from generated getters would pass
        # the `property` case above but fail this one.
        it "binds fields declared without an accessor" do
            both_backends(
                "struct Pair\n    @a: int\n    @b: int\n\n    def sum\n        return @a + @b\n    end\nend\np = Pair.new(a: 3, b: 4)\necho p.sum\n",
                "7\n"
            )
        end

        it "leaves an explicit initialize in charge" do
            both_backends(
                "struct Box\n    def initialize(@w: int)\n    end\n\n    def w\n        return @w\n    end\nend\necho Box.new(5).w\n",
                "5\n"
            )
        end
    end

    describe "the implicit constructor's error paths" do
        it "rejects an attribute the struct does not declare" do
            both_backends_raise(
                POINT + "p = Point.new(x: 1, z: 2)\n",
                Dragonstone::NameError,
                /Unknown attribute 'z' for Point/
            )
        end

        it "rejects a construction that leaves a field unset" do
            both_backends_raise(
                POINT + "p = Point.new(x: 1)\n",
                Dragonstone::TypeError,
                /Point\.new missing required attributes: y/
            )
        end

        it "rejects arguments to a struct that declares no fields" do
            both_backends_raise(
                "struct Empty\nend\np = Empty.new(x: 1)\n",
                Dragonstone::TypeError,
                /Empty\.new expects 0 arguments, got 1/
            )
        end
    end

    # The VM matches named arguments against the callee’s signature. When no
    # signature is available—such as for a builtin or the struct constructor
    # above—it previously discarded the argument names and passed only the values.
    #
    # As a result, `[1, 2].includes?(value: 1)` was treated as a positional call
    # and incorrectly returned `true`. The interpreter has always rejected this
    # usage.
    describe "named arguments aimed at something that binds positionally" do
        it "rejects a named argument to a builtin method" do
            both_backends_raise(
                "echo [1, 2].includes?(value: 1)\n",
                Dragonstone::TypeError,
                /Array#includes\? does not take named arguments \('value:'\)/
            )
        end

        it "still accepts the same call positionally" do
            both_backends("echo [1, 2].includes?(1)\n", "true\n")
        end
    end
end
