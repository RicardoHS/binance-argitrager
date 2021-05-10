using LinearAlgebra

struct Arbitrage
    type::String
    orders::Vector{Order}
    aer::Float64
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
    if length(cross_rates_matrix) <= 2
        @debug "NOT ARBITRAGE DETECTED, LENGTH(matrix) <= 2"
        return nothing
    end
    eigens = eigen(cross_rates_matrix)
    nrow, ncol = size(eigens.vectors)
    api = compute_API(real(eigens.values[ncol]), ncol)

    if rank(cross_rates_matrix) != length(assets)
        @debug "NOT ARBITRAGE DETECTED, RANK(matrix) < LEN(assets)"
        return nothing
    end

    if api > 0
        @debug "ARBITRAGE DETECTED, API=",api
        max_evector = eigens.vectors[:,ncol]
        return find_arbitrage_path(cross_rates_matrix, max_evector, assets)
    else
        @debug "NOT ARBITRAGE DETECTED, API=",api
        return nothing
    end
end

function compute_API(lambda_max::Real, n::Integer)
    return abs(lambda_max-n)/(n-1)
end
