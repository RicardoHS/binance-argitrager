using Test
include("../core.jl")

@testset "Direct arbitrage 1 checking" begin
    CURRENCIES = ["ADA", "BNB", "BTC", "ETH", "EUR", "USDT", "XRP"]
    example_matrix = [1.00000000e+00 2.60838580e-03 1.00000000e+00 1.00000000e+00 1.00000000e+00 1.00000000e+00 1.00000000e+00;
                    3.82160455e+02 1.00000000e+00 8.67488247e-03 1.00000000e+00 1.00000000e+00 1.00000000e+00 1.00000000e+00;
                    1.00000000e+00 1.15247201e+02 1.00000000e+00 2.68415352e+01 1.00000000e+00 1.00000000e+00 1.00000000e+00;
                    1.00000000e+00 1.00000000e+00 3.72507611e-02 1.00000000e+00 1.00000000e+00 1.00000000e+00 1.00000000e+00;
                    1.00000000e+00 1.00000000e+00 1.00000000e+00 1.00000000e+00 1.00000000e+00 1.19419518e+00 1.00000000e+00;
                    1.00000000e+00 1.00000000e+00 1.00000000e+00 1.00000000e+00 8.37010064e-01 1.00000000e+00 5.85993995e-01;
                    1.00000000e+00 1.00000000e+00 1.00000000e+00 1.00000000e+00 1.00000000e+00 1.70529411e+00 1.00000000e+00]
    #=
    Arbitrage oportunity detected. API=5.185
    Matrix shape:  (7, 7)
    Arbitrage orders: DIRECT
    ADA -> BNB -> ADA : AER = 0.319% : Fee = 0.150% : Return = 0.169%
    BUY  BNB/ADA(0.0026083857962392438) in ADA   
    SELL ADA/BNB(382.16045533634656) in BNB   
    1/0.002608*382.2 = 1.0032
    =#
    arb = arbitrage(transpose(example_matrix), CURRENCIES)
    ord1 = arb.orders[1]
    ord2 = arb.orders[2]
    @test arb.type == "DIRECT"
    @test arb.aer == 0.0031882283517752352
    @test ord1.type == "BUY"
    @test ord1.currency1 == "BNB"
    @test ord1.currency2 == "ADA"
    @test ord1.value ≈ 0.0026083857962392438
    @test ord2.type == "SELL"
    @test ord2.currency1 == "ADA"
    @test ord2.currency2 == "BNB"
    @test ord2.value ≈ 382.16045533634656
end

@testset "Direct arbitrage 2 checking" begin
    CURRENCIES = ["ADA", "BNB", "BTC", "ETH", "EUR", "LTC", "USDT", "XRP"]
    example_matrix = [1.00000000e+00 2.51197027e-03 1.00000000e+00 6.13029095e-04 1.19596561e+00 1.00000000e+00 1.42990614e+00 1.00000000e+00;
                    3.96589968e+02 1.00000000e+00 8.93236432e-03 2.43608766e-01 4.75243647e+02 2.11692098e+00 5.67721644e+02 3.17575037e+02;
                    1.00000000e+00 1.11913230e+02 1.00000000e+00 2.72970273e+01 5.32198690e+04 2.39116720e+02 6.35753340e+04 1.00000000e+00;
                    1.62750203e+03 4.09764936e+00 3.66210966e-02 1.00000000e+00 1.94932754e+03 8.74493375e+00 2.32825851e+03 1.30878418e+03;
                    8.34335531e-01 2.10153113e-03 1.87851473e-05 5.12827153e-04 1.00000000e+00 4.48868403e-03 1.19393399e+00 6.72341604e-01;
                    1.00000000e+00 4.63767183e-01 4.17708361e-03 1.13980863e-01 2.22133753e+02 1.00000000e+00 2.65685651e+02 1.00000000e+00;
                    6.99297503e-01 1.76110290e-03 1.57280848e-05 4.29466298e-04 8.37326712e-01 3.76321605e-03 1.00000000e+00 5.63511726e-01;
                    1.00000000e+00 3.09685197e-03 1.00000000e+00 7.61746862e-04 1.48311635e+00 1.00000000e+00 1.77412204e+00 1.00000000e+00]

    #=              
    Arbitrage oportunity detected. API=9.048
    Matrix shape:  (8, 8)
    Arbitrage orders: DIRECT
    BNB -> BTC -> BNB : AER = 0.035% : Fee = 0.150% : Return = -0.115%
    BUY  BTC/BNB(0.008932364320785596) in BNB   
    SELL BNB/BTC(111.91323011345173) in BTC   
    1/0.008932*111.9 = 1.0004
    =#
    arb = arbitrage(transpose(example_matrix), CURRENCIES)
    ord1 = arb.orders[1]
    ord2 = arb.orders[2]
    @test rank(example_matrix) == length(CURRENCIES)
    @test arb.type == "DIRECT"
    @test arb.aer == 0.00035038013528576606
    @test ord1.type == "BUY"
    @test ord1.currency1 == "BTC"
    @test ord1.currency2 == "BNB"
    @test ord1.value ≈ 0.008932364320785596
    @test ord2.type == "SELL"
    @test ord2.currency1 == "BNB"
    @test ord2.currency2 == "BTC"
    @test ord2.value ≈ 111.91323011345173
