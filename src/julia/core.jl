struct ExchangeSymbol
    name::String
    asset1::String
    asset2::String
end

struct OrderSymbol
    type::String
    symbol::String
    price::Float64
    quantity::Float64
end

struct ArbitrageIterative
    type::String
    orders::Vector{OrderSymbol}
    aer::Float64
end

function mean_weighted(a::Vector{Float64}, weights::Vector{Float64})
    return sum(a .* weights) / sum(weights)
end

function arbitrage_iterative(buysell_matrix::Matrix, assets::Vector{String}, symbols::Vector{ExchangeSymbol}, initial_quantities::Dict{String, Float64})
    assets_dict = Dict([(a,i) for (i, a) in enumerate(assets)])
    v1 = [assets_dict[s.asset1] for s in symbols]
    v2 = [assets_dict[s.asset2] for s in symbols]

    arbitrages = []
    for (i1, a1) in enumerate(v1)
        for (i2, b2) in enumerate(v2)
            if a1 == b2
                b1 = v2[i1]
                a2 = v1[i2]
                for i3 in 1:length(v1)
                    #if v1[i3]==b1 && v2[i3]==a2
                    #    orders = OrderSymbol[]
                    #    prices = [buysell_matrix[a1,b1], buysell_matrix[a2,b2], buysell_matrix[b1,a2]]
                    #    if prod(prices) == 0
                    #        continue
                    #    end
                    #    initial_quantity = initial_quantities[symbols[i1].name]
                    #    push!(orders, OrderSymbol("BUY", symbols[i1].name, prices[1], initial_quantity))
                    #    push!(orders, OrderSymbol("SELL", symbols[i2].name, prices[2], initial_quantity / prices[1]))
                    #    push!(orders, OrderSymbol("BUY", symbols[i3].name, prices[3], initial_quantity / prices[1] * prices[2]))
                    #    aer = 1 / prices[1] * prices[2] * 1 /  prices[3] -1
                    #    push!(arbitrages, ArbitrageIterative("BSB", orders, aer))

                    if v1[i3]==a2 && v2[i3]==b1
                        orders = OrderSymbol[]
                        prices = [buysell_matrix[a1,b1], buysell_matrix[a2,b2], buysell_matrix[b1,a2]]
                        if prod(prices) == 0
                            continue
                        end
                        initial_quantity = initial_quantities[symbols[i1].name]
                        push!(orders, OrderSymbol("BUY", symbols[i1].name, prices[1], initial_quantity))
                        push!(orders, OrderSymbol("BUY", symbols[i2].name, prices[2], (1/prices[2]) * initial_quantity ))
                        push!(orders, OrderSymbol("SELL", symbols[i3].name, prices[3], (1/prices[2]) * initial_quantity ))
                        aer = 1 / prices[1] * 1 / prices[2] * prices[3] -1
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
