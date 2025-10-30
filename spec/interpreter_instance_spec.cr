require "spec"
require "../src/dragonstone/lib/lexer/*"
require "../src/dragonstone/lib/parser/*"
require "../src/dragonstone/lib/interpreter/*"

private def run_program(source : String, typing : Bool = false)
    tokens = Dragonstone::Lexer.new(source).tokenize
    ast = Dragonstone::Parser.new(tokens).parse
    interpreter = Dragonstone::Interpreter.new(false, typing)
    interpreter.interpret(ast)
end

describe "Constant path resolution" do
    it "resolves nested constants and classes through scope resolution" do
        source = <<-DS
        module Outer
            module Inner
                VALUE = 99

                class Thing
                    def initialize
                    end

                    def greet
                        "hello"
                    end
                end
            end
        end

        puts Outer::Inner::VALUE
        thing = Outer::Inner::Thing.new
        puts thing.greet
        DS

        run_program(source).should eq("99\nhello\n")
    end

    it "prints enum members using their name" do
        source = <<-DS
        enum Color
            Red
            Green
        end

        puts Color::Green
        DS

        run_program(source).should eq("Green\n")
    end
end

describe "Interpreter instance variable support" do
    it "exposes instance state through generated getter" do
        source = <<-DS
        class Person
            getter name

            def initialize(@name)
            end
        end

        person = Person.new("Alice")
        puts person.name
        DS

        run_program(source).should eq("Alice\n")
    end

    it "updates state through property setter" do
        source = <<-DS
        class Counter
            property value: int

            def initialize(@value: int)
            end

            def bump(amount: int)
                self.value += amount
            end
        end

        counter = Counter.new(5)
        counter.bump(3)
        puts counter.value
        DS

        run_program(source, typing: true).should eq("8\n")
    end

    it "rejects invalid assignments based on property type" do
        source = <<-DS
        class Account
            property balance: int

            def initialize(@balance: int)
            end
        end

        account = Account.new(100)
        account.balance = "oops"
        DS

        expect_raises(Dragonstone::TypeError) do
            run_program(source, typing: true)
        end
    end

    it "prevents calling private methods with an explicit receiver" do
        source = <<-DS
        class BankAccount
            def initialize(balance)
                @balance = balance
            end

            private def balance
                @balance
            end

            def reveal
                balance
            end
        end

        account = BankAccount.new(50)
        puts account.reveal
        account.balance
        DS

        expect_raises(Dragonstone::InterpreterError) do
            run_program(source)
        end
    end
end
