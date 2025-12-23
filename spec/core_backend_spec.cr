require "spec"
require "file_utils"
require "../src/dragonstone"

describe "core backend execution" do
    it "supports operator overloading operators in class methods" do
        source = <<-DS
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
        result = Dragonstone.run(source, backend: Dragonstone::BackendMode::Core)
        result.output.should eq "8\n2\n20\n25\n2.5\n2\n2\ntrue\ntrue\ntrue\ntrue\ntrue\nfalse\n20\n2\n"
    end

    it "supports super calls in class methods" do
        source = <<-DS
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
        result = Dragonstone.run(source, backend: Dragonstone::BackendMode::Core)
        result.output.should eq "Hello, everyone\nHello, again\n"
    end

    it "raises when super is used outside a method on the core backend" do
        expect_raises(Dragonstone::InterpreterError) do
            Dragonstone.run("super(1)\n", backend: Dragonstone::BackendMode::Core)
        end
    end

    it "evaluates conditional expressions (ternary operator)" do
        source = <<-DS
age = 20
status = age >= 18 ? "Adult" : "Minor"
echo "Status: \#{status}"

score = 85
grade = score > 90 ? "A" : (score > 80 ? "B" : "C")
echo "Grade: \#{grade}"
DS
        result = Dragonstone.run(source, backend: Dragonstone::BackendMode::Core)
        result.output.should eq "Status: Adult\nGrade: B\n"
    end

    it "evaluates array enumerators with block control flow" do
        source = <<-DS
numbers = [1, 2, 3, 4]
sum = 0

numbers.each do |n|
    next if n == 2
    sum += n
    break if n == 3
end

echo sum

mapped = numbers.map do |n|
    next if n <= 1
    break if n == 4
    n * 10
end

echo mapped.length
echo mapped.first
echo mapped.last
DS
        result = Dragonstone.run(source, backend: Dragonstone::BackendMode::Core)
        result.output.should eq "4\n2\n20\n30\n"
    end

    it "allocates fresh empty array literals" do
        source = <<-DS
a = []
b = []
a.push(1)
echo b.length
DS
        result = Dragonstone.run(source, backend: Dragonstone::BackendMode::Core)
        result.output.should eq "0\n"
    end

    it "retries array iterations when redo is invoked" do
        source = <<-DS
values = [1, 2, 3]
sum = 0
redo_used = false

values.each do |value|
    if value == 2 && !redo_used
        redo_used = true
        redo
    end

    sum += value
end

echo sum
echo redo_used
DS
        result = Dragonstone.run(source, backend: Dragonstone::BackendMode::Core)
        result.output.should eq "6\ntrue\n"
    end

    it "handles typed bags under the core backend" do
        source = <<-DS
#! typed
numbers = bag(int).new
numbers.add(1)
numbers.add(2)
numbers.add(3)

sum = 0
numbers.each do |value|
    next if value == 1
    sum += value
    break if value == 3
end

echo sum

product = numbers.inject(1) do |memo, value|
    memo * value
end

echo product
DS
        result = Dragonstone.run(source, typed: true, backend: Dragonstone::BackendMode::Core)
        result.output.should eq "5\n6\n"
    end

    it "enforces typed assignments when running on the core backend" do
        source = <<-DS
#! typed
name: str = 1
DS
        expect_raises(Dragonstone::TypeError) do
            Dragonstone.run(source, typed: true, backend: Dragonstone::BackendMode::Core)
        end
    end

    it "evaluates para literals and allows calling them" do
        source = <<-DS
greet = ->(name: str) { "Hello, \#{name}!" }
echo greet.call("Jalyn")

square = ->(value: int) { value * value }
echo square.call(6)
DS
        result = Dragonstone.run(source, backend: Dragonstone::BackendMode::Core)
        result.output.should eq "Hello, Jalyn!\n36\n"
    end

    it "captures lexical variables in para literals" do
        source = <<-DS
def make_adder(x)
    adder = ->(y) { x + y }
    adder
end

add5 = make_adder(5)
echo add5.call(3)

def make_counter
    x = 0
    counter = -> {
        x += 1
        x
    }
    counter
end

counter = make_counter()
echo counter.call()
echo counter.call()
DS
        result = Dragonstone.run(source, backend: Dragonstone::BackendMode::Core)
        result.output.should eq "8\n1\n2\n"
    end

    it "supports tuple and named tuple literals" do
        source = <<-DS
data = {1, "two", 3}
echo data.length
echo data[1]

person = {name: "Ada", age: 37}
echo person[:name]
echo person[:age]
DS
        result = Dragonstone.run(source, backend: Dragonstone::BackendMode::Core)
        result.output.should eq "3\ntwo\nAda\n37\n"
    end

    it "evaluates unless statements" do
        source = <<-DS
username = "guest"

unless username == "admin"
    echo "Not an admin"
else
    echo "Welcome, admin!"
end
DS
        result = Dragonstone.run(source, backend: Dragonstone::BackendMode::Core)
        result.output.should eq "Not an admin\n"
    end

    it "handles instance variable declarations and accessors" do
        source = <<-DS
class Person
    @name: str
    @age: int

    getter name, age

    def initialize(@name, @age)
    end
end

person = Person.new("Jules", 30)
echo person.name
echo person.age
DS
        result = Dragonstone.run(source, backend: Dragonstone::BackendMode::Core)
        result.output.should eq "Jules\n30\n"
    end

    it "loads modules via use declarations on the core backend" do
        base_tmp = File.join(Dir.current, "tmp")
        FileUtils.mkdir_p(base_tmp)
        dir = File.join(base_tmp, "core_use_#{Time.utc.to_unix}_#{Process.pid}")
        FileUtils.rm_rf(dir)
        Dir.mkdir(dir)
        begin
            helpers = File.join(dir, "helpers.ds")
            people = File.join(dir, "people.ds")
            entry = File.join(dir, "main.ds")

            File.write(helpers, <<-DS)
con magic = 42

def add(a, b)
    a + b
end
DS

            File.write(people, <<-DS)
class Person
    def greet
        echo "Hi from Person"
    end
end
DS

            File.write(entry, <<-DS)
use "helpers.ds"
use { Person } from "people.ds"

echo add(magic, 8)

person = Person.new
person.greet
DS

            result = Dragonstone.run_file(entry, backend: Dragonstone::BackendMode::Core)
            result.output.should eq "50\nHi from Person\n"
        ensure
            FileUtils.rm_rf(dir)
        end
    end
end
