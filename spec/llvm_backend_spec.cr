require "spec"
require "../src/dragonstone"

private def build_program(statements : Array(Dragonstone::AST::Node))
    ast = Dragonstone::AST::Program.new(statements)
    analysis = Dragonstone::Language::Sema::AnalysisResult.new(
        Dragonstone::Language::Sema::SymbolTable.new,
        false,
        [] of String,
        {} of String => Array(Dragonstone::AST::Annotation)
    )
    Dragonstone::IR::Program.new(ast, analysis)
end

private def extract_function_body(ir : String, signature : String) : String
    start = ir.index(signature) || raise "signature #{signature} not found"
    slice = ir[start..-1]
    if ending = slice.index("\n}\n")
        slice[0..ending + 2]
    else
        slice
    end
end

describe Dragonstone::Core::Compiler::Targets::LLVM::IRGenerator do
    it "lowers constant paths via the runtime lookup helper" do
        statements = [
            Dragonstone::AST::ConstantPath.new(["Foo", "Bar"])
        ] of Dragonstone::AST::Node
        program = build_program(statements)
        generator = Dragonstone::Core::Compiler::Targets::LLVM::IRGenerator.new(program)
        io = IO::Memory.new

        generator.generate(io)

        ir = io.to_s
        ir.includes?("@dragonstone_runtime_constant_lookup(i64 2, i8**").should be_true
        ir.includes?("[2 x i8*]").should be_true
    end

    it "marshals tuple literals into the runtime constructor" do
        tuple = Dragonstone::AST::TupleLiteral.new([
            Dragonstone::AST::Literal.new(1_i64),
            Dragonstone::AST::Literal.new(2_i64)
        ] of Dragonstone::AST::Node)
        program = build_program([tuple] of Dragonstone::AST::Node)
        generator = Dragonstone::Core::Compiler::Targets::LLVM::IRGenerator.new(program)
        io = IO::Memory.new

        generator.generate(io)

        ir = io.to_s
        ir.includes?("@dragonstone_runtime_tuple_literal(i64 2, i8** %").should be_true
    end

    it "lowers named tuple literals via runtime helper" do
        entries = [
            Dragonstone::AST::NamedTupleEntry.new("name", Dragonstone::AST::Literal.new("Ada")),
            Dragonstone::AST::NamedTupleEntry.new("age", Dragonstone::AST::Literal.new(37_i64))
        ]
        literal = Dragonstone::AST::NamedTupleLiteral.new(entries)
        program = build_program([literal] of Dragonstone::AST::Node)
        generator = Dragonstone::Core::Compiler::Targets::LLVM::IRGenerator.new(program)
        io = IO::Memory.new

        generator.generate(io)

        ir = io.to_s
        ir.includes?("@dragonstone_runtime_named_tuple_literal(i64 2, i8** %").should be_true
    end

    it "propagates begin expression values" do
        begin_expr = Dragonstone::AST::BeginExpression.new([
            Dragonstone::AST::Literal.new(1_i64),
            Dragonstone::AST::Literal.new(2_i64)
        ] of Dragonstone::AST::Node, [] of Dragonstone::AST::RescueClause)
        func = Dragonstone::AST::FunctionDef.new(
            "value_fn",
            [] of Dragonstone::AST::TypedParameter,
            [Dragonstone::AST::ReturnStatement.new(begin_expr)] of Dragonstone::AST::Node,
            [] of Dragonstone::AST::RescueClause,
            Dragonstone::AST::SimpleTypeExpression.new("Int64")
        )
        program = build_program([func] of Dragonstone::AST::Node)
        generator = Dragonstone::Core::Compiler::Targets::LLVM::IRGenerator.new(program)
        io = IO::Memory.new

        generator.generate(io)

        section = extract_function_body(io.to_s, "define i64 @\"value_fn\"")
        section.includes?("call i8* @dragonstone_runtime_box_i64(i64 2)").should be_true
        section.includes?("call i64 @dragonstone_runtime_unbox_i64").should be_true
        section.includes?("ret i64 %").should be_true
    end

    it "runs ensure blocks before returning" do
        ensure_call = Dragonstone::AST::MethodCall.new("echo", [
            Dragonstone::AST::Literal.new("cleanup")
        ] of Dragonstone::AST::Node)
        begin_expr = Dragonstone::AST::BeginExpression.new(
            [Dragonstone::AST::ReturnStatement.new(Dragonstone::AST::Literal.new(42_i64))] of Dragonstone::AST::Node,
            [] of Dragonstone::AST::RescueClause,
            nil,
            [ensure_call] of Dragonstone::AST::Node
        )
        func = Dragonstone::AST::FunctionDef.new(
            "cleanup_fn",
            [] of Dragonstone::AST::TypedParameter,
            [begin_expr] of Dragonstone::AST::Node,
            [] of Dragonstone::AST::RescueClause,
            Dragonstone::AST::SimpleTypeExpression.new("Int64")
        )
        program = build_program([func] of Dragonstone::AST::Node)
        generator = Dragonstone::Core::Compiler::Targets::LLVM::IRGenerator.new(program)
        io = IO::Memory.new

        generator.generate(io)

        section = extract_function_body(io.to_s, "define i64 @\"cleanup_fn\"")
        ensure_pos = section.index("call i32 @puts") || raise("ensure puts not emitted")
        ret_pos = section.index("ret i64 42") || raise("return missing")
        (ensure_pos < ret_pos).should be_true
    end

    it "wraps begin/rescue expressions with exception handler scaffolding" do
        rescue_clause = Dragonstone::AST::RescueClause.new(
            ["StandardError"],
            nil,
            [Dragonstone::AST::MethodCall.new("echo", [Dragonstone::AST::Literal.new("recover")] of Dragonstone::AST::Node)] of Dragonstone::AST::Node
        )
        begin_expr = Dragonstone::AST::BeginExpression.new(
            [Dragonstone::AST::Literal.new(10_i64)] of Dragonstone::AST::Node,
            [rescue_clause]
        )
        program = build_program([begin_expr] of Dragonstone::AST::Node)
        generator = Dragonstone::Core::Compiler::Targets::LLVM::IRGenerator.new(program)
        io = IO::Memory.new

        generator.generate(io)

        ir = io.to_s
        ir.includes?("call void @dragonstone_runtime_push_exception_frame").should be_true
        ir.includes?("call void @dragonstone_runtime_pop_exception_frame").should be_true
        {% if flag?(:windows) %}
            ir.includes?("call i32 @_setjmp").should be_true
        {% else %}
            ir.includes?("call i32 @setjmp").should be_true
        {% end %}
    end

    it "invokes block receivers via the runtime shim" do
        block_literal = Dragonstone::AST::BlockLiteral.new(
            [] of Dragonstone::AST::TypedParameter,
            [Dragonstone::AST::Literal.new(42_i64)] of Dragonstone::AST::Node
        )
        call = Dragonstone::AST::MethodCall.new("call", [] of Dragonstone::AST::Node, block_literal)
        program = build_program([call] of Dragonstone::AST::Node)
        generator = Dragonstone::Core::Compiler::Targets::LLVM::IRGenerator.new(program)
        io = IO::Memory.new

        generator.generate(io)

        ir = io.to_s
        ir.includes?("@dragonstone_runtime_block_invoke").should be_true
    end

    it "declares constants via the runtime helper" do
        const_decl = Dragonstone::AST::ConstantDeclaration.new("MAGIC", Dragonstone::AST::Literal.new(99_i64))
        program = build_program([const_decl] of Dragonstone::AST::Node)
        generator = Dragonstone::Core::Compiler::Targets::LLVM::IRGenerator.new(program)
        io = IO::Memory.new

        generator.generate(io)

        io.to_s.includes?("@dragonstone_runtime_define_constant").should be_true
    end

    it "lowers index access and assignment through runtime shims" do
        array_literal = Dragonstone::AST::ArrayLiteral.new([Dragonstone::AST::Literal.new(1_i64)] of Dragonstone::AST::Node)
        setup = Dragonstone::AST::Assignment.new("items", array_literal)
        read = Dragonstone::AST::IndexAccess.new(Dragonstone::AST::Variable.new("items"), Dragonstone::AST::Literal.new(0_i64))
        write = Dragonstone::AST::IndexAssignment.new(Dragonstone::AST::Variable.new("items"), Dragonstone::AST::Literal.new(0_i64), Dragonstone::AST::Literal.new(2_i64))
        program = build_program([setup, read, write] of Dragonstone::AST::Node)
        generator = Dragonstone::Core::Compiler::Targets::LLVM::IRGenerator.new(program)
        io = IO::Memory.new

        generator.generate(io)

        ir = io.to_s
        ir.includes?("@dragonstone_runtime_index_get").should be_true
        ir.includes?("@dragonstone_runtime_index_set").should be_true
    end

    it "translates case expressions using runtime comparisons" do
        clause = Dragonstone::AST::WhenClause.new(
            [Dragonstone::AST::Literal.new(1_i64)] of Dragonstone::AST::Node,
            [Dragonstone::AST::Literal.new("one")] of Dragonstone::AST::Node
        )
        case_stmt = Dragonstone::AST::CaseStatement.new(Dragonstone::AST::Literal.new(1_i64), [clause])
        program = build_program([case_stmt] of Dragonstone::AST::Node)
        generator = Dragonstone::Core::Compiler::Targets::LLVM::IRGenerator.new(program)
        io = IO::Memory.new

        generator.generate(io)

        io.to_s.includes?("@dragonstone_runtime_case_compare").should be_true
    end

    it "adds implicit block parameters for functions that yield" do
        yield_expr = Dragonstone::AST::YieldExpression.new([Dragonstone::AST::Literal.new(5_i64)] of Dragonstone::AST::Node)
        func = Dragonstone::AST::FunctionDef.new(
            "runner",
            [Dragonstone::AST::TypedParameter.new("value", Dragonstone::AST::SimpleTypeExpression.new("Int64"))],
            [yield_expr] of Dragonstone::AST::Node,
            [] of Dragonstone::AST::RescueClause,
            Dragonstone::AST::SimpleTypeExpression.new("Int64")
        )
        block_literal = Dragonstone::AST::BlockLiteral.new(
            [Dragonstone::AST::TypedParameter.new("x")],
            [Dragonstone::AST::Literal.new(10_i64)] of Dragonstone::AST::Node
        )
        call = Dragonstone::AST::MethodCall.new("runner", [
            Dragonstone::AST::Literal.new(1_i64),
            block_literal
        ] of Dragonstone::AST::Node)
        program = build_program([func, call] of Dragonstone::AST::Node)
        generator = Dragonstone::Core::Compiler::Targets::LLVM::IRGenerator.new(program)
        io = IO::Memory.new

        generator.generate(io)

        ir = io.to_s
        ir.includes?("define i64 @\"runner").should be_true
        ir.includes?("%block_arg").should be_true
        ir.includes?("@dragonstone_runtime_block_invoke").should be_true
    end

    it "spills captured locals into block environments" do
        setup = Dragonstone::AST::Assignment.new("message", Dragonstone::AST::Literal.new("Hello"))
        block_body = [
            Dragonstone::AST::MethodCall.new("echo", [Dragonstone::AST::Variable.new("message")] of Dragonstone::AST::Node)
        ] of Dragonstone::AST::Node
        block_literal = Dragonstone::AST::BlockLiteral.new([] of Dragonstone::AST::TypedParameter, block_body)
        call = Dragonstone::AST::MethodCall.new("call", [] of Dragonstone::AST::Node, block_literal)
        program = build_program([setup, call] of Dragonstone::AST::Node)
        generator = Dragonstone::Core::Compiler::Targets::LLVM::IRGenerator.new(program)
        io = IO::Memory.new

        generator.generate(io)

        ir = io.to_s
        ir.includes?("@dragonstone_runtime_block_env_allocate(i64 1)").should be_true
        ir.includes?("bitcast i8* %closure to i8**").should be_true
    end

    it "routes receiver method calls through the runtime" do
        receiver = Dragonstone::AST::ConstantPath.new(["Foo", "Bar"])
        call = Dragonstone::AST::MethodCall.new(
            "greet",
            [Dragonstone::AST::Literal.new(1_i64)] of Dragonstone::AST::Node,
            receiver
        )
        program = build_program([call] of Dragonstone::AST::Node)
        generator = Dragonstone::Core::Compiler::Targets::LLVM::IRGenerator.new(program)
        io = IO::Memory.new

        generator.generate(io)

        io.to_s.includes?("@dragonstone_runtime_method_invoke").should be_true
    end

    it "emits argv-based block entrypoints" do
        block_literal = Dragonstone::AST::BlockLiteral.new(
            [] of Dragonstone::AST::TypedParameter,
            [Dragonstone::AST::Literal.new(1_i64)] of Dragonstone::AST::Node
        )
        call = Dragonstone::AST::MethodCall.new("call", [] of Dragonstone::AST::Node, block_literal)
        program = build_program([call] of Dragonstone::AST::Node)
        generator = Dragonstone::Core::Compiler::Targets::LLVM::IRGenerator.new(program)
        io = IO::Memory.new

        generator.generate(io)

        ir = io.to_s
        ir.includes?("(i8* %closure, i64 %argc, i8** %argv)").should be_true
    end

    it "unboxes typed block parameters" do
        block_literal = Dragonstone::AST::BlockLiteral.new(
            [Dragonstone::AST::TypedParameter.new("value", Dragonstone::AST::SimpleTypeExpression.new("Int32"))],
            [Dragonstone::AST::MethodCall.new("echo", [Dragonstone::AST::Variable.new("value")] of Dragonstone::AST::Node)] of Dragonstone::AST::Node
        )
        call = Dragonstone::AST::MethodCall.new("call", [] of Dragonstone::AST::Node, block_literal)
        program = build_program([call] of Dragonstone::AST::Node)
        generator = Dragonstone::Core::Compiler::Targets::LLVM::IRGenerator.new(program)
        io = IO::Memory.new

        generator.generate(io)

        io.to_s.includes?("@dragonstone_runtime_unbox_i32").should be_true
    end

    it "routes pointer echoes through the runtime display helper" do
        array_literal = Dragonstone::AST::ArrayLiteral.new([Dragonstone::AST::Literal.new(5_i64)] of Dragonstone::AST::Node)
        setup = Dragonstone::AST::Assignment.new("items", array_literal)
        read = Dragonstone::AST::IndexAccess.new(Dragonstone::AST::Variable.new("items"), Dragonstone::AST::Literal.new(0_i64))
        echo = Dragonstone::AST::MethodCall.new("echo", [read] of Dragonstone::AST::Node)
        program = build_program([setup, echo] of Dragonstone::AST::Node)
        generator = Dragonstone::Core::Compiler::Targets::LLVM::IRGenerator.new(program)
        io = IO::Memory.new

        generator.generate(io)

        ir = io.to_s
        ir.includes?("@dragonstone_runtime_value_display").should be_true
    end

    it "unboxes pointer operands when performing arithmetic" do
        array_literal = Dragonstone::AST::ArrayLiteral.new([Dragonstone::AST::Literal.new(3_i64)] of Dragonstone::AST::Node)
        setup = Dragonstone::AST::Assignment.new("items", array_literal)
        index = Dragonstone::AST::IndexAccess.new(Dragonstone::AST::Variable.new("items"), Dragonstone::AST::Literal.new(0_i64))
        sum = Dragonstone::AST::BinaryOp.new(index, :+, Dragonstone::AST::Literal.new(2_i64))
        ret = Dragonstone::AST::ReturnStatement.new(sum)
        func = Dragonstone::AST::FunctionDef.new(
            "sum_items",
            [] of Dragonstone::AST::TypedParameter,
            [setup, ret] of Dragonstone::AST::Node,
            [] of Dragonstone::AST::RescueClause,
            Dragonstone::AST::SimpleTypeExpression.new("Int64")
        )
        program = build_program([func] of Dragonstone::AST::Node)
        generator = Dragonstone::Core::Compiler::Targets::LLVM::IRGenerator.new(program)
        io = IO::Memory.new

        generator.generate(io)

        io.to_s.includes?("@dragonstone_runtime_unbox_i64").should be_true
    end
end
