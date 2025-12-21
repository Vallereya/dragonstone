require "spec"
require "../../src/dragonstone/native/interpreter/interpreter"
require "../../src/dragonstone/shared/language/ast/ast"
require "../../src/dragonstone/shared/language/resolver/resolver"

alias AST = Dragonstone::AST

private def evaluate_statements(statements : Array(AST::Node)) : Dragonstone::Interpreter
    program = AST::Program.new(statements)
    graph = Dragonstone::ModuleGraph.new
    graph.add(Dragonstone::ModuleNode.new("<native-evaluator>", program, false))
    interpreter = Dragonstone::Interpreter.new(log_to_stdout: false, typing_enabled: false)
    interpreter.interpret(program, graph)
    interpreter
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
        interpreter = evaluate_statements(statements)
        interpreter.output.should eq("2 + 3 * 4 # -> 14\n")
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
        interpreter = evaluate_statements(statements)
        interpreter.output.should eq("5\n")
    end

    it "supports eecho for printing without a newline" do
        args = [] of AST::Node
        args << AST::Literal.new("Hello")
        call = AST::MethodCall.new("eecho", args)
        statements = [] of AST::Node
        statements << call
        interpreter = evaluate_statements(statements)
        interpreter.output.should eq("Hello")
    end

    it "supports ee! for inline debug accumulation" do
        first = AST::DebugEcho.new(AST::Literal.new("Test Four..."), true)
        second = AST::DebugEcho.new(AST::Literal.new("done!"), true)
        statements = [] of AST::Node
        statements << first
        statements << second
        interpreter = evaluate_statements(statements)
        interpreter.output.should eq("\"Test Four...\" + \"done!\" # -> \"Test Four...\" + \"done!\"\n")
    end
end
