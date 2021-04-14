using LinearAlgebra


function compute_API(lambda_max, n)
    return abs(lambda_max-n)/(n-1)
end

function find_arbitrage_path(A, vecmax, currencies)
    divide(i,j) = i/j
    vecmax = real(vecmax)
    B = [divide(i, j) for i in vecmax, j in vecmax]
    C = A ./ B

    C_max = argmax(C)
    C_min = argmin(C)

    if C_max[1]==C_min[2] && C_max[2]==C_min[1]
        # Direct arbitrage
        println("DIRECT")
        println("BUY ", currencies[C_min[1]], "/", currencies[C_min[2]], "(", A[C_min], ")")
        println("SELL ",currencies[C_max[1]], "/", currencies[C_min[1]], "(", A[C_max[1],C_min[1]], ")")
        aer = 1 / ( C[C_min] * C[C_max] ) - 1

    elseif C_max[1]==C_min[1] || C_max[2]==C_min[2]
        # Triangular arbitrage
        if C_max[1]==C_min[1]
            # Arbitrage elements in the same row
            println("TRIANGULAR ROW")
            println("BUY ", currencies[C_min[1]], "/", currencies[C_min[2]], "(" , A[C_min], ")")
            println("SELL ",currencies[C_min[1]], "/", currencies[C_max[2]], "(" , A[C_min[1],C_max[2]], ")")
            println("BUY ", currencies[C_min[2]], "/", currencies[C_max[2]], "(" , A[C_min[2],C_max[2]], ")")
            aer = 1 / C[C_min] * C[C_min[1],C_max[2]] / C[C_min[2],C_max[2]] - 1

        else # C_max[2]==C_min[2] 
            # Arbitrage elements in the same col
            println("TRIANGULAR COLUMN")
            println("BUY  ", currencies[C_min[1]], "/", currencies[C_min[2]], "(", A[C_min], ")")
            println("SELL ", currencies[C_min[1]], "/", currencies[C_max[1]], "(", A[C_min[1],C_max[1]], ")")
            println("SELL ", currencies[C_max[1]], "/", currencies[C_min[2]], "(", A[C_max[1],C_min[2]], ")")
            aer = 1 / C[C_min] * C[C_min[1],C_max[1]] * C[C_max] - 1

        end
    else
        # Cuadrangular arbitrage
        println("CUADRANGULAR")
        println("BUY ",  currencies[C_min[1]], "/", currencies[C_min[2]], "(", A[C_min], ")")
        println("SELL ", currencies[C_min[1]], "/", currencies[C_max[1]], "(", A[C_min[1],C_max[1]], ")")
        println("SELL ", currencies[C_max[1]], "/", currencies[C_max[2]], "(", A[C_max[1],C_max[2]], ")")
        println("BUY ",  currencies[C_min[2]], "/", currencies[C_max[2]], "(", A[C_min[2],C_max[2]], ")")
        aer = 1 / C[C_min] * C[C_min[1],C_max[1]] * C[C_max] / C[C_min[2],C_max[2]] - 1

    end
end

function arbitrage(cross_rates_matrix, currencies)
    eigens = eigen(cross_rates_matrix)# x -> -abs(x)
    nrow, ncol = size(eigens.vectors)
    api = compute_API(eigens.values[ncol], ncol)

    if api > 0 
        println("ARBITRAGE DETECTED, API=",api)
        max_evector = eigens.vectors[:,ncol]
        find_arbitrage_path(cross_rates_matrix, max_evector, currencies)
    else
        println("NOT ARBITRAGE DETECTED, API=",api)
    end
end

# transpose to inverse the arbitrage direction. 
# Need to study this, sometimes the aer is 0 in
# one direction but positive or different in the
# other direction.
#aer = arbitrage(transpose(example_matrix), CURRENCIES)