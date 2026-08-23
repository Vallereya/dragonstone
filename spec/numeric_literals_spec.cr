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

# These numeric forms previously failed to lex correctly—and failed silently.
# `scan_number` read only the initial decimal digits, then treated the remaining
# characters as a separate identifier.
#
# As a result, `0xEF` evaluated as `0` and `1_000` as `1`, without producing an
# error. Each case below prevents those regressions from returning.
describe "numeric literals" do
    describe "radix prefixes" do
        {
            "0xEF"       => "239",
            "0xff"       => "255",
            "0XFF"       => "255",
            "0b1010"     => "10",
            "0B1010"     => "10",
            "0o17"       => "15",
            "0O17"       => "15",
            "0x0"        => "0",
            "0xFFFFFFFF" => "4294967295",
        }.each do |literal, expected|
            it "lexes #{literal} as #{expected}" do
                both_backends("echo #{literal}\n", "#{expected}\n")
            end
        end

        it "keeps a bare 0 separate when no valid digit follows the marker" do
            # `0x` is not a hexadecimal literal without at least one hexadecimal digit.
            # It is therefore tokenized as the integer `0` followed by the identifier `x`,
            # preserving the existing behavior. The undefined identifier is what produces
            # the error.
            expect_raises(Dragonstone::NameError, /Unknown method or variable: x/) do
                Dragonstone.run("echo 0x\n")
            end
        end
    end

    describe "underscore separators" do
        {
            "1_000"     => "1000",
            "1_000_000" => "1000000",
            "0xDE_AD"   => "57005",
            "0b1010_1010" => "170",
            "1_000.5"   => "1000.5",
            "1.000_1"   => "1.0001",
        }.each do |literal, expected|
            it "drops the separators in #{literal}" do
                both_backends("echo #{literal}\n", "#{expected}\n")
            end
        end

        # Because `_` can begin an identifier, a trailing underscore previously caused
        # the lexer to split the literal and silently produce the wrong numeric value.
        it "rejects a trailing underscore instead of splitting the literal" do
            expect_raises(Dragonstone::LexerError, /Trailing '_' in number literal/) do
                Dragonstone.run("echo 1_\n")
            end
        end

        it "rejects a trailing underscore in a radix literal" do
            expect_raises(Dragonstone::LexerError, /Trailing '_' in number literal/) do
                Dragonstone.run("echo 0xFF_\n")
            end
        end
    end

    describe "exponents" do
        {
            "1e5"       => "100000",
            "1E5"       => "100000",
            "2e+8"      => "200000000",
            "1.5e-3"    => "0.0015",
            "1_000.5e2" => "100050",
        }.each do |literal, expected|
            it "lexes #{literal} as #{expected}" do
                both_backends("echo #{literal}\n", "#{expected}\n")
            end
        end

        it "leaves a bare 1e as an integer followed by an identifier" do
            # Without a digit after the exponent marker, there is no exponent to parse.
            # The `e` is therefore left as an identifier, which then fails as undefined.
            expect_raises(Dragonstone::NameError, /Unknown method or variable: e/) do
                Dragonstone.run("echo 1e\n")
            end
        end
    end

    describe "existing forms still lex" do
        it "keeps plain integers and floats" do
            both_backends("echo 255\necho 1.5\necho 0\n", "255\n1.5\n0\n")
        end

        # When checking for a fractional part, the lexer must not consume the first `.`
        # of a range operator.
        it "does not break range literals" do
            both_backends("r = 1..5\nr.each do |i|\n    echo i\nend\n", "1\n2\n3\n4\n5\n")
        end

        # `5.to_f` must be parsed as a method call on the integer `5`, not as the
        # float literal `5.` followed by an identifier. Adding `0.5` verifies that the
        # conversion occurred, because `echo` renders both `5` and `5.0` as `"5"`.
        #
        # This test runs only on the interpreter. The VM currently does not dispatch
        # methods on integers, so no integer method call works there. That limitation
        # predates this lexer behavior and is unrelated to the test: both backends use
        # the same token stream, so the interpreter is sufficient to verify parsing.
        it "still allows a method call on an integer" do
            Dragonstone.run("echo 5.to_f + 0.5\n").output.should eq("5.5\n")
        end
    end

    describe "out of range" do
        it "reports a decimal literal too large for Int rather than crashing" do
            expect_raises(Dragonstone::LexerError, /out of range/) do
                Dragonstone.run("echo 99999999999999999999\n")
            end
        end

        it "reports a radix literal too large for Int" do
            expect_raises(Dragonstone::LexerError, /out of range/) do
                Dragonstone.run("echo 0xFFFFFFFFFFFFFFFFF\n")
            end
        end
    end
end