end

#=
@testset "Triangular columns checking" begin
    CURRENCIES =  ["ATOM", "BTC", "EASY", "OMG", "PERP", "SRM"]
    example_matrix = [1.00000000e+00 3.79462561e-04 1.00000000e+00 1.00000000e+00 1.00000000e+00 1.00000000e+00;
                    2.62738369e+03 1.00000000e+00 2.35419700e+03 6.90841266e+03 8.04852134e+03 9.17858292e+03;
                    1.00000000e+00 4.20621409e-04 1.00000000e+00 1.00000000e+00 0.03000000e+00 1.00000000e+00;
                    1.00000000e+00 1.43940312e-04 1.00000000e+00 1.60000000e+00 1.00000000e+00 1.00000000e+00;
                    1.00000000e+00 1.23660594e-04 1.45000000e+00 1.00000000e+00 1.00000000e+00 3.00000000e+00;
                    1.12000000e+00 1.08663121e-04 1.00000000e+00 1.00000000e+00 1.00000000e+00 1.00000000e+00]
    #=
    Arbitrage oportunity detected. API=0.0474
    Matrix shape:  (6, 6)
    Arbitrage orders: TRIANGULAR COLUMN
    BTC -> EASY -> SRM -> BTC : AER = 289.882% : Fee = 0.225% : Return = 289.657%
    BUY EASY/BTC(2354.196996044633) in BTC
    SELL EASY/SRM(1.0) in SRM
    SELL SRM/BTC(9178.582920978679) in BTC
    1/2.354e+03*1.0*9.179e+03 = 3.8988
    =#
    arb = arbitrage(transpose(example_matrix), CURRENCIES)
    ord1 = arb.orders[1]
    ord2 = arb.orders[2]
    ord3 = arb.orders[3]
    @test rank(example_matrix) == length(CURRENCIES)
    @test arb.type == "TRIANGULAR COLUMN"
    @test arb.aer == 2.898816844979414
    @test ord1.type == "BUY"
    @test ord1.currency1 == "EASY"
    @test ord1.currency2 == "BTC"
    @test ord1.value ≈ 2354.196996044633
    @test ord2.type == "SELL"
    @test ord2.currency1 == "EASY"
    @test ord2.currency2 == "SRM"
    @test ord2.value ≈ 1.0
    @test ord3.type == "SELL"
    @test ord3.currency1 == "SRM"
    @test ord3.currency2 == "BTC"
    @test ord3.value ≈ 9178.582920978679
end=#

@testset "Triangular rows checking" begin
    CURRENCIES =  ["USDT", "EUR", "POUND", "YEN", "HKDOLLAR", "SINGDOLLAR"]
    example_matrix = [1      1.1038  0.6888  1.19    7.8     1.8235;
                    0.905  1       0.6241  1.0955  7.0801  1.6403;
                    1.4501 1.6026  1       1.7705  11.32   2.6506;
                    0.8893 0.9099  0.5677  1       6.43    1.4957;
                    0.1282 0.1414  0.0883  0.1555  1       0.2328;
                    0.5521 0.6098  0.3773  0.6681  4.3100  1     ]
    #=
    Arbitrage oportunity detected. API=0.002311
    Arbitrage orders: TRIANGULAR ROW
    EUR -> YEN -> USDT -> EUR : AER = 7.996%
    BUY  YEN/EUR(0.9099) in FRANK
    SELL YEN/USDT(0.8893) in NY
    BUY  EUR/USDT(0.905) in NY
    1/0.9099*0.8893/0.905 = 1.08
    =#
    arb = arbitrage(example_matrix, CURRENCIES)
    ord1 = arb.orders[1]
    ord2 = arb.orders[2]
    ord3 = arb.orders[3]
    @test rank(example_matrix) == length(CURRENCIES)
    @test arb.type == "TRIANGULAR ROW"
    @test arb.aer == 0.07995596626185009
    @test ord1.type == "BUY"
    @test ord1.currency1 == "YEN"
    @test ord1.currency2 == "EUR"
    @test ord1.value ≈ 0.9099
    @test ord2.type == "SELL"
    @test ord2.currency1 == "YEN"
    @test ord2.currency2 == "USDT"
    @test ord2.value ≈ 0.8893
    @test ord3.type == "BUY"
    @test ord3.currency1 == "EUR"
    @test ord3.currency2 == "USDT"
    @test ord3.value ≈ 0.905
