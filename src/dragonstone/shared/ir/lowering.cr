require "set"
require "../language/lexer/lexer"
require "../language/parser/parser"
require "./program"

module Dragonstone
    module IR
        module Lowering
            extend self

            module Supports
                extend self

                module VM
                    extend self

                    SUPPORTED_BINARY_OPERATORS = Set{:+, :"&+", :-, :"&-", :*, :"&*", :/, :==, :!=, :<, :<=, :>, :>=}
                    SUPPORTED_UNARY_OPERATORS = Set{:+, :"&+", :-, :"&-", :!, :~}

                    def supports?(program : AST::Program) : Bool
                        nodes_supported?(program.statements)
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
                            node.type_annotation.nil?
                        when AST::Assignment
                            node.operator.nil? && node.type_annotation.nil? && node_supported?(node.value)
                        when AST::BinaryOp
                            SUPPORTED_BINARY_OPERATORS.includes?(node.operator) &&
                                node_supported?(node.left) &&
                                node_supported?(node.right)
                        when AST::UnaryOp
                            SUPPORTED_UNARY_OPERATORS.includes?(node.operator) &&
                                node_supported?(node.operand)
                        when AST::MethodCall
                            return false if node.arguments.any? { |arg| arg.is_a?(AST::BlockLiteral) }
                            receiver_supported = node.receiver.nil? || node_supported?(node.receiver.not_nil!)
                            receiver_supported && nodes_supported?(node.arguments)
                        when AST::IfStatement
                            cond_ok = node_supported?(node.condition)
                            then_ok = nodes_supported?(node.then_block)
                            elsif_ok = node.elsif_blocks.all? { |clause| node_supported?(clause.condition) && nodes_supported?(clause.block) }
                            else_ok = node.else_block.nil? || nodes_supported?(node.else_block.not_nil!)
                            cond_ok && then_ok && elsif_ok && else_ok
                        when AST::WhileStatement
                            node_supported?(node.condition) && nodes_supported?(node.block)
                        when AST::DebugPrint
                            node_supported?(node.expression)
                        when AST::ArrayLiteral
                            nodes_supported?(node.elements)
                        when AST::IndexAccess
                            !node.nil_safe && node_supported?(node.object) && node_supported?(node.index)
                        when AST::InterpolatedString
                            interpolated_string_supported?(node)
                        when AST::ReturnStatement
                            node.value.nil? || node_supported?(node.value.not_nil!)
                        when AST::FunctionDef
                            function_supported?(node)
                        else
                            false
                        end
                    end

                    private def function_supported?(node : AST::FunctionDef) : Bool
                        return false if node.receiver
                        return false unless node.rescue_clauses.empty?
                        return false unless node.typed_parameters.all? { |param| param.instance_var_name.nil? }
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

                def interpreter?(program : AST::Program) : Bool
                    Interpreter.supports?(program)
                end
            end

            def lower(program : AST::Program, analysis : Language::Sema::AnalysisResult) : Program
                Program.new(program, analysis)
            end
        end
    end
end
