require "spec"
require "../../src/dragonstone/native/interpreter/interpreter"
require "../../src/dragonstone/shared/language/ast/ast"
require "../../src/dragonstone/shared/language/resolver/resolver"

alias AST = Dragonstone::AST

# Returns what the program echoed. The interpreter streams 
# to its stdout rather than accumulating a string, so 
# capture via an IO::Memory.
private def evaluate_statements(statements : Array(AST::Node)) : String
    program = AST::Program.new(statements)
    
    graph = Dragonstone::ModuleGraph.new
    graph.add(Dragonstone::ModuleNode.new("<native-evaluator>", program, false))

    output = IO::Memory.new

    interpreter = Dragonstone::Interpreter.new(stdout: output, typing_enabled: false)
    interpreter.interpret(program, graph)

    output.to_s
end

describe "Native evaluator" do
    it "evaluates arithmetic binary expressions directly from AST nodes" do
        expression = AST::BinaryOp.new(
            AST::Literal.new(2_i64),
            :+,
            AST::BinaryOp.new(AST::Literal.new(3_i64), :*, AST::Literal.new(4_i64))
        )

        debug = AST::DebugEcho.new(expression)

        statements = [] of AST::Node
        statements << debug

        evaluate_statements(statements).should eq("2 + 3 * 4 # -> 14\n")
    end

    it "updates variables and invokes builtins with manually built AST" do
        assign = AST::Assignment.new("counter", AST::Literal.new(1_i64))

        increment = AST::Assignment.new(
            "counter",
            AST::BinaryOp.new(AST::Variable.new("counter"), :+, AST::Literal.new(4_i64))
        )

        args = [] of AST::Node
        args << AST::Variable.new("counter")

        echo_call = AST::MethodCall.new("echo", args)

        statements = [] of AST::Node
        statements << assign
        statements << increment
        statements << echo_call

        evaluate_statements(statements).should eq("5\n")
    end

    it "supports eecho for printing without a newline" do
        args = [] of AST::Node
        args << AST::Literal.new("Hello")

        call = AST::MethodCall.new("eecho", args)

        statements = [] of AST::Node
        statements << call

        evaluate_statements(statements).should eq("Hello")
    end

    it "formats floats without trailing noise" do
        args = [] of AST::Node
        args << AST::Literal.new(5.0_f64)

        call = AST::MethodCall.new("echo", args)

        statements = [] of AST::Node
        statements << call

        evaluate_statements(statements).should eq("5\n")
    end

    it "coerces float32 annotations during assignment" do
        value = 3.14159265358_f64
        expected = sprintf("%.15g", value.to_f32.to_f64)

        assign = AST::Assignment.new(
            "pi",
            AST::Literal.new(value),
            type_annotation: AST::SimpleTypeExpression.new("float32")
        )

        call = AST::MethodCall.new("echo", [AST::Variable.new("pi")] of AST::Node)

        statements = [] of AST::Node
        statements << assign
        statements << call

        evaluate_statements(statements).should eq("#{expected}\n")
    end

    it "supports ee! for inline debug accumulation" do
        first = AST::DebugEcho.new(AST::Literal.new("Test Four..."), true)
        second = AST::DebugEcho.new(AST::Literal.new("done!"), true)

        statements = [] of AST::Node
        statements << first
        statements << second

        evaluate_statements(statements).should eq("\"Test Four...\" + \"done!\" # -> \"Test Four...\" + \"done!\"\n")
    end
end
