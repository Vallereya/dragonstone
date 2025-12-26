require "../backend_mode"
require "../core/compiler/compiler"
require "../core/compiler/frontend/pipeline"
require "../core/vm/vm"
require "../shared/language/resolver/resolver"

require "./proc/common"
require "./proc/file_ops"

module Dragonstone
  module CLIBuild
    extend self

    EXECUTABLE_SUFFIX = {% if flag?(:windows) %} ".exe" {% else %} "" {% end %}
    LLVM_RUNTIME_STUB = "src/dragonstone/core/compiler/targets/llvm/runtime_stub.c"

	    private struct CLIOptions
	      getter typed : Bool
	      getter output_dir : String?
	      getter targets : Array(Core::Compiler::Target)
	      getter filename : String
	      getter argv : Array(String)

	      def initialize(@typed : Bool, @output_dir : String?, @targets : Array(Core::Compiler::Target), @filename : String, @argv : Array(String))
	      end
	    end

    alias TargetArtifact = NamedTuple(
      target: Core::Compiler::Target,
      artifact: Core::Compiler::BuildArtifact,
      linked_path: String?)

    private def emit_warnings(warnings : Array(String), targets : Array(Core::Compiler::Target), stderr : IO) : Nil
      filtered = warnings
      if targets.includes?(Core::Compiler::Target::LLVM)
        filtered = warnings.reject { |warning| warning.starts_with?("Symbol ") && warning.includes?(" redefined as ") }
      end
      filtered.each { |warning| stderr.puts "WARNING: #{warning}" }
    end

    def build_command(args : Array(String), stdout : IO, stderr : IO) : Int32
      options = parse_cli_options(args, stdout, stderr)
      return 1 unless options

      filename = options.filename
      return ProcFileOps.handle_missing_file(filename, stderr) unless File.exists?(filename)

      ProcFileOps.warn_if_unknown_extension(filename, stderr)

      begin
        program, warnings = build_program(filename, typed: options.typed)
        emit_warnings(warnings, options.targets, stderr)
        build_targets(program, options.targets, options.output_dir, stdout, stderr)
        return 0
      rescue e : Dragonstone::Error
        stderr.puts "ERROR: #{e.message}"
        return 1
      rescue e
        stderr.puts "UNEXPECTED ERROR: #{e.message}"
        return 1
      end
    end

    def build_and_run_command(args : Array(String), stdout : IO, stderr : IO) : Int32
      options = parse_cli_options(args, stdout, stderr)
      return 1 unless options

      filename = options.filename
      return ProcFileOps.handle_missing_file(filename, stderr) unless File.exists?(filename)

      ProcFileOps.warn_if_unknown_extension(filename, stderr)

      begin
        program, warnings = build_program(filename, typed: options.typed)

        emit_warnings(warnings, options.targets, stderr)

	        artifacts = build_targets(program, options.targets, options.output_dir, stdout, stderr)
	        run_artifacts(program, artifacts, stdout, stderr, options.argv) ? 0 : 1
	      rescue e : Dragonstone::Error
	        stderr.puts "ERROR: #{e.message}"
	        return 1
      rescue e
        stderr.puts "UNEXPECTED ERROR: #{e.message}"
        return 1
      end
    end

    private def add_target(targets : Array(Core::Compiler::Target), target : Core::Compiler::Target)
      targets << target unless targets.includes?(target)
    end

	    private def parse_cli_options(args : Array(String), stdout : IO, stderr : IO) : CLIOptions?
	      typed = false
	      output_dir : String? = nil
	      targets = [] of Core::Compiler::Target
	      filename = nil
	      script_argv = [] of String

	      idx = 0

      while idx < args.size
        arg = args[idx]

        if arg == "--typed"
          typed = true
        elsif arg == "--target"
          idx += 1

          if idx >= args.size
            stderr.puts "Missing value for --target"
            return nil
          end

          target = parse_target_flag(args[idx], stderr)
          return nil unless target

          add_target(targets, target)
        elsif arg.starts_with?("--target=")
          value = arg.split("=", 2)[1]? || ""
          target = parse_target_flag(value, stderr)
          return nil unless target

          add_target(targets, target)
        elsif arg == "--output"
          idx += 1

          if idx >= args.size
            stderr.puts "Missing value for --output"
            return nil
          end

          output_dir = args[idx]
        elsif arg.starts_with?("--output=")
          output_dir = arg.split("=", 2)[1]? || ""
        elsif arg.starts_with?("--")
          stderr.puts "Unknown option: #{arg}"
          return nil
	        elsif filename.nil?
	          filename = arg
	        else
	          script_argv << arg
	        end

        idx += 1
      end

      unless filename
        ProcCommon.show_usage(stdout)
        return nil
      end

	      add_target(targets, Core::Compiler::Target::Bytecode) if targets.empty?
	      CLIOptions.new(typed, output_dir, targets, filename, script_argv)
	    end

    private def parse_target_flag(value : String, stderr : IO) : Core::Compiler::Target?
      normalized = value.downcase
      case normalized
      when "bytecode", "vm"
        Core::Compiler::Target::Bytecode
      when "llvm"
        Core::Compiler::Target::LLVM
      when "c"
        Core::Compiler::Target::C
      when "crystal"
        Core::Compiler::Target::Crystal
      when "ruby"
        Core::Compiler::Target::Ruby
      else
        stderr.puts "Unknown target '#{value}'. Expected bytecode, llvm, c, crystal, or ruby."
        nil
      end
    end

    private def build_program(filename : String, *, typed : Bool) : Tuple(IR::Program, Array(String))
      entry_path = File.realpath(filename)

      resolver = Dragonstone.build_resolver(entry_path, BackendMode::Core)
      topo = resolver.resolve(filename)

      pipeline = Core::Compiler::Frontend::Pipeline.new

      combined_statements = [] of AST::Node
      typed_flag = typed
      entry = entry_path

      topo.reverse_each do |path|
        node = resolver.graph[path]?
        raise "Internal: missing module node for #{path}" unless node

        ast = node.ast || resolver.cache.get(path)
        raise "Internal: missing AST for #{path}" unless ast

        typed_flag ||= node.typed

        is_entry = !remote_path?(path) && File.realpath(path) == entry
        if is_entry
          combined_statements.concat(ast.statements)
        else
          ast.statements.each do |stmt|
            combined_statements << stmt if exportable_statement?(stmt)
          end
        end
      end

      combined_ast = AST::Program.new(combined_statements, [] of AST::UseDecl)

      program = pipeline.build_ir(combined_ast, typed: typed_flag)
      {program, program.warnings}
    end

    private def exportable_statement?(stmt : AST::Node) : Bool
      case stmt
      when AST::ClassDefinition,
           AST::ModuleDefinition,
           AST::StructDefinition,
           AST::EnumDefinition,
           AST::FunctionDef,
           AST::ConstantDeclaration,
           AST::AliasDefinition,
           AST::AccessorMacro
        true
      else
        false
      end
    end

    private def remote_path?(value : String) : Bool
      value.starts_with?("http://") || value.starts_with?("https://")
    end

    private def build_targets(program : IR::Program, targets : Array(Core::Compiler::Target), output_dir : String?, stdout : IO, stderr : IO) : Array(TargetArtifact)
      artifacts = [] of TargetArtifact

      targets.each do |target|
        options = Core::Compiler::BuildOptions.new(target: target, output_dir: output_dir)
        artifact = Core::Compiler.build(program, options)
        linked_path = target == Core::Compiler::Target::LLVM ? link_llvm_binary(artifact, stdout, stderr) : nil
        report_artifact(target, artifact, stdout, linked_path)
        artifacts << {target: target, artifact: artifact, linked_path: linked_path}
      end

      artifacts
    end

	    private def run_artifacts(program : IR::Program, artifacts : Array(TargetArtifact), stdout : IO, stderr : IO, argv : Array(String)) : Bool
	      artifacts.each do |entry|
	        target = entry[:target]
	        # stdout.puts "Running #{target_label(target)} artifact..."
	        return false unless run_build_artifact(program, target, entry[:artifact], stdout, stderr, entry[:linked_path], argv)
	      end

      true
    end

	    private def run_build_artifact(program : IR::Program, target : Core::Compiler::Target, artifact : Core::Compiler::BuildArtifact, stdout : IO, stderr : IO, linked_path : String?, argv : Array(String)) : Bool
	      case target
	      when Core::Compiler::Target::Bytecode
	        run_bytecode_artifact(program, artifact, stdout, stderr, argv)
	      when Core::Compiler::Target::Ruby
	        run_ruby_artifact(artifact, stdout, stderr, argv)
	      when Core::Compiler::Target::Crystal
	        run_crystal_artifact(artifact, stdout, stderr, argv)
	      when Core::Compiler::Target::C
	        run_c_artifact(artifact, stdout, stderr, argv)
	      when Core::Compiler::Target::LLVM
	        run_llvm_artifact(artifact, stdout, stderr, linked_path, argv)
	      else
	        stderr.puts "Cannot execute #{target_label(target)} artifacts yet"
	        false
	      end
	    end

	    private def run_bytecode_artifact(program : IR::Program, artifact : Core::Compiler::BuildArtifact, stdout : IO, stderr : IO, argv : Array(String)) : Bool
      bytecode = artifact.bytecode

      unless bytecode
        stderr.puts "Bytecode artifact is missing compiled instructions"
        return false
      end

      output = IO::Memory.new
	      vm = VM.new(bytecode, argv: argv, stdout_io: output, typing_enabled: program.typed?)
      vm.run
      stdout << output.to_s
      true
    rescue e : Exception
      stderr.puts "Failed to execute bytecode artifact: #{e.message}"
      false
    end

	    private def run_ruby_artifact(artifact : Core::Compiler::BuildArtifact, stdout : IO, stderr : IO, argv : Array(String)) : Bool
	      if path = artifact.object_path
	        run_process("ruby", [path] + argv, stdout, stderr)
	      else
	        stderr.puts "Ruby artifact did not produce an output file"
	        false
	      end
	    end

	    private def run_crystal_artifact(artifact : Core::Compiler::BuildArtifact, stdout : IO, stderr : IO, argv : Array(String)) : Bool
	      if path = artifact.object_path
	        run_process("crystal", ["run", path, "--"] + argv, stdout, stderr)
	      else
	        stderr.puts "Crystal artifact did not produce an output file"
	        false
	      end
	    end

	    private def run_llvm_artifact(artifact : Core::Compiler::BuildArtifact, stdout : IO, stderr : IO, linked_path : String?, argv : Array(String)) : Bool
      if linked_path && File.exists?(linked_path)
        linked_stdout = IO::Memory.new
        linked_stderr = IO::Memory.new

	        linked_ok = run_process(linked_path, argv, linked_stdout, linked_stderr, lookup: false)
        if linked_ok
          stdout << linked_stdout.to_s
          stderr << linked_stderr.to_s
          return true
        end

        stderr.puts "Linked LLVM binary failed; falling back to lli."
        stderr << linked_stderr.to_s unless linked_stderr.empty?
      end

	      if path = artifact.object_path
	        run_process("lli", [path] + argv, stdout, stderr)
	      else
	        stderr.puts "LLVM artifact did not produce an output file"
	        false
	      end
	    end

	    private def run_c_artifact(artifact : Core::Compiler::BuildArtifact, stdout : IO, stderr : IO, argv : Array(String)) : Bool
      path = artifact.object_path

      unless path
        stderr.puts "C artifact did not produce an output file"
        return false
      end

      binary_path = c_binary_path(path)
      compiler_used = nil
      ["cc", "gcc", "clang"].each do |candidate|
        begin
          status = Process.run(candidate, args: ["-std=c11", path, "-o", binary_path], output: stdout, error: stderr)
          if status.success?
            compiler_used = candidate
            break
          else
            stderr.puts "C compiler '#{candidate}' exited with status #{status.exit_code}"
            return false
          end
        rescue ex : File::NotFoundError
          next
        rescue ex
          stderr.puts "Failed to invoke #{candidate}: #{ex.message}"
          return false
        end
      end

      unless compiler_used
        stderr.puts "Cannot execute C artifact: no compiler found (tried cc, gcc, clang)"
        return false
      end

	      run_process(binary_path, argv, stdout, stderr, lookup: false)
	    ensure
	      if binary_path && File.exists?(binary_path)
	        File.delete(binary_path)
	      end
	    end

    private def c_binary_path(source_path : String) : String
      dir = File.dirname(source_path)
      base = File.basename(source_path, File.extname(source_path))
      File.join(dir, "#{base}_run#{EXECUTABLE_SUFFIX}")
    end

    private def llvm_binary_path(ir_path : String) : String
      dir = File.dirname(ir_path)
      File.join(dir, "dragonstone_llvm#{EXECUTABLE_SUFFIX}")
    end

    private def run_process(command : String, args : Array(String), stdout : IO, stderr : IO, *, lookup : Bool = true) : Bool
      status = Process.run(command, args: args, output: stdout, error: stderr)
      if status.success?
        true
      else
        stderr.puts "Command '#{command}' exited with status #{status.exit_code}"
        false
      end
    rescue ex : File::NotFoundError
      if lookup
        stderr.puts "Command '#{command}' not found. Please install it to run this artifact."
      else
        stderr.puts "Executable '#{command}' not found."
      end
      false
    rescue ex
      stderr.puts "Failed to run #{command}: #{ex.message}"
      false
    end

    private def report_artifact(target : Core::Compiler::Target, artifact : Core::Compiler::BuildArtifact, stdout : IO, linked_path : String?) : Nil
      label = target_label(target)
      if path = artifact.object_path
        # stdout.puts "Built #{label} -> #{path}"
      elsif bytecode = artifact.bytecode
        instructions = bytecode.code.size
        # stdout.puts "Built #{label} (#{instructions} instructions)"
      else
        # stdout.puts "Built #{label}"
      end
      if linked_path
        # stdout.puts "Linked #{label} binary -> #{linked_path}"
      end
    end

    private def target_label(target : Core::Compiler::Target) : String
      "#{target.to_s.downcase} target"
    end

    ABI_RUNTIME_SOURCES = [
      "src/dragonstone/shared/runtime/abi/abi.c",
      "src/dragonstone/shared/runtime/abi/std/std.c",
      "src/dragonstone/shared/runtime/abi/std/io/io.c",
      "src/dragonstone/shared/runtime/abi/std/file/file.c",
      "src/dragonstone/shared/runtime/abi/std/path/path.c",
      "src/dragonstone/shared/runtime/abi/platform/platform.c",
      "src/dragonstone/shared/runtime/abi/platform/lib_c/lib_c.c",
    ]

    UTF8PROC_RUNTIME_SOURCE = "src/dragonstone/stdlib/modules/shared/unicode/proc/vendor/utf8proc.c"

    private def link_llvm_binary(artifact : Core::Compiler::BuildArtifact, stdout : IO, stderr : IO) : String?
      ir_path = artifact.object_path
      return nil unless ir_path && File.exists?(ir_path)
      runtime_objs = compile_runtime_stub(File.dirname(ir_path), stdout, stderr)
      return nil unless runtime_objs
      binary_path = llvm_binary_path(ir_path)
      return nil unless link_with_clang(ir_path, runtime_objs, binary_path, stdout, stderr)
      binary_path
    end

    private def compile_runtime_stub(output_dir : String, stdout : IO, stderr : IO) : Array(String)?
      sources = [LLVM_RUNTIME_STUB] + ABI_RUNTIME_SOURCES + [UTF8PROC_RUNTIME_SOURCE]
      objects = [] of String

      sources.each do |source|
        basename = File.basename(source, ".c")
        object_path = File.join(output_dir, "#{basename}.o")
        args = ["-std=c11", "-c", source, "-o", object_path]
        if source == UTF8PROC_RUNTIME_SOURCE
          args << "-DUTF8PROC_STATIC"
        end
        return nil unless run_clang(args, stdout, stderr)
        objects << object_path
      end

      objects
    end

    private def link_with_clang(ir_path : String, runtime_objs : Array(String), binary_path : String, stdout : IO, stderr : IO) : Bool
      args = ["-Wno-override-module", ir_path] + runtime_objs + ["-o", binary_path]
      {% if flag?(:linux) %}
        args << "-lm"
      {% end %}
      run_clang(args, stdout, stderr)
    end

    private def run_clang(args : Array(String), stdout : IO, stderr : IO) : Bool
      status = Process.run("clang", args: args, output: stdout, error: stderr)
      status.success?
    rescue ex : File::NotFoundError
      stderr.puts "clang is required to link LLVM artifacts. Please install it and rerun."
      false
    rescue ex
      stderr.puts "Failed to run clang: #{ex.message}"
      false
    end
  end
end
