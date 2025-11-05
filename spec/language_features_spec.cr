require "spec"
require "../src/dragonstone"

describe "language features" do
    it "creates and uses para literals" do
        source = <<-DS
#! typed
square: para(int, int) = ->(x: int) { x * x }
puts square.call(5)
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
    puts x
    puts y
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
    puts i
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

puts numbers.size
puts numbers.includes?(3)

doubled = numbers.map do |value|
    value * 2
end

puts doubled.length
DS
        result = Dragonstone.run(source, typed: true)
        result.output.should eq "2\ntrue\n2\n"
    end
end
