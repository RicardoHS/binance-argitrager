using HTTP
using StructTypes
using JSON3
using Dates

struct BinanceAPIOrderBookJSON
    lastUpdateId::Int64
    bids::Vector{Vector{String}}
    asks::Vector{Vector{String}}
end
StructTypes.StructType(::Type{BinanceAPIOrderBookJSON}) = StructTypes.Struct()

struct BinanceAPIOrderBook
    lastUpdateId::Int64
    bids::Vector{Vector{Float64}}
    asks::Vector{Vector{Float64}}
end

struct BinanceAPIResponse
    url::String
    status::Integer
    response::Any
    elapsed::Millisecond
    used_w::Integer
end


function bapi_endpoint()
    url = "https://api.binance.com/api/v3/"
    return url
end

function bapi_get(url::String)
    time_i = now()
    request = HTTP.request("GET", url)
    time_e = now() - time_i
    return request, time_e
end

function bapi_map_orderbook(orderbook_json)
    asks = map(x -> parse.(Float64, x), orderbook_json.asks)
    bids = map(x -> parse.(Float64, x), orderbook_json.bids)
    return BinanceAPIOrderBook(orderbook_json.lastUpdateId, bids, asks)
end

function bapi_get_orderbook(symbol::String, depth::Integer = 5)
    uri = "depth?symbol=$symbol&limit=$depth"
    url = bapi_endpoint() * uri
    request, time_e = bapi_get(url)
    parsed_json = JSON3.read(request.body, BinanceAPIOrderBookJSON)
    response = bapi_map_orderbook(parsed_json)
    headers = Dict(request.headers)
    return BinanceAPIResponse(url, request.status, response, time_e, parse(Int32, headers["x-mbx-used-weight"]))
end

function bapi_get_exchangeinfo()
    uri = "exchangeInfo"
    url = bapi_endpoint() * uri
    request, time = bapi_get(url)
    return JSON3.read(request.body)
end

function bapi_symbols()
    request = bapi_get_exchangeinfo()
    symbols = [[d["symbol"], d["baseAsset"], d["quoteAsset"]] for d in json["symbols"] if d["status"]=="TRADING"]
    return symbols
end
