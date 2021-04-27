using LinearAlgebra

struct Order
    type::String
    asset1::String
    asset2::String
    price::Float64
end

struct Arbitrage
    type::String
    orders::Vector{Order}
    aer::Float64
end


function compute_API(lambda_max::Real, n::Integer)
    return abs(lambda_max-n)/(n-1)
end

function mean_weighted(a::Vector{Float64}, weights::Vector{Float64})
    return sum(a .* weights) / sum(weights)
end

function find_arbitrage_path(A::Matrix, vecmax::Vector, assets::Vector{String})
    divide(i,j) = i/j
    vecmax = real(vecmax)
    B = [divide(i, j) for i in vecmax, j in vecmax]
    C = A ./ B

    C_max = argmax(C)
    C_min = argmin(C)
    orders = []

    if C_max[1]==C_min[2] && C_max[2]==C_min[1]
        # Direct arbitrage
        push!(orders, Order("BUY", assets[C_min[1]], assets[C_min[2]], A[C_min]))
        push!(orders, Order("SELL", assets[C_max[1]], assets[C_min[1]], A[C_max[1],C_min[1]]))
        aer = 1 / ( C[C_min] * C[C_max] ) - 1
        return Arbitrage("DIRECT", orders, aer)
    elseif C_max[1]==C_min[1] || C_max[2]==C_min[2]
        # Triangular arbitrage
        if C_max[1]==C_min[1]
            # Arbitrage elements in the same row
            push!(orders, Order("BUY", assets[C_min[1]], assets[C_min[2]], A[C_min]))
            push!(orders, Order("SELL", assets[C_min[1]], assets[C_max[2]], A[C_min[1],C_max[2]]))
            push!(orders, Order("BUY", assets[C_min[2]], assets[C_max[2]], A[C_min[2],C_max[2]]))
            aer = 1 / C[C_min] * C[C_min[1],C_max[2]] / C[C_min[2],C_max[2]] - 1
            return Arbitrage("TRIANGULAR ROW", orders, aer)
        else # C_max[2]==C_min[2] 
            # Arbitrage elements in the same col
            push!(orders, Order("BUY", assets[C_min[1]], assets[C_min[2]], A[C_min]))
            push!(orders, Order("SELL", assets[C_min[1]], assets[C_max[1]], A[C_min[1],C_max[1]]))
            push!(orders, Order("SELL", assets[C_max[1]], assets[C_min[2]], A[C_max[2],C_min[2]]))
            aer = 1 / C[C_min] * C[C_min[1],C_max[1]] * C[C_max] - 1
            return Arbitrage("TRIANGULAR COLUMN", orders, aer)
        end
    else
        # Cuadrangular arbitrage
        push!(orders, Order("BUY", assets[C_min[1]], assets[C_min[2]], A[C_min]))
        push!(orders, Order("SELL", assets[C_min[1]], assets[C_max[1]], A[C_min[1],C_max[1]]))
        push!(orders, Order("SELL", assets[C_max[1]], assets[C_max[2]], A[C_max[1],C_max[2]]))
        push!(orders, Order("BUY", assets[C_min[2]], assets[C_max[2]], A[C_min[2],C_max[2]]))
        aer = 1 / C[C_min] * C[C_min[1],C_max[1]] * C[C_max] / C[C_min[2],C_max[2]] - 1
        return Arbitrage("CUADRANGULAR", orders, aer)
    end
end

function arbitrage(cross_rates_matrix::Matrix, assets::Vector{String})
    eigens = eigen(cross_rates_matrix)
    nrow, ncol = size(eigens.vectors)
    api = compute_API(real(eigens.values[ncol]), ncol)

    if rank(cross_rates_matrix) != length(assets)
        #println("NOT ARBITRAGE DETECTED, RANK(matrix) < LEN(assets)")
        return nothing
    end

    if api > 0
        #println("ARBITRAGE DETECTED, API=",api)
        max_evector = eigens.vectors[:,ncol]
        return find_arbitrage_path(cross_rates_matrix, max_evector, assets)
    else
        #println("NOT ARBITRAGE DETECTED, API=",api)
        return nothing
    end
end

# transpose to inverse the arbitrage direction. 
# Need to study this, sometimes the aer is 0 in
# one direction but positive or different in the
# other direction. Probable because rank
#arb = arbitrage(transpose(example_matrix), CURRENCIES)
