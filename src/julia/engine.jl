using Logging
using Statistics
using ConfParser

include("core.jl")
include("binance.jl")

mutable struct Timings
    # Computation
    c_main_loop::Float64
    c_arbitrage::Float64
end

struct SymbolPrice
    symbol::ExchangeSymbol
    ask::Float64
    bid::Float64
    timestamp::DateTime
end

struct Fill
    price::Float64
    quantity::Float64
    commission::Float64
    commission_asset::String
end

struct Order
    type::String
    asset1::String
    asset2::String
    price::Float64
end

struct Operation
    order::Order
    fills::Vector{Fill}
end

struct Balance
    asset::String
    free::Float64
    locked::Float64
    timestamp::DateTime
end

struct ArbitrageOperation
    expected_arbitrage::ArbitrageIterative
    pre_balance::Vector{Balance}
    post_balance::Vector{Balance}
    operations::Vector{Operation}
end

struct ArbitrageEngine
    loop_price_tasks::Vector{Task}
    dict_task::Task
    price_channel::Channel
    symbol_dict::Dict{String, SymbolPrice}
    safe_amounts::Dict{String, Float64}
    filters::Dict{String, Any}
    config::Dict{Any, Any}
end

function incremental_subtract(value::Float64, array::Vector{Float64})
    remaining = value
    subtract_array = Float64[]
    for e in array
        push!(subtract_array, max(0, e-remaining))
        remaining = max(0,remaining-e)
    end
    subtract_array
end

function compute_prices(orderbook, quantity::Float64)
    asks = orderbook.asks
    asks_weights = incremental_subtract(quantity, asks[:,2]) - asks[:,2]
    ask_price = mean_weighted(asks[:,1], asks_weights)
    bids = orderbook.bids
    bids_weights = incremental_subtract(quantity, bids[:,2]) - bids[:,2]
    bid_price = mean_weighted(bids[:,1], bids_weights)
    return ask_price, bid_price
end

function get_symbols(assets::Vector{String})
    @info "Getting symbols using the assets."
    symbols_matrix = bapi_symbols()
    valid_symbols = [ExchangeSymbol(x[1],x[2],x[3]) for x in symbols_matrix if x[2] in assets && x[3] in assets]
    return valid_symbols
end

function update_symbols_dict!(symbols_dict::Dict{String, SymbolPrice}, orderbook_channel::Channel, safe_quantities::Dict{String, Float64})
    for item in orderbook_channel
        try
            orderbook, timestamp = item
            ask, bid = compute_prices(orderbook, safe_quantities[orderbook.symbol])
            current_symbol = symbols_dict[uppercase(orderbook.symbol)]
            sym_price = SymbolPrice(current_symbol.symbol, ask, bid, timestamp)
            symbols_dict[sym_price.symbol.name] = sym_price
        catch err
            @warn "Stoping update symbol dict sub-task." err
            isa(err, InterruptException) || rethrow(err)
            break
        end
    end
end

function init_symbols_dict(symbols_list)
    @debug "Initiating the symbols dictionary"
    time_now = now()
    return Dict{String, SymbolPrice}([[s.name, SymbolPrice(s, 0, 0, time_now)] for s in symbols_list])
end

function stop_task(task::Task)
    schedule(task, InterruptException(), error=true)
end

function get_buysell_matrix(engine::ArbitrageEngine, max_elapsed::Millisecond)
    @debug "Getting currency matrix."
    valid_symbols_mask = [now() - x[2].timestamp for x in engine.symbol_dict] .< max_elapsed
    valid_symbols_keys = collect(keys(engine.symbol_dict))[valid_symbols_mask]
    
    valid_assets = Set()
    for key in valid_symbols_keys
        push!(valid_assets, engine.symbol_dict[key].symbol.asset1)
        push!(valid_assets, engine.symbol_dict[key].symbol.asset2)
    end
    valid_assets = collect(String, valid_assets)

    n = length(valid_assets)
    buysell_matrix = zeros(n,n)

    for key in valid_symbols_keys
        ask = engine.symbol_dict[key].ask
        bid = engine.symbol_dict[key].bid
        asset1 = engine.symbol_dict[key].symbol.asset1
        asset2 = engine.symbol_dict[key].symbol.asset2
        asset1_pos = findfirst(isequal(asset1), valid_assets)
        asset2_pos = findfirst(isequal(asset2), valid_assets)
        buysell_matrix[asset1_pos, asset2_pos] = bid
        buysell_matrix[asset2_pos, asset1_pos] = ask
    end

    return buysell_matrix, valid_assets
end

