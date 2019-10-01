module Beancount

using PyCall
using Decimals
using Dates
using Parameters
using Combinatorics

import Base.==

const DEFAULT_CURRENCY = "EUR"
const aDict = Union{Nothing,Dict{Any,Any}}
const SN = Union{Nothing,String}
const DN = Union{Nothing,Decimal}

function __init__()
    global loader, load_file
    loader = pyimport("beancount.loader")
    load_file = loader.load_file
end

export Posting, Transaction, issimilar, balances, isTransaction, from_python, txn, pad

Base.homedir(path::AbstractString...) = joinpath(homedir(),path...)

struct Posting
    location::aDict
    account::String
    value::DN
    currency::SN
    comment::SN
    Posting(;account::String,value::Union{Nothing,Number}=nothing,currency::SN=nothing,comment::SN=nothing,location::aDict=nothing) = new(
        location,account,value == nothing ? value : convert(Decimal,value),currency,comment)
end

function ==(pA::Posting,pB::Posting)
    pA.account == pB.account && pA.value == pB.value && pA.currency == pB.currency
end

function ==(pA::Vector{Posting},pB::Vector{Posting})
    for a in permutations(pA)
        if all((a[i] == pB[i] for i in 1:length(pB)))
            return true
        end
        println(a)
    end
    return false
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

abstract type AbstractTransactionType end

struct txn <: AbstractTransactionType end
struct pad <: AbstractTransactionType end

const Collection1D{T} = Union{Vector{T},Set{T},NTuple{N,T}} where N

struct Transaction{typ<:AbstractTransactionType}
    location::aDict
    date::Date
    payee::SN
    description::String
    tags::Set{String}
    links::Set{String}
    postings::Vector{Posting}
    Transaction{typ}(;date::Date,payee::SN=nothing,description::String,
                     tags::Collection1D{String}=Set{String}(),links::Collection1D{String}=Set{String}(),postings::Vector{Posting}=Posting[],location::aDict=nothing) where typ <: AbstractTransactionType = new{typ}(
                         nothing,date,clean_text(payee),clean_text(description),
                         tags isa Set ? tags : Set(tags),
                         links isa Set ? links : Set(links),postings)
end

function ==(txA::Transaction{T},txB::Transaction{T}) where T <: AbstractTransactionType
    txA.date        == txA.date &&
    txA.payee       == txA.payee &&
    txA.description == txA.description &&
    txA.tags        == txA.tags &&
    txA.links       == txA.links &&
    txA.postings    == txA.postings
end

clean_text(::Nothing) = nothing

function clean_text(st::String)
    reduce(replace,[
        "\n" => " ",
        "\t" => " ",
        r" {2,}" => " ",
    ],init=st)
end

function from_python_posting(tup::NTuple{6,Any})
    Posting(
        location = tup[end],
        account=tup[1],
        value=convert(Decimal,tup[2][1]),
        currency=tup[2][2])
end

from_python(::Any) = nothing

function from_python(entry::NTuple{8,Any}) 
    if entry[3] in ("*","txn")
        typ = txn
    elseif entry[3] == "P"
        typ = pad
    else
        error("Unknown transaction type '$(entry[3])'.")
    end
    Transaction{typ}(location=entry[1],
                     date=entry[2],
                     payee=entry[4],
                     description=entry[5],
                     tags=Set(String.(entry[6])),
                     links=Set(String.(entry[7])),
                     postings=from_python_posting.(entry[8]))
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
