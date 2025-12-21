require "spec"
require "../src/dragonstone"

describe "language features" do
    it "scopes let declarations to blocks" do
        source = <<-DS
x = 1
if true
    let x = 2
    echo x
end
echo x
DS
        result = Dragonstone.run(source)
        result.output.should eq "2\n1\n"
    end

    it "prevents reassignment of let and fix bindings" do
        result = Dragonstone.run("if true\n  let x = 1\n  x = 2\n  echo x\nend\n")
        result.output.should eq "2\n"

        expect_raises(Dragonstone::ConstantError) do
            Dragonstone.run("if true\n  fix x = 1\n  x = 2\nend\n")
        end
    end

    it "does not rewrite shadowed parameters for let bindings" do
        source = <<-DS
let x = 1
def show(x)
    echo x
end
show(5)
DS
        result = Dragonstone.run(source)
        result.output.should eq "5\n"
    end

    it "supports @@ class variables shared across instances" do
        source = <<-DS
class Counter
    @@count = 0

    def initialize
        @@count += 1
    end

    def self.count
        @@count
    end
end

Counter.new
Counter.new
echo Counter.count
DS
        result = Dragonstone.run(source)
        result.output.should eq "2\n"
    end

    it "supports @@@ module variables shared across the module" do
        source = <<-DS
module Tracker
    @@@count = 0

    def self.inc
        @@@count += 1
    end

    def self.count
        @@@count
    end
end

Tracker.inc
Tracker.inc
echo Tracker.count
DS
        result = Dragonstone.run(source)
        result.output.should eq "2\n"
    end

    it "rejects class/module variables outside containers" do
        expect_raises(Dragonstone::ParserError) do
            Dragonstone.run("@@count = 1\n")
        end

        expect_raises(Dragonstone::ParserError) do
            Dragonstone.run("@@@count = 1\n")
        end
    end

    it "supports Array#empty? in the native backend" do
        result = Dragonstone.run("echo argv.empty?\n", argv: ["one"])
        result.output.should eq "false\n"
    end

    it "creates and uses para literals" do
        source = <<-DS
#! typed
square: para(int, int) = ->(x: int) { x * x }
echo square.call(5)
DS
        result = Dragonstone.run(source, typed: true)
        result.output.should eq "25\n"
    end

    it "supports singleton methods on objects and classes" do
        source = <<-DS
greeting = "Hello"

def greeting.shout
    upcase + "!"
end

echo greeting.shout

class Phrase
    GREETING = "hi"

    def self.loud
        GREETING.upcase
    end
end

echo Phrase.loud
DS
        result = Dragonstone.run(source)
        result.output.should eq "HELLO!\nHI\n"
    end

    it "supports super calls in the native backend" do
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
        result = Dragonstone.run(source, backend: Dragonstone::BackendMode::Native)
        result.output.should eq "Hello, everyone\nHello, again\n"
    end

    it "supports operator overloading operators in the native backend" do
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
        result = Dragonstone.run(source, backend: Dragonstone::BackendMode::Native)
        result.output.should eq "8\n2\n20\n25\n2.5\n2\n2\ntrue\ntrue\ntrue\ntrue\ntrue\nfalse\n20\n2\n"
    end

    it "raises when super is used outside a method in the native backend" do
        expect_raises(Dragonstone::InterpreterError) do
            Dragonstone.run("super(1)\n", backend: Dragonstone::BackendMode::Native)
        end
    end

    it "supports with blocks as implicit receivers" do
        source = <<-DS
struct Point
    property x: int
    property y: int
end

point = Point.new(x: 1, y: 2)

with point
    echo x
    echo y
end
DS
        result = Dragonstone.run(source)
        result.output.should eq "1\n2\n"
    end

    it "yields to provided blocks" do
        source = <<-DS
def repeat(times)
    index = 0
    while index < times
        yield index
        index += 1
    end
end

repeat(3) do |i|
    echo i
end
DS
        result = Dragonstone.run(source)
        result.output.should eq "0\n1\n2\n"
    end

    it "manages typed bags with higher-order helpers" do
        source = <<-DS
#! typed
numbers = bag(int).new
numbers.add(1)
numbers.add(1)
numbers.add(3)

echo numbers.size
echo numbers.includes?(3)

doubled = numbers.map do |value|
    value * 2
end

echo doubled.length
DS
        result = Dragonstone.run(source, typed: true)
        result.output.should eq "2\ntrue\n2\n"
    end

    it "supports loop escapes inside array enumerators" do
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
        result = Dragonstone.run(source)
        result.output.should eq "4\n2\n20\n30\n"
    end

    it "supports loop escapes inside bag enumerators" do
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

values = numbers.map do |value|
    next if value == 1
    break if value == 3
    value * 5
end

echo values.length
values.each do |value|
    echo value
end
DS
        result = Dragonstone.run(source, typed: true)
        result.output.should eq "5\n1\n10\n"
    end

    it "provides select, inject, and until helpers across collections" do
        source = <<-DS
numbers = [1, 2, 3, 4, 5]

