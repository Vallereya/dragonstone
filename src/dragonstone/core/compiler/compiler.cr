# ---------------------------------
# ----- Core Compiler Driver ------
# ---------------------------------
require "../../shared/ir/program"
require "./build_options"
require "./frontend/pipeline"
require "./ir/builder"
require "./codegen/bytecode_generator"
require "./targets/llvm/backend"
require "./targets/c/backend"
require "./targets/crystal/backend"
require "./targets/ruby/backend"
require "./targets/python/backend"
require "./targets/javascript/backend"

module Dragonstone
    module Core
        module Compiler
            extend self

            def build(program : ::Dragonstone::IR::Program, options : BuildOptions = BuildOptions.new) : BuildArtifact
                case options.target
                when Target::Bytecode
                    bytecode = ::Dragonstone::Compiler.compile(program.ast)
                    BuildArtifact.new(target: Target::Bytecode, bytecode: bytecode)
                when Target::LLVM
                    Targets::LLVM::Backend.new.build(program, options)
                when Target::C
                    Targets::C::Backend.new.build(program, options)
                when Target::Crystal
                    Targets::Crystal::Backend.new.build(program, options)
                when Target::Ruby
                    Targets::Ruby::Backend.new.build(program, options)
                when Target::Python
                    Targets::Python::Backend.new.build(program, options)
                when Target::JavaScript
                    Targets::JavaScript::Backend.new.build(program, options)
                else
                    raise "Unknown compiler target #{options.target}"
                end
            end

            module Codegen
                alias BytecodeGenerator = ::Dragonstone::Compiler
            end
        end
    end
end
