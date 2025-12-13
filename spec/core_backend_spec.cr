require "spec"
require "file_utils"
require "../src/dragonstone"

describe "core backend execution" do
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
