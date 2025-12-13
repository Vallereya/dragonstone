require "../ast/ast"
require "./symbol_table"

# ---------------------------------
# ---------- Type Checker ---------
# ---------------------------------
module Dragonstone
    module Language
        module Sema
            record AnalysisResult,
                symbol_table : SymbolTable,
                typed : Bool,
                warnings : Array(String),
                annotations : Hash(String, Array(AST::Annotation))

            class TypeChecker
                getter symbol_table : SymbolTable

                def initialize(@symbol_table = SymbolTable.new)
                    @warnings = [] of String
                    @annotations = {} of String => Array(AST::Annotation)
                    @name_stack = [] of String
                end

                def analyze(program : AST::Program, typed : Bool = false) : AnalysisResult
                    visit_program(program)
                    AnalysisResult.new(@symbol_table, typed, @warnings.dup, @annotations.dup)
                end

                private def visit_program(program : AST::Program)
                    program.statements.each { |stmt| visit_node(stmt) }
                end

                private def visit_node(node : AST::Node)
                    case node
                    when AST::FunctionDef
                        register_function(node)
                    when AST::ClassDefinition
                        register_type(node.name, node.annotations)
                        with_name(node.name) { node.body.each { |stmt| visit_node(stmt) } }
                    when AST::StructDefinition
                        register_type(node.name, node.annotations)
                        with_name(node.name) { node.body.each { |stmt| visit_node(stmt) } }
                    when AST::ModuleDefinition
                        register_module(node.name, node.annotations)
                        with_name(node.name) { node.body.each { |stmt| visit_node(stmt) } }
                    when AST::ConstantDeclaration
                        register_constant(node.name)
                        visit_node(node.value)
                    when AST::Assignment
                        register_variable(node.name)
                        visit_node(node.value)
                    when AST::UseDecl
                        # Nothing to register yet, but ensure dependencies get visited later.
                    else
                        # For now we only track declarations; other nodes are ignored.
                    end
                end

                private def register_function(node : AST::FunctionDef)
                    if name = node.name
                        qualified = qualify(name)
                        record_annotations(qualified, node.annotations)
                        register_symbol(name, SymbolKind::Function)
                    end
                    node.body.each { |stmt| visit_node(stmt) }
                end

                private def register_type(name : String, annotations : Array(AST::Annotation))
                    record_annotations(qualify(name), annotations)
                    register_symbol(name, SymbolKind::Type)
                end

                private def register_module(name : String, annotations : Array(AST::Annotation))
                    record_annotations(qualify(name), annotations)
                    register_symbol(name, SymbolKind::Module)
                end

                private def register_constant(name : String)
                    register_symbol(name, SymbolKind::Constant)
                end

                private def register_variable(name : String)
                    register_symbol(name, SymbolKind::Variable)
                end

                private def register_symbol(name : String, kind : SymbolKind)
                    if symbol_table.defined?(name)
                        @warnings << "Symbol #{name} redefined as #{kind}"
                    end
                    symbol_table.define(name, kind)
                end

                private def record_annotations(name : String, annotations : Array(AST::Annotation))
                    return if annotations.empty?
                    @annotations[name] = annotations
                end

                private def with_name(name : String)
                    @name_stack << name
                    yield
                ensure
                    @name_stack.pop
                end

                private def qualify(name : String) : String
                    return name if @name_stack.empty?
                    (@name_stack + [name]).join("::")
                end
            end
        end
    end
end