selected = numbers.select do |value|
    value % 2 == 1
end

echo selected.length
echo selected.first
echo selected.last

sum = numbers.inject do |memo, value|
    memo + value
end

echo sum

first_over_three = numbers.until do |value|
    value > 3
end

echo first_over_three

scores = {"arya" -> 9, "bran" -> 5, "sansa" -> 8}

high_scores = scores.select do |name, score|
    score >= 8
end

echo high_scores.length
echo high_scores["arya"]
echo high_scores.has_key?("bran")

total_score = scores.inject(0) do |memo, _name, score|
    memo + score
end

echo total_score

match = scores.until do |name, score|
    score == 5
end

if match
    echo match.first
    echo match.last
else
    echo "none"
end

numbers_bag = bag(int).new
numbers_bag.add(2)
numbers_bag.add(3)
numbers_bag.add(5)

large_bag = numbers_bag.select do |value|
    value >= 3
end

echo large_bag.size

product = numbers_bag.inject(1) do |memo, value|
    memo * value
end

echo product

first_even = numbers_bag.until do |value|
    value % 2 == 0
end

echo first_even
DS
        result = Dragonstone.run(source)
        result.output.should eq "3\n1\n5\n15\n4\n2\n9\nfalse\n22\nbran\n5\n2\n30\n2\n"
    end

    it "supports redo within collection each helpers" do
        source = <<-DS
numbers = [1, 2]
array_redos = 0

numbers.each do |value|
    if value == 1 && array_redos == 0
        array_redos += 1
        redo
    end
end

echo array_redos

pairs = {"a" -> 1, "b" -> 2}
map_redos = 0

pairs.each do |key, _value|
    if key == "a" && map_redos == 0
        map_redos += 1
        redo
    end
end

echo map_redos

counts = bag(int).new
counts.add(10)
counts.add(20)

bag_redos = 0

counts.each do |value|
    if value == 10 && bag_redos == 0
        bag_redos += 1
        redo
    end
end

echo bag_redos
DS
        result = Dragonstone.run(source)
        result.output.should eq "1\n1\n1\n"
    end

    it "converts runtime values with display and inspect" do
        source = <<-'DS'
class Person
    def initialize(@name)
    end

    def display
        "Person(#{@name})"
    end

    def inspect
        "<Person #{@name}>"
    end
end

person = Person.new("Arya")
numbers = [1, 2]
text = "hi"
nil_value = nil

echo "nil-display:" + nil_value.display
echo "nil-inspect:" + nil_value.inspect
echo "int-display:" + 25.display
echo "int-inspect:" + 25.inspect
echo "text-display:" + text.display
echo "text-inspect:" + text.inspect
echo "array-display:" + numbers.display
echo "array-inspect:" + numbers.inspect
echo "person-display:" + person.display
echo "person-inspect:" + person.inspect
DS
        result = Dragonstone.run(source)
        expected_output = <<-OUT
nil-display:
nil-inspect:nil
int-display:25
int-inspect:25
text-display:hi
text-inspect:"hi"
array-display:[1, 2]
array-inspect:[1, 2]
person-display:Person(Arya)
person-inspect:<Person Arya>
OUT
        result.output.should eq expected_output + "\n"
    end

    it "slices strings by codepoint and enforces bounds" do
        source = <<-DS
s = "🔥dragon🪄"
echo s.slice(0, 2)
echo s.slice(2..4)
echo s.slice(6, 2)
DS
        result = Dragonstone.run(source)
        result.output.should eq "🔥d\nrag\nn🪄\n"

        bad_source = <<-DS
s = "🔥dragon🪄"
s.slice(100, 1)
DS
        expect_raises(Dragonstone::OutOfBounds) do
            Dragonstone.run(bad_source)
        end
    end

    it "strips leading and trailing whitespace" do
        source = <<-DS
s1 = "  Dragonstone  "
echo s1.strip
s2 = "\\tHello\\n"
echo s2.strip
s3 = "   "
echo "empty:\#{s3.strip}"
DS
        result = Dragonstone.run(source)
        result.output.should eq "Dragonstone\nHello\nempty:\n"
    end

    it "accepts var as explicit assignment" do
        source = <<-DS
x = 1
var y = 2
echo x
echo y
DS
        result = Dragonstone.run(source)
        result.output.should eq "1\n2\n"
    end

    it "supports abstract classes across native and core backends" do
        source = <<-DS
abstract class Animal
    abstract def sound
    end
end

class Dog < Animal
    def sound
        "woof"
    end
end

echo Dog.new.sound
DS
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Native).output.should eq("woof\n")
        Dragonstone.run(source, backend: Dragonstone::BackendMode::Core).output.should eq("woof\n")
    end

    it "parses annotated definitions without affecting execution" do
        source = <<-DS
@[gc.disable]
def greet
    echo "hi"
end

@[meta.tag]
class Box
    def value
        42
    end
end

greet
echo Box.new.value
DS
        result = Dragonstone.run(source)
        result.output.should eq "hi\n42\n"
    end
end
