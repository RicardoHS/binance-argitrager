include("engine.jl")

mutable struct Timings
    # Computation
    c_main_loop::Float64
    c_arbitrage::Float64
end

function iteration_sleep()
    time_to_sleep_in_seconds = 0.05 # seconds
    sleep(time_to_sleep_in_seconds)
end

function time_microsec()
    time_ns()*1e-3
end

function compute_times(timings::Timings, symbol_dict::Dict{String, SymbolPrice})
    n = time_microsec()

    #price_loop deltas
    prices_deltas = [Dates.value.(now()-x[2].timestamp) for x in symbol_dict]

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

function main(test::Bool=true)
    logging_file = "" # "engine.debug"
    config = engine_read_config(logging_file)
    bapi_read_config()

    order_fee = config["ORDER_FEE"]
    security_profit = config["SECURITY_PROFIT"]
    order_maxage = Millisecond(config["ORDER_MAXAGE"])
    recvWindow = config["RECVWINDOW"]

    engine, last_balance= start_engine(config)

    symbol_dict = engine.symbol_dict

    timings = Timings(0.0,0.0)
    @info "Starting arbitrage:"
    try 
        while true
            timings.c_main_loop = time_microsec()
            buysell_matrix, assets, quantities = get_buysell_matrix(symbol_dict, order_maxage)
            symbols = [x for x in collect(values(symbol_dict)) if x.symbol.asset1 in assets && x.symbol.asset2 in assets]
            if length(symbols) >= 3
                detected_arbitrage = arbitrage_iterative(buysell_matrix, assets, symbols, quantities)
                timings.c_arbitrage = time_microsec()

                if !isnothing(detected_arbitrage)
                    aer = detected_arbitrage.aer
                    arbitrage_fees = order_fee * 3

                    if aer - arbitrage_fees >= security_profit
                        @info string("Arbitrage detected. Expected AER=",round((aer - arbitrage_fees)*100, digits=2),"%") detected_arbitrage
                        
                        operations = make_arbitrage(detected_arbitrage, recvWindow, test)
                        new_balance = get_balances()
                        arbitrage_operation = ArbitrageOperation(detected_arbitrage, last_balance, new_balance, operations)
                        analyse_arbitrage_operation(arbitrage_operation, engine)
                        last_balance = new_balance
                        bapi_test_all_endpoints()
                        break
                    else
                        @info "Arbitrage insecure." aer arbitrage_fees aer-arbitrage_fees security_profit aer - arbitrage_fees >= security_profit
                    end
                end                
            end
            compute_times(timings, symbol_dict)
            iteration_sleep()
        end
    catch err
        @warn "Error on main loop. Stoping." err
        close(config["io"])
        rethrow(err)
        return engine
    end
end

main()