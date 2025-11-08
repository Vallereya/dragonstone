require "spec"
require "../src/dragonstone"

describe "language features" do
    it "creates and uses para literals" do
        source = <<-DS
#! typed
square: para(int, int) = ->(x: int) { x * x }
echo square.call(5)
DS
        result = Dragonstone.run(source, typed: true)
        result.output.should eq "25\n"
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
end
