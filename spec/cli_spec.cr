require "spec"
require "../src/dragonstone/cli"
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
            file.print("puts 1\n")
            file.flush
            stdout = IO::Memory.new
            stderr = IO::Memory.new
            status = Dragonstone::CLI.run(["lex", file.path], stdout, stderr)
            status.should eq(0)
            stdout.to_s.should contain("=== Tokens for #{file.path}")
            stdout.to_s.should contain("Token(PUTS")
            stderr.to_s.should be_empty
        end
    end

    it "parses a program and prints function definitions" do
        File.tempfile("dragonstone", suffix: ".ds") do |file|
            file.print("def greet(name)\n  puts name\nend\n")
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
            file.print("puts \"Hello, Dragonstone!\"")
            file.flush

            stdout = IO::Memory.new
            stderr = IO::Memory.new
            status = Dragonstone::CLI.run(["run", file.path], stdout, stderr)

            status.should eq(0)
            stdout.to_s.should contain("Hello, Dragonstone!")
            stderr.to_s.should be_empty
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
end
