require "spec"
require "../src/dragonstone/cli/cli"

private def cli_run_for(program_source : String, backend : String)
    file = File.tempfile("dragonstone-smoke", suffix: ".ds")
    begin
        file.print(program_source)
        file.flush

        stdout = IO::Memory.new
        stderr = IO::Memory.new
        status = Dragonstone::CLI.run(["run", "--backend", backend, file.path], stdout, stderr)

        {
            status: status,
            stdout: stdout.to_s,
            stderr: stderr.to_s,
        }
    ensure
        path = file.path
        file.close
        File.delete(path) if File.exists?(path)
    end
end

describe Dragonstone::CLI do
    it "returns an error when the file is missing" do
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        status = Dragonstone::CLI.run(["lex", "missing.ds"], stdout, stderr)
        status.should eq(1)
        stderr.to_s.should contain("not found")
    end

    it "prints version information" do
        stdout = IO::Memory.new
        stderr = IO::Memory.new
        status = Dragonstone::CLI.run(["version"], stdout, stderr)
        status.should eq(0)
        stdout.to_s.should contain("Dragonstone #{Dragonstone::VERSION}")
    end
    
    it "lexes a program" do
        File.tempfile("dragonstone", suffix: ".ds") do |file|
            file.print("echo 1\n")
            file.flush
            stdout = IO::Memory.new
            stderr = IO::Memory.new
            status = Dragonstone::CLI.run(["lex", file.path], stdout, stderr)
            status.should eq(0)
            stdout.to_s.should contain("------- Tokens for #{file.path}")
            stdout.to_s.should contain("Token(ECHO")
            stderr.to_s.should be_empty
        end
    end

    it "parses a program and prints function definitions" do
        File.tempfile("dragonstone", suffix: ".ds") do |file|
            file.print("def greet(name)\n  echo name\nend\n")
            file.flush

            stdout = IO::Memory.new
            stderr = IO::Memory.new
            status = Dragonstone::CLI.run(["parse", file.path], stdout, stderr)

            status.should eq(0)
            stdout.to_s.should contain("FunctionDef: greet(name)")
            stderr.to_s.should be_empty
        end
    end

    it "runs a program and streams interpreter output" do
        File.tempfile("dragonstone", suffix: ".ds") do |file|
            file.print("echo \"Hello, Dragonstone!\"")
            file.flush

            stdout = IO::Memory.new
            stderr = IO::Memory.new
            status = Dragonstone::CLI.run(["run", file.path], stdout, stderr)

            status.should eq(0)
            stdout.to_s.should contain("Hello, Dragonstone!")
            stderr.to_s.should be_empty
        end
    end

    it "runs a program via the core backend when requested" do
        File.tempfile("dragonstone-core", suffix: ".ds") do |file|
            file.print("echo \"Hello from core\"")
            file.flush

            stdout = IO::Memory.new
            stderr = IO::Memory.new
            status = Dragonstone::CLI.run(["run", "--backend", "core", file.path], stdout, stderr)

            status.should eq(0)
            stdout.to_s.should contain("Hello from core")
            stderr.to_s.should be_empty
        end
    end

    it "reports an error for unknown backend values" do
        File.tempfile("dragonstone-bad-backend", suffix: ".ds") do |file|
            file.print("echo 1")
            file.flush

            stdout = IO::Memory.new
            stderr = IO::Memory.new
            status = Dragonstone::CLI.run(["run", "--backend", "warp", file.path], stdout, stderr)

            status.should eq(1)
            stderr.to_s.should contain("Unknown backend 'warp'")
            stdout.to_s.should be_empty
        end
    end

    it "returns an error code when run raises a syntax error" do
        File.tempfile("dragonstone", suffix: ".ds") do |file|
            file.print("def broken(\n")
            file.flush

            stdout = IO::Memory.new
            stderr = IO::Memory.new
            status = Dragonstone::CLI.run(["run", file.path], stdout, stderr)

            status.should eq(1)
            stderr.to_s.should contain("Error:")
        end
    end

    it "runs the same smoke programs through native and core backends" do
        programs = [
            {name: "hello world", source: %(echo "smoke!") },
            {name: "loop counters", source: "i = 3\nwhile i > 0\n    echo i\n    i = i - 1\nend\n"},
        ]

        programs.each do |program|
            native = cli_run_for(program[:source], "native")
            core = cli_run_for(program[:source], "core")

            native[:status].should eq(0)
            native[:stderr].should be_empty
            core[:status].should eq(0)
            core[:stderr].should be_empty
            core[:stdout].should eq(native[:stdout])
        end
    end
end
