require "spec"
require "../src/dragonstone"
require "../src/dragonstone/shared/language/lexer/lexer"
require "../src/dragonstone/shared/language/parser/parser"

private def parse(source : String)
    tokens = Dragonstone::Lexer.new(source).tokenize
    Dragonstone::Parser.new(tokens).parse
end

# Crystal-style type parameters, such as `class Box(T)`, are not valid
# Dragonstone syntax. Previously, however, the parser neither rejected nor
# ignored them.
#
# Instead, it parsed `(T)` as a parenthesized expression statement at the start
# of the class body. When the body was later evaluated, `T` was treated as a
# normal variable, producing an unhelpful `Undefined variable: T` error at the
# class declaration—far from the actual syntax mistake.
#
# `gc.ds` contained this pattern and still passed the parser sweep.
#
# Rejecting type parameters at the class definition makes the error immediate
# and explicit. Dragonstone may support them in the future, but until then it
# must not silently assign them a different meaning.
describe "type parameters" do
    it "rejects them on a class, naming the parameters" do
        expect_raises(Dragonstone::ParserError, /Type parameters are not supported: class Box\(T\)/) do
            parse("class Box(T)\nend\n")
        end
    end

    it "rejects them on a module and a struct" do
        expect_raises(Dragonstone::ParserError, /module Pair\(A, B\)/) do
            parse("module Pair(A, B)\nend\n")
        end

        expect_raises(Dragonstone::ParserError, /struct Cell\(T\)/) do
            parse("struct Cell(T)\nend\n")
        end
    end

    it "reports at the parenthesis, not the class keyword" do
        error = expect_raises(Dragonstone::ParserError) do
            parse("class Box(T)\nend\n")
        end

        # `class Box(`, column 10 is the `(`.
        error.location.not_nil!.column.should eq(10)
    end

    it "carries a hint pointing at the workaround" do
        error = expect_raises(Dragonstone::ParserError) do
            parse("class Box(T)\nend\n")
        end

        error.hint.not_nil!.should contain("Drop (T)")
    end

    # As elsewhere in the parser, the line break determines the meaning of `(`.
    # A `(` on the same line as the class name is treated as a type-parameter list,
    # while a `(` on the next line begins a normal parenthesized expression.
    #
    # This distinction prevents the type-parameter check from rejecting valid
    # expressions at the start of a class body.
    it "still accepts a parenthesized first statement on the next line" do
        Dragonstone.run("class Foo\n  (1 + 2).to_s\nend\necho \"ok\"\n").output.should eq("ok\n")
    end

    it "leaves an ordinary class alone" do
        parse("class Box\nend\n").should_not be_nil
    end
end
