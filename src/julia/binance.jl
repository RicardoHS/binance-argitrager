using HTTP
using StructTypes
using JSON3
using Dates
using Printf
using Nettle #for hashing algorithms

api_config = Dict{String, String}()

struct BinanceAPIOrderBookJSON
    lastUpdateId::Int64
    bids::Vector{Vector{String}}
    asks::Vector{Vector{String}}
end
StructTypes.StructType(::Type{BinanceAPIOrderBookJSON}) = StructTypes.Struct()

struct BinanceAPIOrderBook
    symbol::String
    lastUpdateId::Int64
    bids::Matrix{Float64}
    asks::Matrix{Float64}
end

struct BinanceAPIResponse
    url::String
    status::Integer
    response::Any
    timestamp::DateTime
    elapsed::Millisecond
    used_w::Integer
end

struct BAPIResponseException <: Exception
    status::Integer
    response::BinanceAPIResponse
end

function bapi_read_config()
    config_file_path = pwd() * "/src/julia/" * "./config.txt"
    @info "Reading Binance API configuration: " config_file_path
    lines = readlines(config_file_path)
    config_dict = Dict{String, String}()
    for line in lines
        k, v = split(line, "=")
        config_dict[lowercase(k)] = v
    end
    global api_config = config_dict
end

function bapi_client_clock()
    """
    Get current local/client time in milliseconds::Int64
    """
    return round(Int64, time()*1000)
end

function bapi_endpoint()
    api_endpoint = "api" #api1 api2 api3
    api_version = "v3"
    url = "https://$api_endpoint.binance.com/api/$api_version/"
    return url
end

function bapi_get(url::String, headers::Vector{Any}=[])
    time_i = now()
    request = HTTP.request("GET", url, headers)
    time_e = now()
    elapsed = time_e - time_i
    timestamp = time_e - div(elapsed,2)
    @info "GET $url"
    return request, timestamp, elapsed
end

function bapi_post(url::String, headers::Vector{Any}=[])
    time_i = now()
    request = HTTP.request("POST", url, headers)
    time_e = now()
    elapsed = time_e - time_i
    timestamp = time_e - div(elapsed,2)
    @info "POST $url"
    return request, timestamp, elapsed
end

function bapi_map_orderbook(symbol, orderbook_json)
    asks_v = map(x -> parse.(Float64, x), orderbook_json.asks)
    asks = transpose(hcat(asks_v...))
    bids_v = map(x -> parse.(Float64, x), orderbook_json.bids)
    bids = transpose(hcat(bids_v...))
    return BinanceAPIOrderBook(symbol, orderbook_json.lastUpdateId, bids, asks)
end

function bapi_get_price(symbol::String)
    uri = "ticker/price?symbol=$symbol"
    url = bapi_endpoint() * uri
    request, timestamp, elapsed = bapi_get(url)
    parsed_json = JSON3.read(request.body)
    headers = Dict(request.headers)
    return BinanceAPIResponse(url, request.status, parsed_json, timestamp, elapsed, parse(Int32, headers["x-mbx-used-weight"]))
end

function bapi_get_orderbook(symbol::String, depth::Integer = 20)
    uri = "depth?symbol=$symbol&limit=$depth"
    url = bapi_endpoint() * uri
    request, timestamp, elapsed = bapi_get(url)
    parsed_json = JSON3.read(request.body, BinanceAPIOrderBookJSON)
    response = bapi_map_orderbook(symbol, parsed_json)
    headers = Dict(request.headers)
    return BinanceAPIResponse(url, request.status, response, timestamp, elapsed, parse(Int32, headers["x-mbx-used-weight"]))
end

function bapi_get_exchangeinfo()
    uri = "exchangeInfo"
    url = bapi_endpoint() * uri
    request, time = bapi_get(url)
    return JSON3.read(request.body)
end

