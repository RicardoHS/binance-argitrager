# binance-argitrager
My own arbitrage bot for the binance in-market. Detect and perform triangular arbitrage between assets in the binance market. 

# Install
### julia
Use the script `install_julia.sh` in the scripts folder to install the correct julia version.

### dependencies
After julia installation, to install the dependencies just run 

```julia
julia src/julia/requirements.jl
```

# Configuration
In the `src/julia/config_default.ini` file you can find the default config file. Make a copy and rename it to `config.ini`, add the binance keys and change the involved assets. All assets need to have a minimum balance in order to run the arbitrage operations, the program check the balances on startup, so dont worry about this.

# Execution

Run the following to run the julia in-time compiler and test the first arbitrage operation.

```julia
julia -i src/julia/app.jl
```

This will perform an initial arbitrage (in test mode, it does not perform the real operations). After this first arbitrage, just type in the julia prompt

```julia
main(test=false)
```

To start the real arbitrage.

# IMPORTANT

Profitable arbitrage operations need a lot of different expert knowledge in a bunch of different areas. This project is just a tinny part of a whole arbitrage system and it was more like a project to learn julia and cryptos than a project to earn money. Use it by your own responsibility.

