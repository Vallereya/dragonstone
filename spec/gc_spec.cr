require "spec"
require "../src/dragonstone"

BACKENDS = [Dragonstone::BackendMode::Native, Dragonstone::BackendMode::Core]

describe "gc integration" do
    it "respects gc.disable and with_disabled scopes" do
        source = <<-DS
@[gc.disable]
def work
    gc.disable
    gc.enable
    7
end

echo work()

gc.with_disabled do
    echo 8
end
DS
        BACKENDS.each do |backend|
            Dragonstone.run(source, backend: backend).output.should eq "7\n8\n"
        end
    end

    it "tracks areas and clears current_area after end" do
        source = <<-DS
@[gc.area]
def uses_area
    echo gc.current_area.nil?
end

uses_area
echo gc.current_area.nil?
DS
        BACKENDS.each do |backend|
            Dragonstone.run(source, backend: backend).output.should eq "false\ntrue\n"
        end
    end

    it "deep copies arrays, maps, bags, and tuples" do
        source = <<-DS
#! typed
arr = [1, [2]]
arr_copy = gc.copy(arr)
arr[1][0] = 9

map = { "a" -> [1, 2] }
map_copy = gc.copy(map)
map["a"][0] = 7

numbers = bag(int).new
numbers.add(1)
numbers.add(2)
bag_copy = gc.copy(numbers)
numbers.add(3)

tuple = {1, [2]}
tuple_copy = gc.copy(tuple)
tuple[1][0] = 5

echo arr_copy[1][0]
echo map_copy["a"][0]
echo bag_copy.includes?(3)
echo tuple_copy[1][0]
DS
        BACKENDS.each do |backend|
            Dragonstone.run(source, backend: backend, typed: true).output.should eq "2\n1\nfalse\n2\n"
        end
    end
end
