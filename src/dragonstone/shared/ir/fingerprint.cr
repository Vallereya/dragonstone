require "./program"
require "../language/lexer/lexer"
require "../language/parser/parser"

module Dragonstone
    module IR
        module Fingerprint
            extend self

            def generate(program : Program) : String
                io = IO::Memory.new
                io << "typed:" << program.typed?
                io << "|symbols:"
                io << symbol_entries(program)
                io << "|ast:"
                describe_node(program.ast, io)
                io.to_s
            end

            private def symbol_entries(program : Program) : String
                entries = program.symbol_table.symbols.values.sort_by(&.name)
                entries.map do |info|
                    "#{info.name}:#{info.kind}"
                end.join(";")
            end

            private def describe_node(node : AST::Node, io : IO) : Nil
                case node
                when AST::Program
                    io << "Program("
                    describe_sequence(node.statements, io)
                    io << ")"
                when AST::Literal
                    io << "Literal(" << node.value.inspect << ")"
                when AST::Variable
                    io << "Var(" << node.name << ")"
                when AST::Assignment
                    operator = node.operator || "="
                    io << "Assign(" << node.name << "," << operator.to_s << ","
                    describe_node(node.value, io)
                    io << ")"
                when AST::BinaryOp
                    io << "Binary(" << node.operator.to_s << ","
                    describe_node(node.left, io)
                    io << ","
                    describe_node(node.right, io)
                    io << ")"
                when AST::UnaryOp
                    io << "Unary(" << node.operator.to_s << ","
                    describe_node(node.operand, io)
                    io << ")"
                when AST::MethodCall
                    io << "Call(" << node.name << ",recv="
                    if recv = node.receiver
                        describe_node(recv, io)
                    else
                        io << "nil"
                    end
                    io << ",args:"
                    describe_sequence(node.arguments, io)
                    io << ")"
                when AST::IfStatement
                    io << "If("
                    describe_node(node.condition, io)
                    io << ",then:"
                    describe_sequence(node.then_block, io)
                    io << ",elsif:"
                    node.elsif_blocks.each_with_index do |clause, idx|
                        io << "|" if idx > 0
                        describe_elsif(clause, io)
                    end
                    io << ",else:"
                    if block = node.else_block
                        describe_sequence(block, io)
                    else
                        io << "nil"
                    end
                    io << ")"
                when AST::WhileStatement
                    io << "While("
                    describe_node(node.condition, io)
                    io << ","
                    describe_sequence(node.block, io)
                    io << ")"
                when AST::DebugEcho
                    io << "Debug("
                    describe_node(node.expression, io)
                    io << ")"
                when AST::ArrayLiteral
                    io << "Array("
                    describe_sequence(node.elements, io)
                    io << ")"
                when AST::IndexAccess
                    io << "Index("
                    describe_node(node.object, io)
                    io << ","
                    describe_node(node.index, io)
                    io << ")"
                when AST::InterpolatedString
                    io << "Interpolated("
                    node.normalized_parts.each_with_index do |(type, content), idx|
                        io << "|" if idx > 0
                        if type == :string
                            io << "str:" << content
                        else
                            io << "expr:"
                            if expression_node = interpolation_expression_node(content)
                                describe_node(expression_node, io)
                            else
                                io << "invalid"
                            end
                        end
                    end
                    io << ")"
                when AST::ReturnStatement
                    io << "Return("
                    if value = node.value
                        describe_node(value, io)
                    else
                        io << "nil"
                    end
                    io << ")"
                when AST::FunctionDef
                    io << "Function(" << node.name << ",params:"
                    io << node.parameters.join(",")
                    io << ",body:"
                    describe_sequence(node.body, io)
                    io << ")"
                when AST::UseDecl
                    io << "Use(" << node.to_source << ")"
                else
                    io << node.class.name
                end
            end

            private def describe_sequence(nodes : Array(AST::Node), io : IO) : Nil
                io << "["
                nodes.each_with_index do |child, idx|
                    io << "," if idx > 0
                    describe_node(child, io)
                end
                io << "]"
            end

            private def describe_elsif(clause : AST::ElsifClause, io : IO) : Nil
                io << "Elsif("
                describe_node(clause.condition, io)
                io << ","
                describe_sequence(clause.block, io)
                io << ")"
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

        class Program
            def fingerprint : String
                Fingerprint.generate(self)
            end
        end
    end
end
