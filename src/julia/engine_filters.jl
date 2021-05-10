using JSON3

function warn_filter(filter_name::String, filter_arg::String, filter_val::Any, symbol::String)
    @warn "FILTER NOT PASSED: $symbol - $filter_name: $filter_arg ! $filter_val"
end

function check_filter_price(symbol::String, filter::JSON3.Object, price::Float64)
    passed = true
    filter_name = "PRICE_FILTER"
    min_price = parse(Float64, filter["minPrice"])
    max_price = parse(Float64, filter["maxPrice"])
    tick_size = parse(Float64, filter["tickSize"])

    if min_price != 0
        if !(price >= min_price)
            warn_filter(filter_name, "minPrice", min_price, symbol)
            passed=false
        end
    end

    if max_price != 0
        if !(price <= max_price)
            warn_filter(filter_name, "maxPrice", max_price, symbol)
            passed=false
        end
    end

    if tick_size != 0
        if !(mod(price-min_price, tick_size) == 0)
            warn_filter(filter_name, "tickSize", tick_size, symbol)
            passed=false
        end
    end

    return passed
end

function check_filter_lot(filter_name::String, symbol::String, filter::JSON3.Object, safe_quantity::Float64)
    passed=true
    min_qty = parse(Float64, filter["minQty"])
    max_qty = parse(Float64, filter["maxQty"])
    step_size = parse(Float64, filter["stepSize"])

    if !(safe_quantity >= min_qty)
        warn_filter(filter_name, "minQty", min_qty, symbol)
        passed=false
    end

    if !(safe_quantity <= max_qty)
        warn_filter(filter_name, "maxQty", max_qty, symbol)
        passed=false
    end

    if step_size > 0
        if !(mod(safe_quantity-min_qty, step_size) == 0)
            warn_filter(filter_name, "stepSize", step_size, symbol)
            passed=false
        end
    end
    return passed
end

function check_filter_lotsize(symbol::String, filter::JSON3.Object, safe_quantity::Float64)
    filter_name = "LOT_SIZE"
    return check_filter_lot(filter_name, symbol, filter, safe_quantity)
end

function check_filter_marketlotsize(symbol::String, filter::JSON3.Object, safe_quantity::Float64)
    filter_name = "MARKET_LOT_SIZE"
    return check_filter_lot(filter_name, symbol, filter, safe_quantity)
end
