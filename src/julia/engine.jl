using Logging

include("core.jl")
include("binance.jl")

struct ExchangeSymbol
    name::String
    asset1::String
    asset2::String
end

struct SymbolPrice
    symbol::ExchangeSymbol
    ask::Float64
    bid::Float64
    timestamp::DateTime
end

struct Operation
    order::Order
    quantity::Float64
    commission::Float64
    commission_asset::String
end

struct Balance
    asset::String
    free::Float64
    locked::Float64
    timestamp::DateTime
end

struct ArbitrageOperation
    expected_arbitrage::Arbitrage
    real_arbitrage::Arbitrage
    pre_balance::Vector{Balance}
    post_balance::Vector{Balance}
    operations::Vector{Operation}
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
    @info "Getting symbols using the assets."
    symbols_matrix = bapi_symbols()
    valid_symbols = [ExchangeSymbol(x[1],x[2],x[3]) for x in symbols_matrix if x[2] in assets && x[3] in assets]
    return valid_symbols
end

function update_prices_channel_loop!(prices_channel::Channel, symbol::ExchangeSymbol)
    @debug "Starting " * symbol.name * " prices loop."
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
            @warn "Stoping " * symbol.name * " prices loop.", err
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
            @warn "Stoping update symbol dict sub-task.", err
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

function get_currency_matrix(engine::ArbitrageEngine, max_elapsed::Millisecond)
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

function analyse_arbitrage_operation(arbitrage_operation::ArbitrageOperation)
    @debug "Performing arbitrage analysis."
    # Check real balance and return comparison
    expected = arbitrage_operation.expected_arbitrage
    real = arbitrage_operation.real_arbitrage
    # TODO
end

function make_arbitrage(arbitrage::Arbitrage, test::Bool = true)
    # Perform the BAPI calls and return a real_arbitrage, operations when orders finish

end

function check_arbitrage!(arbitrage::Any)
    # Check if anything strange in arbitrage
    if isnothing(arbitrage)
        return nothing
    end

    # if any of the operations values are 1
    for order in arbitrage.orders
        if order.price == 1
            @debug "ARBITRAGE CHECK FAILED: Computed Arbitraged contains orders with price=1", arbitrage
            return nothing
        end
    end

    return arbitrage
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

function start_engine(valid_assets::Vector{String})
    @info "Starting engine. Assets: ", valid_assets
    symbols_list = get_symbols_by_assets(valid_assets)
    symbols_dict = init_symbols_dict(symbols_list)
    prices_channel = Channel()

    @info "Starting prices sub-tasks."
    loop_tasks = []
    for sym in symbols_list
        push!(loop_tasks, @async update_prices_channel_loop!(prices_channel, sym))
    end
    @info "Starting update symbol dict sub-task."
    dict_task = @async update_symbols_dict!(symbols_dict, prices_channel)

    return ArbitrageEngine(loop_tasks, dict_task, prices_channel, symbols_dict)
end

function compute_fees(arbitrage::Arbitrage, order_fee::Float64)
    type = arbitrage.type

    if type=="DIRECT"
        return order_fee*2
    elseif type=="TRIANGULAR ROW"
        return order_fee*3
    elseif type=="TRIANGULAR COLUMN"
        return order_fee*3
    elseif type=="CUADRANGULAR"
        return order_fee*4
    else
        throw(ErrorException("Arbitrage type unnkown: $type"))
    end
end

function iteration_sleep()
    time_to_sleep_in_seconds = 0.5 # seconds
    sleep(time_to_sleep_in_seconds)
end

function engine_read_config()
    @info "Reading engine configuration. HARDCODED"
    logging_file = "engine.debug"
    if logging_file != ""
        @info "Starting to write logs in file: ", logging_file
        io = open(logging_file, "w+")
        logger = SimpleLogger(io)
        global_logger(logger)
    end
    order_fee = 0.00075 # TODO check if this value match the calculated fees
    security_profit = 0.001 # 0.1%
    order_maxage = 500 # milliseconds
    valid_assets = ["BTC","ETH","XRP","DOGE","ADA","BNB","EUR","USDT"]
    return order_fee, security_profit, order_maxage, valid_assets, io
end

function main()
    order_fee, security_profit, order_maxage, valid_assets, io = engine_read_config()
    bapi_read_config()
    engine = start_engine(valid_assets)

    last_balance = get_balances()
    @info "Starting arbitrage:"
    try 
        while true
            # the next two lines are 357.89 times faster here than in python
            currency_matrix, assets = get_currency_matrix(engine, Millisecond(order_maxage))
            if length(currency_matrix) > 2
                detected_arbitrage = check_arbitrage!(arbitrage(currency_matrix, assets))
                if isnothing(detected_arbitrage)
                    @debug currency_matrix, assets
                    iteration_sleep()
                    continue
                end
                arbitrage_fees = compute_fees(detected_arbitrage, order_fee)
                @debug "Arbitrage detected. ", detected_arbitrage, currency_matrix
                iteration_sleep()
                continue

                if aer - arbitrage_fees >= security_profit
                    #real_arbitrage, operations = make_arbitrage(detected_arbitrage)
                    new_balance = get_balances()
                    arbitrage_operation = ArbitrageOperation(detected_arbitrage, real_arbitrage, last_balance, new_balance, operations)
                    analysis = analyse_arbitrage_operation(arbitrage_operation)
                    last_balance = new_balance
                    @debug analysis
                else
                    @info "aer - arbitrage_fees >= security_profit -> " * string(aer) * "-" * string(arbitrage_fees) * ">=" * string(security_profit)
                    @debug detected_arbitrage
                end
            else
                iteration_sleep()
                continue
            end
        end
    catch err
        @warn "Error on main loop. Stoping.", err
        close(io)
        return engine
    end
end
