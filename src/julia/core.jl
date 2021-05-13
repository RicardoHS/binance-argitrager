using Dates

struct ExchangeSymbol
    name::String
    asset1::String
    asset2::String
    filters::Dict{String, Any}
end
Base.show(io::IO, obj::ExchangeSymbol) = print(io, "ExchangeSymbol($(obj.name), $(obj.asset1), $(obj.asset2), <$(length(obj.filters)) filters>)")

struct SymbolPrice
    symbol::ExchangeSymbol
    ask::Float64
    ask_qty::Float64
    bid::Float64
    bid_qty::Float64
    timestamp::DateTime
end

struct Order
    type::String
    symbol::ExchangeSymbol
    price::Float64
    quantity::Float64
end

struct ArbitrageIterative
    type::String
    orders::Vector{Order}
    aer::Float64
end

function mean_weighted(a::Vector{Float64}, weights::Vector{Float64})
    return sum(a .* weights) / sum(weights)
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

function get_safe_minqty(price::Float64, s::ExchangeSymbol)
    f = s.filters
    lot_stepsize = parse(Float64, f["LOT_SIZE"]["stepSize"])
    min_notional = parse(Float64, f["MIN_NOTIONAL"]["minNotional"])
    min_qty = min_notional / price
    min_qty_rounded = ceil(min_qty, digits=Integer(abs(floor(log10(lot_stepsize)))))
    return min_qty_rounded
end

function get_safe_qty(qty::Float64, s::ExchangeSymbol)
    min_qty = parse(Float64, s.filters["LOT_SIZE"]["minQty"])
    round_to = Integer(abs(floor(log10(min_qty))))
    safe_qty = max(min_qty, round(qty, digits=round_to))
    return safe_qty
end

function get_safe_price(price::Float64, s::ExchangeSymbol)
    min_price = parse(Float64, s.filters["PRICE_FILTER"]["minPrice"])
    round_to = Integer(abs(floor(log10(min_price))))
    safe_price = max(min_price, round(price, digits=round_to))
    return safe_price
end

function arbitrage_iterative(buysell_matrix::Matrix, assets::Vector{String}, symbols::Vector{SymbolPrice}, quantities::Dict{String, Vector{Float64}})
    assets_dict = Dict([(a,i) for (i, a) in enumerate(assets)])
    v1 = [assets_dict[s.symbol.asset1] for s in symbols]
    v2 = [assets_dict[s.symbol.asset2] for s in symbols]

    arbitrages = []
    for (i1, a1) in enumerate(v1)
        for (i2, b2) in enumerate(v2)
            if a1 == b2
                b1 = v2[i1]
                a2 = v1[i2]
                for i3 in 1:length(v1)
                    # Other types of arbitrages may exists. eg: BSB, BBB (or the inverse: SBS, SSS, SSB) 
                    if v1[i3]==a2 && v2[i3]==b1
                        orders = Order[]
                        prices = [buysell_matrix[a1,b1], buysell_matrix[a2,b2], buysell_matrix[b1,a2]]
                        if prod(prices) == 0
                            continue
                        end
                        initial_quantity = quantities[symbols[i1].symbol.name][1]
                        a1_qty = initial_quantity
                        push!(orders, Order("BUY", symbols[i1].symbol, prices[1], a1_qty))
                        a2_qty = get_safe_qty((1/prices[2]) * initial_quantity, symbols[i2].symbol)
                        push!(orders, Order("BUY", symbols[i2].symbol, prices[2], a2_qty))
                        a3_qty = a2_qty
                        push!(orders, Order("SELL", symbols[i3].symbol, prices[3], a3_qty))

                        if a2_qty <= quantities[symbols[i2].symbol.name][1] && a3_qty <= quantities[symbols[i3].symbol.name][2]
                            # If a2_qty is less than the detected qty and also a3_qty is less too 
                            aer = 1 / prices[1] * 1 / prices[2] * prices[3] -1
                        else
                            aer = 0
                        end

                        push!(arbitrages, ArbitrageIterative("BBS", orders, aer))

                    end
                end
            end
        end
    end
    if length(arbitrages)==0
        return nothing
    end
    return sort(arbitrages, rev=true, by = x -> x.aer)[1]
end
#
#buysell_matrix = [0.0 47884.9783130283 551.8396526652529 3385.9272305965633 0.43408167297282474 1.211898353192841; 
#                  47870.58738979748 0.0 0.011524124404551 0.07071986537108689 9.118672906923945e-6 58036.063105138026; 
#                  551.3417633291331 0.011508675554448044 0.0 0.16263517973045394 0.0 668.4581801499872; 
#                  3384.2398435460764 0.07067921368801197 0.16304352523635612 0.0 0.0 4103.975922570707; 
#                  0.43304520123747925 8.997305627691597e-6 0.0 0.0 0.0 0.5252814030882852; 
#                  1.2124627046708885 58043.98293187449 668.6770033462739 4104.379033559045 0.5258406160535631 0.0]
#assets = ["EUR", "BTC", "BNB", "ETH", "DOGE", "USDT"]
#symbols = ExchangeSymbol[ExchangeSymbol("DOGEEUR", "DOGE", "EUR"), 
#                         ExchangeSymbol("BTCEUR", "BTC", "EUR"), 
#                         ExchangeSymbol("BNBETH", "BNB", "ETH"), 
#                         ExchangeSymbol("BNBBTC", "BNB", "BTC"), 
#                         ExchangeSymbol("ETHBTC", "ETH", "BTC"), 
#                         ExchangeSymbol("BNBUSDT", "BNB", "USDT"), 
#                         ExchangeSymbol("DOGEBTC", "DOGE", "BTC"), 
#                         ExchangeSymbol("EURUSDT", "EUR", "USDT"), 
#                         ExchangeSymbol("ETHUSDT", "ETH", "USDT"), 
#                         ExchangeSymbol("ETHEUR", "ETH", "EUR"), 
#                         ExchangeSymbol("BTCUSDT", "BTC", "USDT"), 
#                         ExchangeSymbol("DOGEUSDT", "DOGE", "USDT"), 
#                         ExchangeSymbol("BNBEUR", "BNB", "EUR")]
#safe_quantities = Dict("BNBEUR" => 0.001, 
#                       "BTCEUR" => 9.999999999999999e-6, 
#                       "BNBETH" => 0.01, 
#                       "BNBBTC" => 0.1, 
#                       "ETHBTC" => 0.01, 
#                       "BNBUSDT" => 0.001, 
#                       "DOGEBTC" => 10.0, 
#                       "EURUSDT" => 0.1, 
#                       "ETHUSDT" => 0.0001, 
#                       "ETHEUR" => 0.0001, 
#                       "BTCUSDT" => 9.999999999999999e-6, 
#                       "DOGEEUR" => 1.0, 
#                       "DOGEUSDT" => 1.0)
#arbitrage_iterative(buysell_matrix, assets, symbols, safe_quantities)
#
