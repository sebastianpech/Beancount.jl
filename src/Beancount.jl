module Beancount

using PyCall
using Decimals
using Dates
using Parameters

const DEFAULT_CURRENCY = "EUR"
const aDict = Union{Nothing,Dict{Any,Any}}
const SN = Union{Nothing,String}
const DN = Union{Nothing,Decimal}

function __init__()
    global loader, load_file
    loader = pyimport("beancount.loader")
    load_file = loader.load_file
end

export  Posting, Transaction, issimilar, balances, isTransaction

Base.homedir(path::AbstractString...) = joinpath(homedir(),path...)

struct Posting
    location::aDict
    account::String
    value::DN
    currency::SN
    comment::SN
    Posting(tup::Tuple{String,Tuple{PyObject,String},Any,Any,Any,Dict{Any,Any}}) = new(
        tup[end],
        tup[1],
        convert(Decimal,tup[2][1]),
        tup[2][2],nothing)
    Posting(;account::String,value::DN=nothing,currency::SN=nothing,comment::SN=nothing) = new(
        nothing,account,value,currency,comment)
end

function Base.show(io::IO,p::Posting)
    @unpack account,value,currency,comment = p
    _comment = comment == nothing ? "" : " ; $comment"
    if value == nothing
        print(io,"$account$_comment")
    else
        _currency = currency == nothing ? DEFAULT_CURRENCY : currency
        print(io,"$account  $value $_currency$_comment")
    end
end

struct Transaction
    location::aDict
    date::Date
    payee::SN
    description::String
    tags::Set{String}
    links::Set{String}
    postings::Vector{Posting}
    function Transaction(tup::Tuple{aDict,Date,Any,Any,Any,Any,Any,Any})
        @assert tup[3] == "*" || tup[3] == "txn"
        new(tup[1], tup[2], tup[4], tup[5],
            Set(tup[6]), Set(tup[7]),
            Posting.(tup[8]))
    end
    Transaction(;date::Date,payee::SN=nothing,description::String,tags::Set{String}=Set{String}(),links::Set{String}=Set{String}(),postings::Vector{Posting}=Posting[]) = new(
        nothing,date,clean_text(payee),clean_text(description),tags,links,postings)
end
clean_text(::Nothing) = nothing
function clean_text(st::String)
    reduce(replace,[
        "\n" => " ",
        "\t" => " ",
        r" {2,}" => " ",
    ],init=st)
end

function Base.show(io::IO,t::Transaction)
    @unpack date,payee,description,tags,links,postings = t
    _links = join("^".*links)
    _tags = join("#".*tags)
    _payee = payee == nothing ? "" : " \"$payee\""
    print(io,"$date *$_payee \"$description\" $_tags $_links")
    for p in postings
        print(io,"\n")
        print(io," "^4)
        show(io,p)
    end
end

function sum_positive(txA::Transaction)
    mapreduce(+,txA.postings) do p
        (p.value == nothing || p.value < 0) ? Decimal(0) : p.value
    end
end

function sum_negative(txA::Transaction)
    mapreduce(+,txA.postings) do p
        (p.value == nothing || p.value > 0) ? Decimal(0) : p.value
    end
end

function issimilar(txA::Transaction,txB::Transaction)
    (txA.date == txB.date) &&
    (sum_negative(txA) == sum_negative(txB) ||
    sum_positive(txA) == sum_positive(txB ))
end

function balances(tx::Transaction)
    sum_positive(tx) == sum_negative(tx) ||
    count([p.value == nothing for p in tx.postings]) == 1
end

isTransaction(::Transaction) = true
isTransaction(tup) = length(tup) == 8 && (tup[3] == "*" || tup[3] == "txn")

Base.push!(tr::Transaction,p::Posting) = push!(tr.postings,p)
Base.append!(tr::Transaction,p::Vector{Posting}) = append!(tr.postings,p)

end # module
