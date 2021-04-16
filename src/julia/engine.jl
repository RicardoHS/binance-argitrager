include("core.jl")
include("binance.jl")

struct Symbol
    name::String
    asset1::String
    asset2::String
end

struct SymbolPrice
    symbol::Symbol
    ask::Float64
    bid::Float64
    datetime::DateTime
end

struct ArbitrageEngine
    loop_price_tasks::Vector{Task}
    dict_task::Task
    price_channel::Channel
    symbol_dict::Dict{String, SymbolPrice}
end

function compute_prices(orderbook)
    asks = orderbook.asks
    ask_price = mean_weighted(asks[:,1], asks[:,2])
    bids = orderbook.bids
    bid_price = mean_weighted(bids[:,1], bids[:,2])
    return ask_price, bid_price
end

function get_symbols_by_assets(assets::Vector{String})
    symbols_matrix = bapi_symbols()
    valid_symbols = [Symbol(x[1],x[2],x[3]) for x in symbols_matrix if x[2] in assets && x[3] in assets]
    return valid_symbols
end

function update_prices_channel_loop!(prices_channel::Channel, symbol::Symbol)
    while true
        try
            bapi_res = bapi_get_orderbook(symbol.name)

            if bapi_res.status != 200
                status = bapi_res.status
                throw(BAPIResponseException(status, bapi_res))
            end

            ask, bid = compute_prices(bapi_res.response)
            put!(prices_channel, SymbolPrice(symbol, ask, bid, bapi_res.timestamp))
        catch err
            isa(err, InterruptException) || rethrow(err)
            break
        end
    end
end

function update_symbols_dict!(symbols_dict::Dict{String, SymbolPrice}, prices_channel::Channel)
    for sym_price in prices_channel
        try
            symbols_dict[sym_price.symbol.name] = sym_price
        catch err
            isa(err, InterruptException) || rethrow(err)
            break
        end
    end
end

function init_symbols_dict(symbols_list)
    time_now = now()
    return Dict{String, SymbolPrice}([[s.name, SymbolPrice(s, 0, 0, time_now)] for s in symbols_list])
end

function stop_task(task::Task)
    schedule(task, InterruptException(), error=true)
end

function get_currency_matrix(engine::ArbitrageEngine, max_elapsed::Millisecond)
    valid_symbols_mask = [now() - x[2].datetime for x in engine.symbol_dict] .< max_elapsed
    valid_symbols_keys = collect(keys(engine.symbol_dict))[valid_symbols_mask]
    
    valid_assets = Set()
    for key in valid_symbols_keys
        push!(valid_assets, engine.symbol_dict[key].symbol.asset1)
        push!(valid_assets, engine.symbol_dict[key].symbol.asset2)
    end
    valid_assets = collect(String, valid_assets)

    n = length(valid_assets)
    currency_matrix = ones(n,n)

    for key in valid_symbols_keys
        ask = engine.symbol_dict[key].ask
        bid = engine.symbol_dict[key].bid
        asset1 = engine.symbol_dict[key].symbol.asset1
        asset2 = engine.symbol_dict[key].symbol.asset2
        asset1_pos = findfirst(isequal(asset1), valid_assets)
        asset2_pos = findfirst(isequal(asset2), valid_assets)
        currency_matrix[asset1_pos, asset2_pos] = bid
        currency_matrix[asset2_pos, asset1_pos] = 1/ask
    end

    return currency_matrix, valid_assets
end

function start_engine(valid_assets::Vector{String} = ["empty"])
    valid_assets = ["BTC","ETH","LTC","DOGE","ADA","BNB","EUR","USDT"]
    symbols_list = get_symbols_by_assets(valid_assets)
    symbols_dict = init_symbols_dict(symbols_list)
    prices_channel = Channel()

    loop_tasks = []
    for sym in symbols_list
        push!(loop_tasks, @async update_prices_channel_loop!(prices_channel, sym))
    end
    dict_task = @async update_symbols_dict!(symbols_dict, prices_channel)

    return ArbitrageEngine(loop_tasks, dict_task, prices_channel, symbols_dict)
end

# arbitrage(get_currency_matrix(engine, Millisecond(100000000))...)