function analyse_arbitrage_operation(arbitrage_operation::ArbitrageOperation)
    @debug "Performing arbitrage analysis."
    # Check real balance and return comparison
    post_balance_dict = Dict([(x.asset,x) for x in arbitrage_operation.post_balance])

    for pre_bal in arbitrage_operation.pre_balance
        asset = pre_bal.asset
        new_free = post_balance_dict[asset].free - pre_bal.free
        new_locked = post_balance_dict[asset].locked - pre_bal.locked
        new_aer = new_free/pre_bal.free
        @info asset new_free new_locked new_aer
    end
end

function make_arbitrage(arbitrage::ArbitrageIterative, engine::ArbitrageEngine, test::Bool = true)
    # Perform the BAPI calls and return operations when orders finish
    recvWindow = engine.config["RECVWINDOW"]
    tasks = Task[]
    for order in arbitrage.orders
        min_qty = parse(Float64, engine.filters[order.symbol]["LOT_SIZE"]["minQty"])
        round_to = Integer(abs(floor(log10(min_qty))))
        quantity = max(min_qty, round(order.quantity, digits=round_to))
        push!(tasks, @async bapi_post_order(order.symbol, order.type, quantity, recvWindow, test))
    end

    operations = Operation[]
    for (i, t) in enumerate(tasks)
        wait(t)
        if test
            continue
        end
        response, elapsed = t.result
        fills = [Fill(parse(Float64, x["price"]), 
                      parse(Float64, x["qty"]),
                      parse(Float64, x["commission"]),
                      x["commissionAsset"]) for x in response["fills"]]
        op = Operation(arbitrage.orders[i], fills)
        push!(operations, op)
    end

    return operations
end

function get_balances()
    @info "Getting assets balance."
    balances_raw, timestamp = bapi_balances()
    balances = Balance[]
    for bal in balances_raw
        asset = bal["asset"]
        free = parse(Float64, bal["free"])
        locked = parse(Float64, bal["locked"])
        push!(balances, Balance(asset, free, locked, timestamp))
    end
    return balances
end

function get_safe_amounts(filters_dict, symbols::Vector{ExchangeSymbol}, min_notional_multiplier::Float64, base_currency_asset::String)::Dict{String, Float64}
    max_safe_amounts = Dict()
    prices = Dict()
    for s in symbols
        res = bapi_get_price(s.name)
        price = parse(Float64, res.response["price"])
        prices[s.name] = price

        f = filters_dict[s.name]
        lot_stepsize = parse(Float64, f["LOT_SIZE"]["stepSize"])
        min_notional = parse(Float64, f["MIN_NOTIONAL"]["minNotional"])
        min_qty = min_notional / price
        min_qty_rounded = ceil(min_qty, digits=Integer(abs(floor(log10(lot_stepsize)))))

        if s.asset1 in keys(max_safe_amounts)
            max_safe_amounts[s.asset1] = max(min_qty_rounded, max_safe_amounts[s.asset1])
        else
            max_safe_amounts[s.asset1] = min_qty_rounded
        end
    end

    safe_amounts = Dict{String, Float64}()
    for s in symbols
        final_safe_amount = max_safe_amounts[s.asset1]*min_notional_multiplier
        safe_amounts[s.name] = final_safe_amount

        if s.asset1 != base_currency_asset
            @info "Safe amount for symbol $(s.name) => $final_safe_amount ($(round(final_safe_amount*prices[s.asset1*base_currency_asset], digits=2)) $base_currency_asset)"
        end
    end

    return safe_amounts
end

function get_filters(symbols::Vector{ExchangeSymbol})
    filters = bapi_get_filters([x.name for x in symbols])
    filters_dict = Dict([(x["symbol"],Dict([(f["filterType"],f) for f in x["filters"]])) for x in filters])
    return filters_dict
end

function start_engine(config::Dict{Any, Any})
    base_currency_asset = config["BASE_CURRENCY_ASSET"]
    symbols_list = get_symbols(config["SYMBOLS"])
    filters_dict = get_filters(symbols_list)
    safe_amounts = get_safe_amounts(filters_dict, symbols_list, config["MIN_NOTIONAL_MULTIPLIER"], base_currency_asset)

    ##################

    last_balance = get_balances()

    if length(symbols_list) <= 2
        throw(ErrorException("Aborting engine start. Insufficient number of safe assets. Check logs."))
    end

    symbols_dict = init_symbols_dict(symbols_list)
    @info "Starting engine."

    @info "Starting prices sub-tasks."
    orderbook_channel = Channel{Tuple{BinanceAPIOrderBook, DateTime}}(length(symbols_list)*100)
    loop_tasks = [@async bapi_ws_subscribe_streams(get_full_streams_url(symbols_list), orderbook_channel)]
    
    @info "Starting update symbol dict sub-task."
    dict_task = @async update_symbols_dict!(symbols_dict, orderbook_channel, safe_amounts)

    return ArbitrageEngine(loop_tasks, dict_task, orderbook_channel, symbols_dict, safe_amounts, filters_dict, config), last_balance
end