function bapi_get_filters(symbols::Vector{String})
    exchange_info = bapi_get_exchangeinfo()

    filters = []
    for sym in exchange_info["symbols"]
        if !(sym["symbol"] in symbols)
            continue
        end
        push!(filters, Dict("symbol"=>sym["symbol"], "asset1"=> sym["baseAsset"], 
                            "asset2"=> sym["quoteAsset"], "filters"=>sym["filters"]) )
    end

    return filters
end

function bapi_symbols()
    request = bapi_get_exchangeinfo()
    symbols = [[d["symbol"], d["baseAsset"], d["quoteAsset"]] for d in request["symbols"] if d["status"]=="TRADING"]
    return symbols
end

function bapi_keys()
    public_key = api_config["public_key"]
    secret_key = api_config["secret_key"]
    return public_key, secret_key
end

function bapi_header_userinfo!(header::Vector{Any})
    public_key, _ = bapi_keys()
    user_api_key = ("X-MBX-APIKEY", public_key)
    push!(header, user_api_key)
    return header
end

function bapi_params_signature!(params)
    public_key, secret_key = bapi_keys()
    signature = hexdigest("sha256", secret_key, params)
    return params * "&signature=" * signature
end

function bapi_get_accountinfo()
    uri = "account"

    timestamp = bapi_client_clock()
    params = "timestamp=$timestamp"
    params = bapi_params_signature!(params)
    header = bapi_header_userinfo!([])

    url = bapi_endpoint() * uri * "?" * params
    request, timestamp, elapsed = bapi_get(url, header)
    parsed_json = JSON3.read(request.body)
    return parsed_json, timestamp, elapsed
end

function bapi_balances()
    """
    return all crypto assets balances where value different from 0
    """
    account_info, timestamp, _ = bapi_get_accountinfo()
    return [x for x in account_info.balances if parse(Float64, x.free) != 0], timestamp
end

function bapi_ws_subscribe_orderbook(symbol::String, channel::Channel, depth::Int=10)
    """
    Subscribe to an symbol order book and push updates to channel
    """
    @debug "Starting websocket to fetch " * symbol * " orderbook."
    try
        HTTP.WebSockets.open("wss://stream.binance.com:9443/ws/$symbol@depth$depth@100ms") do ws
            while !eof(ws)
                res = JSON3.read(readavailable(ws), BinanceAPIOrderBookJSON)
                put!(channel, (bapi_map_orderbook(symbol, res), now()))
            end
        end
    catch err
        @warn "Stoping websocket orderbook $symbol." err
        isa(err, InterruptException) || rethrow(err)
        return 1
    end
end

function bapi_ws_subscribe_streams(url::String, channel::Channel)
    """
    Subscribe to multiple streams order book and push updates to channel
    """
    @debug "Starting websocket to fetch orderbook on stream." url
    try
        HTTP.WebSockets.open(url) do ws
            while !eof(ws)
                res = JSON3.read(readavailable(ws))
                symbol = uppercase(split(res["stream"],"@")[1])
                put!(channel, (bapi_map_orderbook(symbol, res["data"]), now()))
            end
        end
    catch err
        @warn "Stoping websocket orderbook stream." err
        isa(err, InterruptException) || rethrow(err)
        return 1
    end
end

function bapi_post_order(symbol::String, side::String, quantity::Float64, recvWindow::Integer=50, test::Bool=true)
    if test
        uri = "order/test"
    else
        uri = "order/test"
    end
    type = "MARKET"
    quantity_str = @sprintf("%.8f",quantity)

    timestamp = bapi_client_clock()
    params = "type=$type&symbol=$symbol&side=$side&quantity=$quantity_str&recvWindow=$recvWindow&timestamp=$timestamp"
    params = bapi_params_signature!(params)
    header = bapi_header_userinfo!([])

    url = bapi_endpoint() * uri * "?" * params
    request, timestamp, elapsed = bapi_post(url, header)
    parsed_json = JSON3.read(request.body)

    return parsed_json, elapsed
end
