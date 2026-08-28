require "spec"
require "../src/dragonstone/shared/language/lexer/lexer"
require "../src/dragonstone/shared/language/parser/parser"

private def parse(source : String)
    Dragonstone::Parser.new(Dragonstone::Lexer.new(source).tokenize).parse
end

private def lex_types(source : String)
    Dragonstone::Lexer.new(source).tokenize.map(&.type)
end

describe "invoke" do
    it "lexes as a keyword, not an identifier" do
        lex_types("invoke Ruby\n").first.should eq(:INVOKE)
    end

    it "is lowercase only -- capital Invoke is an ordinary identifier" do
        lex_types("Invoke Ruby\n").first.should eq(:IDENTIFIER)
    end

    it "desugars `with \"<name>\"` to ffi.call_<lang>(name, [])" do
        program = parse(<<-DS)
        invoke Ruby
            with "./interop_ruby"
        end
        DS

        call = program.statements.first
        call.should be_a(Dragonstone::AST::MethodCall)
        call = call.as(Dragonstone::AST::MethodCall)

        call.name.should eq("call_ruby")
        call.receiver.as(Dragonstone::AST::Variable).name.should eq("ffi")
        call.arguments[0].as(Dragonstone::AST::Literal).value.should eq("./interop_ruby")
        call.arguments[1].as(Dragonstone::AST::ArrayLiteral).elements.empty?.should be_true
    end

    it "lowercases the language into the method name" do
        parse("invoke Crystal\n    with \"x\"\nend\n")
            .statements.first.as(Dragonstone::AST::MethodCall).name.should eq("call_crystal")
        parse("invoke C\n    with \"x\"\nend\n")
            .statements.first.as(Dragonstone::AST::MethodCall).name.should eq("call_c")
    end

    it "rejects the retired style 2 -- a bare name after `with`" do
        expect_raises(Exception, /Expected a quoted name after 'with'/) do
            parse("invoke Ruby\n    with puts\nend\n")
        end
    end

    it "rejects the retired style 2 -- an `as { ... }` argument block" do
        expect_raises(Exception) do
            parse("invoke Ruby\n    with \"puts\"\n    as {\n        \"x\"\n    }\nend\n")
        end
    end

    it "takes exactly one clause per block" do
        expect_raises(Exception, /Expected END/) do
            parse("invoke Ruby\n    with \"a\"\n    with \"b\"\nend\n")
        end
    end

    it "leaves the unrelated `with <receiver> ... end` expression alone" do
        lex_types("with point\n").first.should eq(:WITH)
        parse("struct Point\n    x: int\nend\np = Point.new(1)\nwith p\n    echo x\nend\n")
            .statements.size.should be > 0
    end
end
