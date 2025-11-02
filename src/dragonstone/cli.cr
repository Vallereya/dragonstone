# ---------------------------------
# ------------- MAIN --------------
# ------------- CLI ---------------
# ---------------------------------
require "../dragonstone"

module Dragonstone
    module CLI
        extend self 

        def run (
                argv = ARGV, 
                stdout : IO = STDOUT, 
                stderr : 
                IO = STDERR
            ) : Int32

            return print_version(stdout) if version_command?(argv)

            return print_help(stdout) if help_command?(argv)

            return show_usage(stdout) if argv.empty?

            command = argv[0]
            args = argv[1..-1]

            case command

            when "lex"
                return show_usage(stdout) if args.empty?
                filename = args[0]
                return handle_missing_file(filename, stderr) unless File.exists?(filename)
                warn_if_unknown_extension(filename, stderr)
                handle_lex(filename, stdout)

            when "parse"
                return show_usage(stdout) if args.empty?
                filename = args[0]
                return handle_missing_file(filename, stderr) unless File.exists?(filename)
                warn_if_unknown_extension(filename, stderr)
                handle_parse(filename, stdout)

            when "run"
                handle_run_command(args, stdout, stderr)

            else
                stderr.puts "Unknown command: #{command}"
                print_usage(stdout)
                return 1
            end
        end

        private def version_command?(argv : Array(String)) : Bool
            argv.size == 1 && {"version", "--version", "--v"}.includes?(argv[0])
        end

        private def help_command?(argv : Array(String)) : Bool
            argv.size == 1 && {"help", "--help", "--h"}.includes?(argv[0])
        end

        private def print_version(stdout : IO) : Int32
            stdout.puts "Dragonstone #{Dragonstone::VERSION}"
            return 0
        end

        private def print_help(stdout : IO) : Int32
            print_usage(stdout)
            return 0
        end

        private def show_usage(stdout : IO) : Int32
            print_usage(stdout)
            return 1
        end

        private def handle_missing_file(filename : String, stderr : IO) : Int32
            stderr.puts "Error: File '#{filename}' not found"
            return 1
        end

        private def warn_if_unknown_extension(filename : String, stderr : IO) : Nil
            return if filename.ends_with?(".ds")
            stderr.puts "Warning: File doesn't have .ds extension"
        end

        private def handle_lex(filename : String, stdout : IO) : Int32
            source = File.read(filename)
            lexer = Dragonstone::Lexer.new(source, source_name: filename)
            tokens = lexer.tokenize
            stdout.puts "=== Tokens for #{filename} ==="
            tokens.each { |token| stdout.puts token.to_s }
            return 0
        end

        private def handle_parse(filename : String, stdout : IO) : Int32
            source = File.read(filename)
            lexer = Dragonstone::Lexer.new(source, source_name: filename)
            tokens = lexer.tokenize
            parser = Dragonstone::Parser.new(tokens)
            ast = parser.parse
            stdout.puts "=== AST for #{filename} ==="
            print_ast(ast, 0, stdout)
            return 0
        end

        private def handle_run_command(args : Array(String), stdout : IO, stderr : IO) : Int32
            typed = false
            filename = nil

            args.each do |arg|
                if arg == "--typed"
                    typed = true
                elsif arg.starts_with?("--")
                    stderr.puts "Unknown option: #{arg}"
                    return 1
                elsif filename.nil?
                    filename = arg
                else
                    stderr.puts "Too many arguments for run command"
                    return 1
                end
            end

            unless filename
                return show_usage(stdout)
            end

            return handle_missing_file(filename, stderr) unless File.exists?(filename)
            warn_if_unknown_extension(filename, stderr)
            handle_run(filename, stdout, stderr, typed: typed)
        end

        private def handle_run(filename : String, stdout : IO, stderr : IO, typed : Bool = false) : Int32
            begin
                result = Dragonstone.run_file(filename, log_to_stdout: false, typed: typed)
                stdout.puts result.output
                return 0

            rescue e : Dragonstone::Error
                stderr.puts "Error: #{e.message}"
                return 1

            rescue e
                stderr.puts "Unexpected error: #{e.message}"
                return 1
            end
        end

        private def print_usage(io : IO) : Nil
            io.puts "Usage: dragonstone <command> [options]"
            io.puts
            io.puts "Commands:"
            io.puts "  lex <file>               Tokenize a .ds file"
            io.puts "  parse <file>             Parse a .ds file and show AST"
            io.puts "  run <file>               Run a .ds file"
            io.puts "  run [--typed] <file>     Run a .ds file and enable optional static typing"
            io.puts "  --help or --h            Show help information"
            io.puts "  --version or --v         Show version information"
        end

        private def print_ast(node : Dragonstone::AST::Node, indent = 0, io : IO = STDOUT)
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
