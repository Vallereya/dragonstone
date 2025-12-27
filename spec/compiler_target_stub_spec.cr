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

private def read_artifact(path : String) : String
    File.exists?(path).should be_true
    File.read(path)
end

describe "compiler target stubs" do
    it "emits a Python stub artifact with a warning" do
        program = build_program([Dragonstone::AST::Literal.new(1_i64)] of Dragonstone::AST::Node)
        options = Dragonstone::Core::Compiler::BuildOptions.new(
            target: Dragonstone::Core::Compiler::Target::Python,
            output_dir: ".cache/spec_output/python"
        )

        artifact = Dragonstone::Core::Compiler::Targets::Python::Backend.new.build(program, options)
        content = read_artifact(artifact.object_path.not_nil!)

        content.includes?("Python target stub").should be_true
        content.includes?("WARNING: Not implemented yet").should be_true
    end

    it "emits a JavaScript stub artifact with a warning" do
        program = build_program([Dragonstone::AST::Literal.new(1_i64)] of Dragonstone::AST::Node)
        options = Dragonstone::Core::Compiler::BuildOptions.new(
            target: Dragonstone::Core::Compiler::Target::JavaScript,
            output_dir: ".cache/spec_output/javascript"
        )

        artifact = Dragonstone::Core::Compiler::Targets::JavaScript::Backend.new.build(program, options)
        content = read_artifact(artifact.object_path.not_nil!)

        content.includes?("JavaScript target stub").should be_true
        content.includes?("WARNING: Not implemented yet").should be_true
    end
end