function engine_read_config(logging_file::String)
    if logging_file != ""
        @info "Starting to write logs in file: " logging_file
        io = open(logging_file, "w+")
        logger = SimpleLogger(io)
        global_logger(logger)
    else
        io = Channel()
    end

    config = Dict()
    config_file_path = pwd() * "/src/julia/" * "./config.ini"
    @info "Reading engine configuration." config_file_path
    conf = ConfParse(config_file_path)
    parse_conf!(conf)

    config["ORDER_FEE"] = parse(Float64, retrieve(conf, "engine", "ORDER_FEE")) # 0.075%
    config["SECURITY_PROFIT"] = parse(Float64, retrieve(conf, "engine", "SECURITY_PROFIT")) # 0.1%
    config["ORDER_MAXAGE"] = parse(Int64, retrieve(conf, "engine", "ORDER_MAXAGE")) # milliseconds
    config["RECVWINDOW"] = parse(Int64, retrieve(conf, "engine", "RECVWINDOW")) # milliseconds
    config["io"] = io

    config["MIN_NOTIONAL_MULTIPLIER"] = parse(Float64, retrieve(conf, "engine", "MIN_NOTIONAL_MULTIPLIER"))
    config["BASE_CURRENCY_ASSET"] = retrieve(conf, "engine", "BASE_CURRENCY_ASSET")
    config["SYMBOLS"] = retrieve(conf, "engine", "SYMBOLS")

    return config
end

function iteration_sleep()
    time_to_sleep_in_seconds = 0.05 # seconds
    sleep(time_to_sleep_in_seconds)
end

function time_microsec()
    time_ns()*1e-3
end

function main(test::Bool=true)
    logging_file = "" # "engine.debug"
    config = engine_read_config(logging_file)
    bapi_read_config()

    order_fee = config["ORDER_FEE"]
    security_profit = config["SECURITY_PROFIT"]
    engine, last_balance= start_engine(config)

    timings = Timings(0.0,0.0)
    @info "Starting arbitrage:"
    try 
        while true
            timings.c_main_loop = time_microsec()
            buysell_matrix, assets = get_buysell_matrix(engine, Millisecond(config["ORDER_MAXAGE"]))
            symbols = [x.symbol for x in collect(values(engine.symbol_dict)) if x.symbol.asset1 in assets && x.symbol.asset2 in assets]
            if length(symbols) >= 3
                detected_arbitrage = arbitrage_iterative(buysell_matrix, assets, symbols, engine.safe_amounts)
                timings.c_arbitrage = time_microsec()

                if !isnothing(detected_arbitrage)
                    aer = detected_arbitrage.aer
                    arbitrage_fees = order_fee * 3

                    if aer - arbitrage_fees >= security_profit
                        @info string("Arbitrage detected. Expected AER=",round((aer - arbitrage_fees)*100, digits=2),"%") detected_arbitrage
                        
                        operations = make_arbitrage(detected_arbitrage, engine, test)
                        new_balance = get_balances()
                        arbitrage_operation = ArbitrageOperation(detected_arbitrage, last_balance, new_balance, operations)
                        analyse_arbitrage_operation(arbitrage_operation)
                        last_balance = new_balance
                        break
                    else
                        @info "Arbitrage insecure." aer arbitrage_fees aer-arbitrage_fees security_profit aer - arbitrage_fees >= security_profit
                    end
                end                
            end
            compute_times(timings, engine)
            iteration_sleep()
        end
    catch err
        @warn "Error on main loop. Stoping." err
        close(config["io"])
        rethrow(err)
        return engine
    end
end

function compute_times(timings::Timings, engine::ArbitrageEngine)
    n = time_microsec()

    #price_loop deltas
    prices_deltas = [Dates.value.(now()-x[2].timestamp) for x in engine.symbol_dict]

    times_str = "Times: \n - Computation:\n"
    times_str = times_str * string("\t\tMain Loop: ", round(n-timings.c_main_loop, digits=2), " μs\n")
    times_str = times_str * string("\t\tArbitrage: ", round(timings.c_arbitrage-timings.c_main_loop, digits=2), " μs\n")

    times_str = times_str * "\n - Network:\n"
    times_str = times_str * string("\t\tPrices mean: ", round(mean(prices_deltas), digits=2), " ms\n")
    times_str = times_str * string("\t\tPrices std: ", round(std(prices_deltas), digits=2), " ms\n")
    times_str = times_str * string("\t\tPrices min: ", minimum(prices_deltas), " ms\n")
    times_str = times_str * string("\t\tPrices max: ", maximum(prices_deltas), " ms\n")

    @info times_str
end


function get_full_streams_url(symbols_list::Vector{ExchangeSymbol})
    full_string = "wss://stream.binance.com:9443/stream?streams="
    for s in symbols_list
        full_string = full_string * lowercase(s.name) * "@depth10@100ms/"
    end
    return String(chop(full_string)) #remove last char from string
end
