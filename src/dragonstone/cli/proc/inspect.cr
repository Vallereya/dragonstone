require "./file_ops"

module Dragonstone
    module ProcInspect
        extend self

        def handle_lex_command(args : Array(String), stdout : IO, stderr : IO) : Int32
            return ProcCommon.show_usage(stdout) if args.empty?
            filename = args[0]
            return ProcFileOps.handle_missing_file(filename, stderr) unless File.exists?(filename)
            ProcFileOps.warn_if_unknown_extension(filename, stderr)
            handle_lex(filename, stdout)
        end

        def handle_parse_command(args : Array(String), stdout : IO, stderr : IO) : Int32
            return ProcCommon.show_usage(stdout) if args.empty?
            filename = args[0]
            return ProcFileOps.handle_missing_file(filename, stderr) unless File.exists?(filename)
            ProcFileOps.warn_if_unknown_extension(filename, stderr)
            handle_parse(filename, stdout)
        end

        def handle_lex(filename : String, stdout : IO) : Int32
            source = ProcFileOps.read_source(filename)
            lexer  = Dragonstone::Lexer.new(source, source_name: filename)
            tokens = lexer.tokenize
            stdout.puts "=== Tokens for #{filename} ==="
            tokens.each { |t| stdout.puts t.to_s }
            return 0
        end

        def handle_parse(filename : String, stdout : IO) : Int32
            source = ProcFileOps.read_source(filename)
            lexer  = Dragonstone::Lexer.new(source, source_name: filename)
            tokens = lexer.tokenize
            parser = Dragonstone::Parser.new(tokens)
            ast    = parser.parse
            stdout.puts "=== AST for #{filename} ==="
            print_ast(ast, 0, stdout)
            return 0
        end

        def print_ast(node : Dragonstone::AST::Node, indent = 0, io : IO = STDOUT)
            prefix = "  " * indent
            case node

            when Dragonstone::AST::Program
                io.puts "#{prefix}Program:"
                node.statements.each { |stmt| print_ast(stmt, indent + 1, io) }

            when Dragonstone::AST::MethodCall
                if node.receiver
                    io.puts "#{prefix}MethodCall: #{node.name} (with receiver)"
                    print_ast(node.receiver.not_nil!, indent + 1, io)
                else
                    io.puts "#{prefix}MethodCall: #{node.name}"
                end
                node.arguments.each { |arg| print_ast(arg, indent + 1, io) }

            when Dragonstone::AST::DebugPrint
                io.puts "#{prefix}DebugPrint:"
                print_ast(node.expression, indent + 1, io)

            when Dragonstone::AST::Assignment
                op = node.operator ? " #{node.operator}" : ""
                lhs = node.name
                lhs += ": #{node.type_annotation.not_nil!.to_source}" if node.type_annotation
                io.puts "#{prefix}Assignment: #{lhs}#{op} ="
                print_ast(node.value, indent + 1, io)

            when Dragonstone::AST::AttributeAssignment
                io.puts "#{prefix}AttributeAssignment: #{node.name}"
                print_ast(node.receiver, indent + 1, io)
                print_ast(node.value, indent + 1, io)

            when Dragonstone::AST::IndexAssignment
                io.puts "#{prefix}IndexAssignment:"
                print_ast(node.object, indent + 1, io)
                io.puts "#{prefix}  Index:"
                print_ast(node.index, indent + 1, io)
                io.puts "#{prefix}  Value:"
                print_ast(node.value, indent + 1, io)

            when Dragonstone::AST::ConstantDeclaration
                label = node.name
                label += ": #{node.type_annotation.not_nil!.to_source}" if node.type_annotation
                io.puts "#{prefix}ConstantDeclaration: #{label}"
                print_ast(node.value, indent + 1, io)

            when Dragonstone::AST::Variable
                label = node.name
                label += ": #{node.type_annotation.not_nil!.to_source}" if node.type_annotation
                io.puts "#{prefix}Variable: #{label}"

            when Dragonstone::AST::Literal
                io.puts "#{prefix}Literal: #{node.value.inspect}"

            when Dragonstone::AST::ArrayLiteral
                io.puts "#{prefix}ArrayLiteral:"
                node.elements.each { |elem| print_ast(elem, indent + 1, io) }

            when Dragonstone::AST::TupleLiteral
                io.puts "#{prefix}TupleLiteral:"
                node.elements.each { |elem| print_ast(elem, indent + 1, io) }

            when Dragonstone::AST::NamedTupleLiteral
                io.puts "#{prefix}NamedTupleLiteral:"
                node.entries.each do |entry|
                    entry_label = "#{entry.name}:"
                    entry_label += " #{entry.type_annotation.not_nil!.to_source}" if entry.type_annotation
                    io.puts "#{prefix}  #{entry_label}"
                    print_ast(entry.value, indent + 2, io)
                end

            when Dragonstone::AST::IndexAccess
                io.puts "#{prefix}IndexAccess:"
                print_ast(node.object, indent + 1, io)
                io.puts "#{prefix}  Index:"
                print_ast(node.index, indent + 1, io)

            when Dragonstone::AST::InterpolatedString
                io.puts "#{prefix}InterpolatedString:"
                
                node.parts.each do |part|
                    type, content = part
                    io.puts "#{prefix}  #{type}: #{content.inspect}"
                end

            when Dragonstone::AST::BinaryOp
                io.puts "#{prefix}BinaryOp: #{node.operator}"
                print_ast(node.left, indent + 1, io)
                print_ast(node.right, indent + 1, io)

            when Dragonstone::AST::UnaryOp
                io.puts "#{prefix}UnaryOp: #{node.operator}"
                print_ast(node.operand, indent + 1, io)

            when Dragonstone::AST::ConditionalExpression
                io.puts "#{prefix}ConditionalExpression:"
                io.puts "#{prefix}  Condition:"
                print_ast(node.condition, indent + 2, io)
                io.puts "#{prefix}  Then:"
                print_ast(node.then_branch, indent + 2, io)
                io.puts "#{prefix}  Else:"
                print_ast(node.else_branch, indent + 2, io)

            when Dragonstone::AST::IfStatement
                io.puts "#{prefix}IfStatement:"
                io.puts "#{prefix}  Condition:"
                print_ast(node.condition, indent + 2, io)
                io.puts "#{prefix}  Then:"
                node.then_block.each { |stmt| print_ast(stmt, indent + 2, io) }

                node.elsif_blocks.each do |elsif_clause|
                    io.puts "#{prefix}  Elsif:"
                    print_ast(elsif_clause.condition, indent + 2, io)
                    elsif_clause.block.each { |stmt| print_ast(stmt, indent + 2, io) }
                end

                if else_block = node.else_block
                    io.puts "#{prefix}  Else:"
                    else_block.each { |stmt| print_ast(stmt, indent + 2, io) }
                end

            when Dragonstone::AST::UnlessStatement
                io.puts "#{prefix}UnlessStatement:"
                io.puts "#{prefix}  Condition:"
                print_ast(node.condition, indent + 2, io)
                io.puts "#{prefix}  Body:"
                node.body.each { |stmt| print_ast(stmt, indent + 2, io) }

                if else_block = node.else_block
                    io.puts "#{prefix}  Else:"
                    else_block.each { |stmt| print_ast(stmt, indent + 2, io) }
                end

            when Dragonstone::AST::CaseStatement
                io.puts "#{prefix}CaseStatement:"

                if expr = node.expression
                    io.puts "#{prefix}  Expression:"
                    print_ast(expr, indent + 2, io)
                end

                node.when_clauses.each do |clause|
                    io.puts "#{prefix}  When:"
                    clause.conditions.each { |condition| print_ast(condition, indent + 2, io) }
                    clause.block.each { |stmt| print_ast(stmt, indent + 2, io) }
                end

                if else_block = node.else_block
                    io.puts "#{prefix}  Else:"
                    else_block.each { |stmt| print_ast(stmt, indent + 2, io) }
                end

            when Dragonstone::AST::WhileStatement
                io.puts "#{prefix}WhileStatement:"
                io.puts "#{prefix}  Condition:"
                print_ast(node.condition, indent + 2, io)
                io.puts "#{prefix}  Body:"
                node.block.each { |stmt| print_ast(stmt, indent + 2, io) }

            when Dragonstone::AST::FunctionDef
                params = node.typed_parameters.map(&.to_source).join(", ")
                sig = "#{node.name}(#{params})"
                sig += " -> #{node.return_type.not_nil!.to_source}" if node.return_type
                io.puts "#{prefix}FunctionDef: #{sig}"
                node.body.each { |stmt| print_ast(stmt, indent + 1, io) }

            when Dragonstone::AST::FunctionLiteral
                params = node.typed_parameters.map(&.to_source).join(", ")
                sig = "(#{params})"
                sig += " -> #{node.return_type.not_nil!.to_source}" if node.return_type
                io.puts "#{prefix}FunctionLiteral#{sig}"
                node.body.each { |stmt| print_ast(stmt, indent + 1, io) }

            when Dragonstone::AST::ReturnStatement
                io.puts "#{prefix}ReturnStatement:"

                if value = node.value
                    print_ast(value, indent + 1, io)
                end
            else
                io.puts "#{prefix}Unknown: #{node.class}"
            end
        end
    end
end
