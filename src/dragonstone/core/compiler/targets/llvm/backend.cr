# ---------------------------------
# -------- LLVM Backend -----------
# ---------------------------------
require "../../build_options"
require "../shared/helpers"
require "../shared/program_serializer"

module Dragonstone
    module Core
        module Compiler
            module Targets
                module LLVM
                    class Backend
                        EXTENSION = "ll"
                        
                        def build(program : ::Dragonstone::IR::Program, options : BuildOptions) : BuildArtifact
                            serializer = Shared::ProgramSerializer.new(program)
                            source_dump = serializer.source
                            summary_lines = serializer.summary_lines
                            artifact_path = Shared.artifact_path(options, EXTENSION)
                            File.write(artifact_path, build_content(program, source_dump, summary_lines))
                            BuildArtifact.new(target: Target::LLVM, object_path: artifact_path)
                        end
                        
                        private def build_content(program : ::Dragonstone::IR::Program, source : String, summary_lines : Array(String)) : String
                            generator = IRGenerator.new(program)
                            
                            String.build do |io|
                                io << "; ---------------------------------\n"
                                io << "; Dragonstone LLVM target artifact\n"
                                io << "; ---------------------------------\n"
                                unless source.empty?
                                    io << "; Source snapshot\n"
                                    source.each_line do |line|
                                        io << ";   " << line.rstrip << "\n"
                                    end
                                    io << ";\n"
                                end
                                unless summary_lines.empty?
                                    io << "; Summary\n"
                                    summary_lines.each do |line|
                                        io << ";  - " << line << "\n"
                                    end
                                    io << ";\n"
                                end
                                
                                # Generate actual LLVM IR
                                generator.generate(io)
                            end
                        end
                    end
                    
                    class IRGenerator
                        @string_counter = 0
                        @strings = [] of {String, String}  # [{name, value}]
                        
                        def initialize(@program : ::Dragonstone::IR::Program)
                        end
                        
                        def generate(io : IO)
                            # First pass: collect all strings we need
                            collect_strings
                            
                            # Emit string constants
                            @strings.each do |(name, value)|
                                escaped = escape_string(value)
                                io << "@#{name} = private unnamed_addr constant [#{escaped.size + 1} x i8] c\"#{escaped}\\00\"\n"
                            end
                            io << "\n" unless @strings.empty?
                            
                            # Declare external functions
                            io << "declare i32 @puts(i8*)\n\n"
                            
                            # Generate main function
                            io << "define i32 @main() {\n"
                            io << "entry:\n"
                            
                            generate_statements(io)
                            
                            io << "  ret i32 0\n"
                            io << "}\n"
                        end
                        
                        private def collect_strings
                            @program.ast.statements.each do |stmt|
                                collect_strings_from_statement(stmt)
                            end
                        end
                        
                        private def collect_strings_from_statement(stmt : AST::Node)
                            case stmt
                            when AST::MethodCall
                                stmt.arguments.each do |arg|
                                    if arg.is_a?(AST::Literal) && arg.value.is_a?(String)
                                        name = ".str#{@string_counter}"
                                        @string_counter += 1
                                        @strings << {name, arg.value.as(String)}
                                    end
                                end
                            end
                        end
                        
                        private def generate_statements(io : IO)
                            @program.ast.statements.each do |stmt|
                                generate_statement(io, stmt)
                            end
                        end
                        
                        private def generate_statement(io : IO, stmt : AST::Node)
                            case stmt
                            when AST::MethodCall
                                generate_method_call(io, stmt)
                            end
                        end
                        
                        private def generate_method_call(io : IO, call : AST::MethodCall)
                            # For now, treat 'echo' as a print statement
                            if call.name == "echo" && call.arguments.size == 1
                                arg = call.arguments[0]
                                if arg.is_a?(AST::Literal) && arg.value.is_a?(String)
                                    str_value = arg.value.as(String)
                                    # Find the string constant we created
                                    str_index = @strings.index { |(_, val)| val == str_value }
                                    if str_index
                                        str_name = @strings[str_index][0]
                                        str_len = escape_string(str_value).size + 1
                                        
                                        io << "  %str#{str_index} = getelementptr [#{str_len} x i8], [#{str_len} x i8]* @#{str_name}, i32 0, i32 0\n"
                                        io << "  call i32 @puts(i8* %str#{str_index})\n"
                                    end
                                end
                            end
                        end
                        
                        private def escape_string(str : String) : String
                            str.gsub("\\", "\\\\").gsub("\"", "\\\"").gsub("\n", "\\0A").gsub("\t", "\\09")
                        end
                    end
                end
            end
        end
    end
end
