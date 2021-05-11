#!/bin/bash

cd $HOME

wget https://julialang-s3.julialang.org/bin/linux/x64/1.6/julia-1.6.1-linux-x86_64.tar.gz
tar -zxvf julia-1.6.1-linux-x86_64.tar.gz
rm julia-1.6.1-linux-x86_64.tar.gz
sudo ln -s $HOME/julia-1.6.1/bin/julia /usr/bin/julia
