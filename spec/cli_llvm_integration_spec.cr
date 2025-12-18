require "spec"
require "file_utils"
require "../src/dragonstone"
require "../src/dragonstone/cli/cli_build"

private def clang_available? : Bool
    io = IO::Memory.new
    Process.run("clang", args: ["--version"], output: io, error: io).success?
rescue File::NotFoundError
    false
end

describe Dragonstone::CLIBuild do
    it "links LLVM artifacts into an executable when clang is available" do
        pending!("clang is not available; skipping LLVM linking integration test") unless clang_available?

        dir = File.join("dev", "build", "spec", "cli_llvm_spec_#{Random::Secure.hex(8)}")
        FileUtils.mkdir_p(dir)
        begin
            source = File.join(dir, "sample.ds")
            File.write(source, "echo \"llvm cli\"")

            stdout = IO::Memory.new
            stderr = IO::Memory.new
            Dragonstone::CLIBuild.build_command(["--target", "llvm", "--output", dir, source], stdout, stderr).should eq(0)

            binary = File.join(dir, "dragonstone_llvm#{Dragonstone::CLIBuild::EXECUTABLE_SUFFIX}")
            File.exists?(binary).should be_true
        ensure
            FileUtils.rm_rf(dir)
        end
    end

    it "executes user-defined iterator methods that yield when clang is available" do
        pending!("clang is not available; skipping LLVM iterator integration test") unless clang_available?

        dir = File.join("dev", "build", "spec", "cli_llvm_iterator_spec_#{Random::Secure.hex(8)}")
        FileUtils.mkdir_p(dir)
        begin
            source = File.join(dir, "iterator.ds")
            File.write(source, <<-DS)
class Countdown
    def initialize(start)
        @start = start
    end

    def each
        current = @start

        while current > 0
            yield current
            current = current - 1
        end

        yield "Blastoff!"
    end
end

timer = Countdown.new(3)
timer.each do |tick|
    echo tick
end
DS

            stdout = IO::Memory.new
            stderr = IO::Memory.new
            Dragonstone::CLIBuild.build_and_run_command(["--target", "llvm", "--output", dir, source], stdout, stderr).should eq(0)
            stderr.to_s.should_not contain("ERROR:")
            stdout.to_s.should eq("3\n2\n1\nBlastoff!\n")
        ensure
            FileUtils.rm_rf(dir)
        end
    end

    it "executes super calls when clang is available" do
        pending!("clang is not available; skipping LLVM super integration test") unless clang_available?

        dir = File.join("dev", "build", "spec", "cli_llvm_super_spec_#{Random::Secure.hex(8)}")
        FileUtils.mkdir_p(dir)
        begin
            source = File.join(dir, "super.ds")
            File.write(source, <<-DS)
class Person
    def greet(msg)
        echo "Hello, \#{msg}"
    end
end

class Employee < Person
    def greet(msg)
        super(msg)
        super("again")
    end
end

Employee.new.greet("everyone")
DS

            stdout = IO::Memory.new
            stderr = IO::Memory.new
            Dragonstone::CLIBuild.build_and_run_command(["--target", "llvm", "--output", dir, source], stdout, stderr).should eq(0)
            stderr.to_s.should_not contain("ERROR:")
            stdout.to_s.should eq("Hello, everyone\nHello, again\n")
        ensure
            FileUtils.rm_rf(dir)
        end
    end

    it "executes overloaded operators when clang is available" do
        pending!("clang is not available; skipping LLVM operator overloading integration test") unless clang_available?

        dir = File.join("dev", "build", "spec", "cli_llvm_overloading_spec_#{Random::Secure.hex(8)}")
        FileUtils.mkdir_p(dir)
        begin
            source = File.join(dir, "overloading.ds")
            File.write(source, <<-DS)
class Number
    def initialize(@value: int)
    end

    def +(other)
        @value + other
    end

    def -(other)
        @value - other
    end

    def *(other)
        @value * other
    end

    def **(other)
        @value ** other
    end

    def /(other)
        @value / other
    end

    def //(other)
        @value // other
    end

    def %(other)
        @value % other
    end

    def ==(other)
        @value == other
    end

    def !=(other)
        @value != other
    end

    def <(other)
        @value < other
    end

    def >(other)
        @value > other
    end

    def <=(other)
        @value <= other
    end

    def >=(other)
        @value >= other
    end

    def <<(other)
        @value << other
    end

    def >>(other)
        @value >> other
    end
end

num = Number.new(5)
echo num + 3
echo num - 3
echo num * 4
echo num ** 2
echo num / 2
echo num // 2
echo num % 3
echo num == 5
echo num != 3
echo num < 10
echo num > 2
echo num <= 5
echo num >= 6
echo num << 2
echo num >> 1
DS

            stdout = IO::Memory.new
            stderr = IO::Memory.new
            Dragonstone::CLIBuild.build_and_run_command(["--target", "llvm", "--output", dir, source], stdout, stderr).should eq(0)
            stderr.to_s.should_not contain("ERROR:")
            stdout.to_s.should eq("8\n2\n20\n25\n2.5\n2\n2\ntrue\ntrue\ntrue\ntrue\ntrue\nfalse\n20\n2\n")
        ensure
            FileUtils.rm_rf(dir)
        end
    end

    it "executes boxed arithmetic inside loops when clang is available" do
        pending!("clang is not available; skipping LLVM loop arithmetic integration test") unless clang_available?

        dir = File.join("dev", "build", "spec", "cli_llvm_loop_arithmetic_spec_#{Random::Secure.hex(8)}")
        FileUtils.mkdir_p(dir)
        begin
            source = File.join(dir, "sum_array.ds")
            File.write(source, <<-DS)
def sum_array(arr)
    total = 0
    i = 0

    while i < arr.length
        total = total + arr[i]
        i = i + 1
    end

    return total
end

numbers = [1, 2, 3, 4, 5]
echo sum_array(numbers)
DS

            stdout = IO::Memory.new
            stderr = IO::Memory.new
            Dragonstone::CLIBuild.build_and_run_command(["--target", "llvm", "--output", dir, source], stdout, stderr).should eq(0)
            stderr.to_s.should_not contain("ERROR:")
            stdout.to_s.should eq("15\n")
        ensure
            FileUtils.rm_rf(dir)
        end
    end
end
