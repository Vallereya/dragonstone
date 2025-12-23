require "spec"
require "file_utils"
require "../src/dragonstone/cli/cli"
require "../src/dragonstone/cli/cli_build"

private def run_program_via_cli(source : String, backend : String) : NamedTuple(status: Int32, stdout: String, stderr: String)
  file = File.tempfile("dragonstone-default-params", suffix: ".ds")
  begin
    file.print(source)
    file.flush

    stdout = IO::Memory.new
    stderr = IO::Memory.new
    status = Dragonstone::CLI.run(["run", "--backend", backend, file.path], stdout, stderr)

    {status: status, stdout: stdout.to_s, stderr: stderr.to_s}
  ensure
    path = file.path
    file.close
    File.delete(path) if File.exists?(path)
  end
end

private def clang_available? : Bool
  io = IO::Memory.new
  Process.run("clang", args: ["--version"], output: io, error: io).success?
rescue File::NotFoundError
  false
end

private module LLVMDefaultParamIntegration
  @@available : Bool? = nil

  def self.available? : Bool
    cached = @@available
    return cached unless cached.nil?

    @@available = begin
      unless clang_available?
        false
      else
        dir = File.join("dev", "build", "spec", "llvm_default_params_probe_#{Random::Secure.hex(8)}")
        FileUtils.mkdir_p(dir)
        begin
          source = File.join(dir, "probe.ds")
          File.write(source, "echo \"probe\"")

          stdout = IO::Memory.new
          stderr = IO::Memory.new
          status = Dragonstone::CLIBuild.build_command(["--target", "llvm", "--output", dir, source], stdout, stderr)
          binary = File.join(dir, "dragonstone_llvm#{Dragonstone::CLIBuild::EXECUTABLE_SUFFIX}")
          status == 0 && File.exists?(binary)
        ensure
          FileUtils.rm_rf(dir)
        end
      end
    end
  end
end

describe "Default parameters" do
  program = <<-DS
  def alpha(name: str = "Jules") -> str
    echo "Hello, \#{name}!"
  end

  def bravo(name = "Jules")
    echo "Hello, \#{name}!"
  end

  alpha()
  alpha("Ringo")
  bravo()
  bravo("Ringo")
  DS

  %w[auto native core].each do |backend|
    it "expands default values on #{backend} backend" do
      result = run_program_via_cli(program, backend)
      result[:status].should eq(0)
      result[:stderr].should be_empty
      result[:stdout].should contain("Hello, Jules!")
      result[:stdout].should contain("Hello, Ringo!")
    end
  end

  it "works when compiled via LLVM target when clang is available" do
    pending!("LLVM toolchain not available; skipping LLVM default parameter test") unless LLVMDefaultParamIntegration.available?

    dir = File.join("dev", "build", "spec", "default_params_llvm_spec_#{Random::Secure.hex(8)}")
    FileUtils.mkdir_p(dir)
    begin
      source_file = File.join(dir, "default_params.ds")
      File.write(source_file, program)

      stdout = IO::Memory.new
      stderr = IO::Memory.new
      status = Dragonstone::CLIBuild.build_and_run_command(["--target", "llvm", "--output", dir, source_file], stdout, stderr)
      status.should eq(0)
      stderr.to_s.should_not contain("ERROR:")
      stdout.to_s.should contain("Hello, Jules!")
      stdout.to_s.should contain("Hello, Ringo!")
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
