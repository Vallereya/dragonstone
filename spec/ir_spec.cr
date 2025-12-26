require "spec"
require "../src/dragonstone/shared/ir/fingerprint"
require "../src/dragonstone/shared/ir/lowering"
require "../src/dragonstone/shared/language/lexer/lexer"
require "../src/dragonstone/shared/language/parser/parser"
require "../src/dragonstone/shared/language/sema/type_checker"

private def build_ir(source : String, typed : Bool = false)
    lexer = Dragonstone::Lexer.new(source)
    tokens = lexer.tokenize
    ast = Dragonstone::Parser.new(tokens).parse
    analysis = Dragonstone::Language::Sema::TypeChecker.new.analyze(ast, typed: typed)
    Dragonstone::IR::Lowering.lower(ast, analysis)
end

private def parse_program(source : String)
    lexer = Dragonstone::Lexer.new(source)
    tokens = lexer.tokenize
    Dragonstone::Parser.new(tokens).parse
end

describe Dragonstone::IR do
    describe Dragonstone::IR::Lowering do
        it "produces stable IR for loops" do
            ir = build_ir("i = 0\nwhile i < 3\n  i = i + 1\nend")
            ir.fingerprint.should eq("typed:false|symbols:i:Variable|ast:Program([Assign(i,=,Literal(0)),While(Binary(<,Var(i),Literal(3)),[Assign(i,=,Binary(+,Var(i),Literal(1)))])])")
        end

        it "produces stable IR for conditionals" do
            source = <<-CODE
            if x > 1
              y = x
            elsif x == 1
              y = 0
            else
              y = -1
            end
            CODE
            ir = build_ir(source.strip)
            ir.fingerprint.should eq("typed:false|symbols:|ast:Program([If(Binary(>,Var(x),Literal(1)),then:[Assign(y,=,Var(x))],elsif:Elsif(Binary(==,Var(x),Literal(1)),[Assign(y,=,Literal(0))]),else:[Assign(y,=,Unary(-,Literal(1)))])])")
        end

        it "produces stable IR for functions" do
            ir = build_ir("def sum(a, b)\n  return a + b\nend")
            ir.fingerprint.should eq("typed:false|symbols:sum:Function|ast:Program([Function(sum,params:a,b,body:[Return(Binary(+,Var(a),Var(b)))])])")
        end

        it "produces stable IR for ffi dispatch" do
            ir = build_ir("ffi.call(\"puts\", [\"hello\"])")
            ir.fingerprint.should eq("typed:false|symbols:|ast:Program([Call(call,recv=Var(ffi),args:[Literal(\"puts\"),Array([Literal(\"hello\")])])])")
        end

        it "exposes VM and interpreter capability checks" do
            ast = parse_program("x += 1")
            Dragonstone::IR::Lowering::Supports.vm?(ast).should be_true
            Dragonstone::IR::Lowering::Supports.interpreter?(ast).should be_true
        end

        it "rejects assignment to argv keyword" do
            expect_raises(Dragonstone::ParserError) do
                parse_program("argv = 1")
            end
        end

        it "rejects assignment to builtin IO keywords" do
            %w[stdout stderr stdin argc argf].each do |name|
                expect_raises(Dragonstone::ParserError) do
                    parse_program("#{name} = 1")
                end
            end
        end
    end
end
