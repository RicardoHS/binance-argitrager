

function fulfil_filters(safe_qty::Float64, symbol::String)
    # fulfil LOT_SIZE stepSize
    f = [x for x in bapi_get_filters([symbol])[1]["filters"] if x["filterType"] == "LOT_SIZE"][1]
    value = parse(Float64, f["stepSize"])
    return round(safe_qty, digits=Integer(-floor(log10(value))))
end

function get_safe_assets_quantities()
    # Safe percentage = 1%
    balances_dict = Dict([(x.asset, x.free) for x in get_balances()])
    symbols_list = get_symbols_by_assets(collect(keys(balances_dict)))
    
    @info "Echange balances" balances_dict

    safe_symbols = ExchangeSymbol[]
    safe_amounts = Dict{String, Float64}()
    base_asset = "BTC"
    safe_amounts[base_asset] = balances_dict[base_asset]*0.01

    for asset in keys(balances_dict)
        if asset == base_asset
            continue
        end

        symbol = [x for x in symbols_list if (x.asset1==asset && x.asset2==base_asset) 
                                            || (x.asset1==base_asset && x.asset2==asset)][1]

        price = parse(Float64, bapi_get_price(symbol.name).response["price"])
        if symbol.asset1==asset
            price = 1/price
        end

        safe_amount = fulfil_filters(safe_amounts[base_asset]*price, symbol.name)

        if balances_dict[asset] > safe_amount*4 # cause the quadrangular arbitrage
            if check_exchange_filters(symbol, safe_amount)
                safe_amounts[asset] = safe_amount
                push!(safe_symbols, symbol)
            end
        else
            @warn "Removing $asset due to insufficient balance (min $(safe_amount*4))" balances_dict[asset] 
        end
    end

    return safe_symbols, safe_amounts
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

function check_exchange_filters(symbol::ExchangeSymbol, safe_amount::Float64)
    sym_name = symbol.name
    filters = bapi_get_filters([sym_name])[1]["filters"]

    filter_passed_flag = true
    for f in filters
        if f["filterType"] == "PRICE_FILTER"
            #filter_passed_flag = check_filter_price(sym_name, f, safe_amount)
            continue
        elseif f["filterType"] == "PERCENT_PRICE"
            #filter_passed_flag = check_filter_percentprice(sym_name, Dict(f), safe_amounts[sym_name])
            continue
        elseif f["filterType"] == "LOT_SIZE"
            filter_passed_flag = check_filter_lotsize(sym_name, f, safe_amount)
            continue
        elseif f["filterType"] == "MIN_NOTIONAL"
            #filter_passed_flag = check_filter_minnotional(sym_name, Dict(f), safe_amounts[sym_name])
            continue
        elseif f["filterType"] == "ICEBERG_PARTS"
            #filter_passed_flag = check_filter_iceberg(sym_name, Dict(f), safe_amounts[sym_name])
            continue
        elseif f["filterType"] == "MARKET_LOT_SIZE"
            filter_passed_flag = check_filter_marketlotsize(sym_name, f, safe_amount)
            continue
        elseif f["filterType"] == "MAX_NUM_ORDERS"
            #filter_passed_flag = check_filter_maxnumorders(sym_name, Dict(f), safe_amounts[sym_name])
            continue
        elseif f["filterType"] == "MAX_NUM_ALGO_ORDERS"
            #filter_passed_flag = check_filter_maxnumalgoorders(sym_name, Dict(f), safe_amounts[sym_name])
            continue
        else
            filter_type = f["filterType"]
            @warn "Filter type $filter_type unnkown on symbol $sym_name."
        end
    end
    return filter_passed_flag
end

function check_arbitrage!(arbitrage::Any)
    # Check if anything strange in arbitrage
    if isnothing(arbitrage)
        return nothing
    end

    # if any of the operations values are 1
    for order in arbitrage.orders
        if order.price == 1
            @debug "ARBITRAGE CHECK FAILED: Computed Arbitraged contains orders with price=1" arbitrage
            return nothing
        end
    end

    return arbitrage
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
