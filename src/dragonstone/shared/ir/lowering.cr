require "set"
require "../language/lexer/lexer"
require "../language/parser/parser"
require "../language/transforms/default_arguments"
require "../language/transforms/lexical_bindings"
require "./program"

module Dragonstone
    module IR
        module Lowering
            extend self

            module Supports
                extend self

                module VM
                    extend self
                    @@last_failure : String?

                    SUPPORTED_BINARY_OPERATORS = Set{:+, :"&+", :-, :"&-", :*, :"&*", :/, :"//", :%, :"**", :"&**", :&, :|, :^, :<<, :>>, :==, :!=, :<, :<=, :>, :>=, :"&&", :"||", :"<=>"}
                    SUPPORTED_RANGE_OPERATORS = Set{:"..", :"..."}
                    SUPPORTED_UNARY_OPERATORS = Set{:+, :"&+", :-, :"&-", :!, :~}

                    def supports?(program : AST::Program) : Bool
                        @@last_failure = nil
                        nodes_supported?(program.statements)
                    end

                    def last_failure : String?
                        @@last_failure
                    end

                    private def nodes_supported?(nodes : Array(AST::Node)) : Bool
                        nodes.all? { |node| node_supported?(node) }
                    end

                    private def node_supported?(node : AST::Node) : Bool
                        case node
                        when AST::Program
                            nodes_supported?(node.statements)
                        when AST::Literal
                            true
                        when AST::Variable
                            true
                        when AST::ArgvExpression
                            true
                        when AST::ArgcExpression
                            true
                        when AST::ArgfExpression
                            true
                        when AST::StdoutExpression
                            true
                        when AST::StderrExpression
                            true
                        when AST::StdinExpression
                            true
                        when AST::Assignment
                            node_supported?(node.value)
                        when AST::AliasDefinition
                            true
                        when AST::BinaryOp
                            (SUPPORTED_BINARY_OPERATORS.includes?(node.operator) || SUPPORTED_RANGE_OPERATORS.includes?(node.operator)) &&
                                node_supported?(node.left) &&
                                node_supported?(node.right)
                        when AST::UnaryOp
                            SUPPORTED_UNARY_OPERATORS.includes?(node.operator) &&
                                node_supported?(node.operand)
                        when AST::ConditionalExpression
                            node_supported?(node.condition) &&
                                node_supported?(node.then_branch) &&
                                node_supported?(node.else_branch)
                        when AST::SuperCall
                            nodes_supported?(node.arguments)
                        when AST::MethodCall
                            receiver_supported = node.receiver.nil? || node_supported?(node.receiver.not_nil!)
                            receiver_supported && nodes_supported?(node.arguments)
                        when AST::ConstantDeclaration
                            node_supported?(node.value)
                        when AST::IfStatement
                            cond_ok = node_supported?(node.condition)
                            then_ok = nodes_supported?(node.then_block)
                            elsif_ok = node.elsif_blocks.all? { |clause| node_supported?(clause.condition) && nodes_supported?(clause.block) }
                            else_ok = node.else_block.nil? || nodes_supported?(node.else_block.not_nil!)
                            cond_ok && then_ok && elsif_ok && else_ok
                        when AST::WhileStatement
                            node_supported?(node.condition) && nodes_supported?(node.block)
                        when AST::DebugEcho
                            node_supported?(node.expression)
                        when AST::ArrayLiteral
                            nodes_supported?(node.elements)
                        when AST::TupleLiteral
                            node.elements.all? { |element| node_supported?(element) }
                        when AST::NamedTupleLiteral
                            node.entries.all? { |entry| node_supported?(entry.value) }
                        when AST::MapLiteral
                            node.entries.all? { |(key_node, value_node)| node_supported?(key_node) && node_supported?(value_node) }
                        when AST::IndexAccess
                            !node.nil_safe && node_supported?(node.object) && node_supported?(node.index)
                        when AST::IndexAssignment
                            node.operator.nil? && !node.nil_safe &&
                                node_supported?(node.object) &&
                                node_supported?(node.index) &&
                                node_supported?(node.value)
                        when AST::AttributeAssignment
                            (node.operator.nil? || SUPPORTED_BINARY_OPERATORS.includes?(node.operator)) &&
                                node_supported?(node.receiver) &&
                                node_supported?(node.value)
                        when AST::ConstantPath
                            true
                        when AST::InstanceVariable, AST::InstanceVariableAssignment
                            true
                        when AST::CaseStatement
                            (node.expression.nil? || node_supported?(node.expression.not_nil!)) &&
                                node.when_clauses.all? { |clause| nodes_supported?(clause.conditions) && nodes_supported?(clause.block) } &&
                                (node.else_block.nil? || nodes_supported?(node.else_block.not_nil!))
                        when AST::UnlessStatement
                            node_supported?(node.condition) &&
                                nodes_supported?(node.body) &&
                                (node.else_block.nil? || nodes_supported?(node.else_block.not_nil!))
                        when AST::InterpolatedString
                            interpolated_string_supported?(node)
                        when AST::ReturnStatement
                            node.value.nil? || node_supported?(node.value.not_nil!)
                        when AST::FunctionDef
                            function_supported?(node)
                        when AST::FunctionLiteral
                            nodes_supported?(node.body)
                        when AST::ParaLiteral
                            nodes_supported?(node.body)
                        when AST::BlockLiteral
                            nodes_supported?(node.body)
                        when AST::BagConstructor
                            true
                        when AST::ClassDefinition, AST::ModuleDefinition, AST::StructDefinition
                            nodes_supported?(node.body)
                        when AST::EnumDefinition
                            node.members.all? { |m| m.value.nil? || node_supported?(m.value.not_nil!) }
                        when AST::InstanceVariableDeclaration
                            true
                        when AST::AccessorMacro
                            true
                        when AST::WithExpression
                            node_supported?(node.receiver) && nodes_supported?(node.body)
                        when AST::NextStatement, AST::BreakStatement, AST::RedoStatement
                            true
                        when AST::RetryStatement
                            true
                        when AST::ExtendStatement
                            nodes_supported?(node.targets)
                        when AST::YieldExpression
                            nodes_supported?(node.arguments)
                        when AST::BeginExpression
                            nodes_supported?(node.body) && nodes_supported?(node.rescue_clauses.flat_map(&.body)) && (node.ensure_block.nil? || nodes_supported?(node.ensure_block.not_nil!)) && (node.else_block.nil? || nodes_supported?(node.else_block.not_nil!))
                        when AST::RaiseExpression
                            node.expression.nil? || node_supported?(node.expression.not_nil!)
                        else
                            debug_unsupported(node)
                            false
                        end
                    end

                    private def function_supported?(node : AST::FunctionDef) : Bool
                        return false if node.receiver && !node_supported?(node.receiver.not_nil!)
                        nodes_supported?(node.body)
                    end

                    private def interpolated_string_supported?(node : AST::InterpolatedString) : Bool
                        node.normalized_parts.all? do |type, content|
                            case type
                            when :string
                                true
                            when :expression
                                expression_node = interpolation_expression_node(content)
                                expression_node && node_supported?(expression_node)
                            else
                                false
                            end
                        end
                    end

                    private def interpolation_expression_node(content) : AST::Node?
                        return content.as(AST::Node) if content.is_a?(AST::Node)

                        lexer = Lexer.new(content.to_s)
                        tokens = lexer.tokenize
                        parser = Parser.new(tokens)
                        parser.parse_expression_entry
                    rescue
                        nil
                    end

                    private def debug_unsupported(node : AST::Node) : Nil
                        @@last_failure = node.class.name
                        return unless ENV["DS_DEBUG_VM_SUPPORT"]?
                        STDERR.puts "VM unsupported node: #{node.class}"
                    end
                end

                module Interpreter
                    extend self

                    def supports?(program : AST::Program) : Bool
                        # Interpreter backend currently serves as the fallback and accepts all AST nodes.
                        !program.nil?
                    end
                end

                def vm?(program : AST::Program) : Bool
                    VM.supports?(program)
                end

                def last_failure : String?
                    VM.last_failure
                end

                def interpreter?(program : AST::Program) : Bool
                    Interpreter.supports?(program)
                end
            end

            def lower(program : AST::Program, analysis : Language::Sema::AnalysisResult) : Program
                transformed = Language::Transforms::LexicalBindings.apply(program)
                transformed = Language::Transforms::DefaultArguments.apply(transformed)
                Program.new(transformed, analysis)
            end
        end
    end
end
