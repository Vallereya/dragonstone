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
                dir = File.join("bin", "dev", "build", "spec", "llvm_default_params_probe_#{Random::Secure.hex(8)}")
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

    # Defaults used to be restricted to literals outright, 
    # which rejected plenty that has nothing to do with 
    # scope like `-1`, `[]`, `1 + 2` and blocked the 
    # self-hosted resolver, which `encoding.ds` defaults 
    # a parameter to a constant. Both runtimes already 
    # evaluated the default node, so only the parser 
    # guard needed to move.
    describe "non-literal defaults" do
        {
            "a constant"           => {"con LIMIT = 7\ndef f(x = LIMIT)\n  echo x\nend\nf()\n", "7"},
            "a qualified constant" => {"module Conf\n  con LIMIT = 8\nend\ndef f(x = Conf::LIMIT)\n  echo x\nend\nf()\n", "8"},
            "a negative number"    => {"def f(x = -1)\n  echo x\nend\nf()\n", "-1"},
            "an arithmetic expr"   => {"def f(x = 2 + 3)\n  echo x\nend\nf()\n", "5"},
            "an empty array"       => {"def f(x = [])\n  echo x.length\nend\nf()\n", "0"},
            "an array of literals" => {"def f(x = [1, 2])\n  echo x.length\nend\nf()\n", "2"},
        }.each do |description, (source, expected)|
            %w[native core].each do |backend|
                it "accepts #{description} on #{backend}" do
                    result = run_program_via_cli(source, backend)
                    result[:stderr].should be_empty
                    result[:status].should eq(0)
                    result[:stdout].should contain(expected)
                end
            end
        end

        it "still overrides the default when an argument is passed" do
            source = "con LIMIT = 7\ndef f(x = LIMIT)\n  echo x\nend\nf(99)\n"
            result = run_program_via_cli(source, "native")
            result[:status].should eq(0)
            result[:stdout].should contain("99")
            result[:stdout].should_not contain("7")
        end
    end

    # A default is evaluated in the caller's scope by both 
    # runtimes, so a default naming a local or calling a 
    # method would resolve against whoever called rather 
    # than against the method. Rejected at parse time 
    # instead.
    describe "rejected defaults" do
        it "rejects referencing a local variable" do
            result = run_program_via_cli("other = 1\ndef f(x = other)\n  echo x\nend\nf()\n", "native")
            result[:status].should_not eq(0)
            result[:stderr].should contain("cannot reference a local variable or parameter")
        end

        it "rejects referencing an earlier parameter" do
            result = run_program_via_cli("def f(a, b = a)\n  echo b\nend\nf(1)\n", "native")
            result[:status].should_not eq(0)
            result[:stderr].should contain("cannot reference a local variable or parameter")
        end

        it "rejects a method call" do
            result = run_program_via_cli("def helper\n  1\nend\ndef f(x = helper())\n  echo x\nend\nf()\n", "native")
            result[:status].should_not eq(0)
            result[:stderr].should contain("must be a literal, a constant, or an operation on them")
        end

        it "rejects a local nested inside an allowed expression" do
            result = run_program_via_cli("other = 1\ndef f(x = [1, other])\n  echo x\nend\nf()\n", "native")
            result[:status].should_not eq(0)
            result[:stderr].should contain("cannot reference a local variable or parameter")
        end
    end

    it "works when compiled via LLVM target when clang is available" do
        pending!("LLVM toolchain not available; skipping LLVM default parameter test") unless LLVMDefaultParamIntegration.available?

        dir = File.join("bin", "dev", "build", "spec", "default_params_llvm_spec_#{Random::Secure.hex(8)}")
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