end

@testset "Cuadrangular arbitrage checking" begin
    CURRENCIES = ["ADA", "BNB", "BTC", "ETH", "EUR", "LTC", "USDT", "XRP"]
    example_matrix = [1.00000000e+00 2.52419313e-03 1.00000000e+00 6.19663281e-04 1.18279275e+00 1.00000000e+00 1.41185421e+00 1.00000000e+00;
                    3.95264136e+02 1.00000000e+00 8.85990774e-03 2.45452625e-01 4.68338916e+02 2.06789531e+00 5.58678415e+02 3.08487723e+02;
                    1.00000000e+00 1.12865401e+02 1.00000000e+00 2.77305123e+01 5.28966654e+04 2.34752634e+02 6.30977188e+04 1.00000000e+00;
                    1.61027877e+03 4.06854348e+00 3.60512661e-02 1.00000000e+00 1.90698895e+03 8.45996586e+00 2.27471683e+03 1.26610798e+03;
                    8.44297378e-01 2.13227178e-03 1.88997706e-05 5.24264199e-04 1.00000000e+00 4.43570627e-03 1.19246958e+00 6.64114235e-01;
                    1.00000000e+00 4.77592373e-01 4.25387096e-03 1.17974952e-01 2.25107158e+02 1.00000000e+00 2.68500978e+02 1.00000000e+00;
                    7.07981201e-01 1.78932864e-03 1.58479156e-05 4.39540951e-04 8.38359614e-01 3.72189996e-03 1.00000000e+00 5.56920135e-01;
                    1.00000000e+00 3.18918407e-03 1.00000000e+00 7.88625768e-04 1.50418594e+00 1.00000000e+00 1.79505578e+00 1.00000000e+00]

    #=
    Arbitrage oportunity detected. API=9.03
    Matrix shape:  (8, 8)
    Arbitrage orders: CUADRANGULAR
    ETH -> BTC -> BNB -> BTC -> ETH : AER = 0.026% : Fee = 0.300% : Return = -0.274%
    BUY  BTC/ETH(0.036051266079747) in ETH
    SELL BTC/BNB(0.0088599077408141) in BNB
    SELL BNB/BTC(112.86540102198703) in BTC
    BUY  ETH/BTC(27.73051234642917) in BTC
    1/0.03605*0.00886*112.9/27.73 = 1.0003
    =#
    arb = arbitrage(transpose(example_matrix), CURRENCIES)
    ord1 = arb.orders[1]
    ord2 = arb.orders[2]
    ord3 = arb.orders[3]
    ord4 = arb.orders[4]
    @test rank(example_matrix) == length(CURRENCIES)
    @test arb.type == "CUADRANGULAR"
    @test arb.aer == 0.00025703383090047716
    @test ord1.type == "BUY"
    @test ord1.currency1 == "BTC"
    @test ord1.currency2 == "ETH"
    @test ord1.value ≈ 0.036051266079747
    @test ord2.type == "SELL"
    @test ord2.currency1 == "BTC"
    @test ord2.currency2 == "BNB"
    @test ord2.value ≈ 0.0088599077408141
    @test ord3.type == "SELL"
    @test ord3.currency1 == "BNB"
    @test ord3.currency2 == "BTC"
    @test ord3.value ≈ 112.86540102198703
    @test ord4.type == "BUY"
    @test ord4.currency1 == "ETH"
    @test ord4.currency2 == "BTC"
    @test ord4.value ≈ 27.73051234642917
end