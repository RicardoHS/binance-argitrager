using Logging
using Statistics
using ConfParser

include("core.jl")
include("binance.jl")

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

struct Operation
    order::Order
    fills::Vector{Fill}
    elapsed::Millisecond
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
    symbols::Vector{ExchangeSymbol}
    safe_amounts::Dict{String, Float64}
    prices_to_main_asset::Dict{String, Float64}
    config::Dict{Any, Any}
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
    config["MAIN_ASSET"] = retrieve(conf, "engine", "MAIN_ASSET")
    config["ASSETS"] = retrieve(conf, "engine", "ASSETS")

    return config
end

function stop_task(task::Task)
    schedule(task, InterruptException(), error=true)
end

function get_full_streams_url(symbols_list::Vector{ExchangeSymbol})
    full_string = "wss://stream.binance.com:9443/stream?streams="
    for s in symbols_list
        full_string = full_string * lowercase(s.name) * "@depth10@100ms/"
    end
    return String(chop(full_string)) #remove last char from string
end

function get_symbols(assets::Vector{String})
    @info "Getting symbols using the assets."
    symbols_matrix = bapi_symbols()
    valid_symbols = [(x[1],x[2],x[3]) for x in symbols_matrix if x[2] in assets && x[3] in assets]

    filters = bapi_get_filters([x[1] for x in valid_symbols])
    filters_dict = Dict([(x["symbol"],Dict([(f["filterType"],f) for f in x["filters"]])) for x in filters])

    valid_symbols = [ExchangeSymbol(x[1],x[2],x[3], filters_dict[x[1]]) for x in symbols_matrix if x[2] in assets && x[3] in assets]
    return valid_symbols
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

function get_prices(symbols::Vector{ExchangeSymbol})
    prices = Dict()
    for s in symbols
        res = bapi_get_price(s.name)
        price = parse(Float64, res.response["price"])
        prices[s.name] = price
    end
    return prices
end

function compute_prices(asks::Matrix{Float64}, bids::Matrix{Float64}, quantity::Float64)
    asks_weights = incremental_subtract(quantity, asks[:,2]) - asks[:,2]
    ask_price = mean_weighted(asks[:,1], asks_weights)

    bids_weights = incremental_subtract(quantity, bids[:,2]) - bids[:,2]
    bid_price = mean_weighted(bids[:,1], bids_weights)
    
    return ask_price, bid_price
end

function init_symbols_dict(symbols_list)
    @debug "Initiating the symbols dictionary"
    time_now = now()
    return Dict{String, SymbolPrice}([[s.name, SymbolPrice(s, 0, 0, time_now)] for s in symbols_list])
end

function update_symbols_dict!(symbols_dict::Dict{String, SymbolPrice}, orderbook_channel::Channel, safe_quantities::Dict{String, Float64})
    for item in orderbook_channel
        try
            orderbook, timestamp = item
            ask, bid = compute_prices(orderbook.asks, orderbook.bids, safe_quantities[orderbook.symbol])
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

function get_buysell_matrix(symbol_dict::Dict{String, SymbolPrice}, max_elapsed::Millisecond)
    @debug "Getting currency matrix."
    valid_symbols_mask = [now() - x[2].timestamp for x in symbol_dict] .< max_elapsed
    valid_symbols = collect(keys(symbol_dict))[valid_symbols_mask]
    
    valid_assets = Set()
    for sym_name in valid_symbols
        push!(valid_assets, symbol_dict[sym_name].symbol.asset1)
        push!(valid_assets, symbol_dict[sym_name].symbol.asset2)
    end
    valid_assets = collect(String, valid_assets)

    n = length(valid_assets)
    buysell_matrix = zeros(n,n)

    for sym_name in valid_symbols
        ask = symbol_dict[sym_name].ask
        bid = symbol_dict[sym_name].bid
        asset1 = symbol_dict[sym_name].symbol.asset1
        asset2 = symbol_dict[sym_name].symbol.asset2
        asset1_pos = findfirst(isequal(asset1), valid_assets)
        asset2_pos = findfirst(isequal(asset2), valid_assets)
        buysell_matrix[asset1_pos, asset2_pos] = bid
        buysell_matrix[asset2_pos, asset1_pos] = ask
    end

    return buysell_matrix, valid_assets
end

