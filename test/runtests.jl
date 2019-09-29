using Beancount
using Dates
using Test
using Decimals

"Extract type of transaction."
typ(::Transaction{T}) where T = T

@testset "Loading Files" begin
    # Load test file
    entries, errors, options = Beancount.load_file("testfile.beancount")

    # Check loaded data and options
    @test length(entries)               == 8
    @test length(errors)                == 0
    @test options["title"]              == "Beancount Example Ledger"
    @test options["operating_currency"] == ["EUR"]

    # Parse what can be parsed
    parsed = from_python.(entries)

    # Check parsed transactions and postings
    @test parsed[5].date                 == Date(2007,12,31)
    @test parsed[5] |> typ               == pad
    @test parsed[5].description          == "(Padding inserted for Balance of 1412.24 EUR for difference 1412.24 EUR)"
    @test parsed[5].payee                == nothing
    @test parsed[5].postings[1].account  == "Assets:TestAccount"
    @test parsed[5].postings[1].value    == 1412.24
    @test parsed[5].postings[1].currency == "EUR"
    @test parsed[5].postings[2].account  == "Equity:Opening-Balances"
    @test parsed[5].postings[2].value    == -1412.24
    @test parsed[5].postings[2].currency == "EUR"
    @test parsed[7].date                 == Date(2008,01,01)
    @test parsed[7] |> typ               == txn
    @test parsed[7].description          == "Else"
    @test parsed[7].payee                == "Something"
    @test parsed[7].postings[1].account  == "Assets:TestAccount"
    @test parsed[7].postings[1].value    == -30
    @test parsed[7].postings[1].currency == "EUR"
    @test parsed[7].postings[2].account  == "Expenses:Stuff"
    @test parsed[7].postings[2].value    == 5562
    @test parsed[7].postings[2].currency == "USD"
    @test parsed[7].tags                 == Set(["tagA", "tagB"])
    @test parsed[7].links                == Set(["linkA"])
end

@testset "Writing Files" begin
    # Write Transactions
    tx = Transaction{txn}(date=today(),description="This is the description",tags=Set(["foo", "bar"]))
    push!(tx,Posting(account="Equity:Opening-Balances"))
    push!(tx,Posting(account="Assets:TestAccount",value=decimal("100.3")))

    open("test.beancount","w") do f
        println(f,"1970-01-01 open Equity:Opening-Balances")
        println(f,"1970-01-01 open Assets:TestAccount")
        println(f,tx)
    end

    @test isfile("test.beancount")
    entries, errors, options = Beancount.load_file("test.beancount")
    isfile("test.beancount") && rm("test.beancount")

    @test length(errors) == 0

    parsed = from_python.(entries)
    @test parsed[end] == tx
end