function get_main_asset_pair_prices(symbols::Vector{ExchangeSymbol}, main_asset::String)::Dict{String,Float64}
    prices_to_main_asset = Dict{String,Float64}()
    prices_to_main_asset[main_asset] = 1.0

    symbols_with_mainbase = [s for s in symbols if s.asset1 == main_asset]
    symbols_with_mainquoted = [s for s in symbols if s.asset2 == main_asset]

    for s in symbols_with_mainquoted
        res = bapi_get_price(s.name)
        price = parse(Float64, res.response["price"])
        prices_to_main_asset[s.asset1] = price
    end

    for s in symbols_with_mainbase
        res = bapi_get_price(s.name)
        price = parse(Float64, res.response["price"])
        prices_to_main_asset[s.asset2] = get_safe_price(1/price, s)
    end

    return prices_to_main_asset
end

function get_safe_amounts(symbols::Vector{ExchangeSymbol}, min_notional_multiplier::Float64, main_asset::String)::Dict{String, Float64}
    max_safe_amounts = Dict()
    prices = get_prices(symbols)
    for s in symbols
        price = prices[s.name]
        min_qty = get_safe_minqty(price, s)

        if s.asset1 in keys(max_safe_amounts)
            max_safe_amounts[s.asset1] = max(min_qty, max_safe_amounts[s.asset1])
        else
            max_safe_amounts[s.asset1] = min_qty
        end
    end

    safe_amounts = Dict{String, Float64}()
    for s in symbols
        final_safe_amount = max_safe_amounts[s.asset1]*min_notional_multiplier
        safe_amounts[s.name] = get_safe_qty(final_safe_amount, s)

        if s.asset1 != main_asset
            @info "Safe amount for symbol $(s.name) => $(round(final_safe_amount, digits=8)) ($(round(final_safe_amount*prices[s.asset1*main_asset], digits=2)) $main_asset)"
        end
    end

    return safe_amounts
end

function analyse_arbitrage_operation(arbitrage_operation::ArbitrageOperation, engine::ArbitrageEngine)
    @debug "Performing arbitrage analysis."
    # Check real balance and return comparison
    post_balance_dict = Dict([(x.asset,x) for x in arbitrage_operation.post_balance if x.asset in engine.config["ASSETS"]])
    pre_balance = [x for x in arbitrage_operation.pre_balance if x.asset in engine.config["ASSETS"]]

    total_balance = 0
    main_asset = engine.config["MAIN_ASSET"]
    for pre_bal in pre_balance
        asset = pre_bal.asset
        diff_free_balance = round(post_balance_dict[asset].free - pre_bal.free, digits=8)
        total_balance += engine.prices_to_main_asset[asset] * diff_free_balance
        @info "$asset $(round(diff_free_balance, digits=8)) ($(diff_free_balance*engine.prices_to_main_asset[asset]) $main_asset)"
    end

    @info "Total Balance in main currency: $(round(total_balance, digits=8)) $main_asset"

    total_commission = 0
    total_fees = 0
    for op in arbitrage_operation.operations
        for fill in op.fills
            total_fees += fill.commission * engine.prices_to_main_asset[fill.commission_asset]
        end
        @info op
    end
    @info "Total commission: $(round(total_fees, digits=8)) $main_asset"
end

function make_arbitrage(arbitrage::ArbitrageIterative, recvWindow::Integer, test::Bool = true)
    # Perform the BAPI calls and return operations when orders finish
    tasks = Task[]
    for order in arbitrage.orders
        quantity = get_safe_qty(order.quantity, order.symbol)
        push!(tasks, @async bapi_post_order(order.symbol.name, order.type, quantity, recvWindow, test))
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
        op = Operation(arbitrage.orders[i], fills, elapsed)
        push!(operations, op)
    end

    return operations
end

function start_engine(config::Dict{Any, Any})
    main_asset = config["MAIN_ASSET"]
    symbols_list = get_symbols(config["ASSETS"])
    safe_amounts = get_safe_amounts(symbols_list, config["MIN_NOTIONAL_MULTIPLIER"], main_asset)
    prices_to_main_asset = get_main_asset_pair_prices(symbols_list, main_asset)

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

    return ArbitrageEngine(loop_tasks, dict_task, orderbook_channel, symbols_dict, symbols_list, safe_amounts, prices_to_main_asset, config), last_balance
end
