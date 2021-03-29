#!/usr/bin/env python
# coding: utf-8

# # Arbitrage auto detection using matrices
#  
#  https://papers.ssrn.com/sol3/papers.cfm?abstract_id=1096549

# In[1]:
import sys

import urllib
import urllib.request
import json

import pandas as pd
import numpy as np


# In[2]:


pd.set_option('display.float_format', lambda x: '%.3f' % x)


# In[3]:


binance_base = "https://<>.binance.com"
binance_subdomains = ["api", "api1", "api2", "api3"]

binance_url = binance_base.replace('<>', binance_subdomains[0])

binance_endpoints = {
    'ping': ('GET', '/api/v3/ping'),
    'server_time': ('GET', '/api/v3/time'),
    'exchange_info': ('GET', '/api/v3/exchangeInfo'),
    'order_book': ('GET', '/api/v3/depth', {'symbol': True, 'limit': False}),
    'recent_trades': ('GET', '/api/v3/trades', {'symbol': True, 'limit': False}),
    'average_price': ('GET', '/api/v3/avgPrice', {'symbol': True}),
    'price': ('GET', '/api/v3/ticker/price', {'symbol': False}),
    'best_book_price': ('GET', '/api/v3/ticker/bookTicker', {'symbol': False})
}


# In[4]:


binance_uri = binance_url + binance_endpoints['exchange_info'][1]

web_url = urllib.request.urlopen(binance_uri)
data = web_url.read()
encoding = web_url.info().get_content_charset('utf-8')
JSON_object = json.loads(data.decode(encoding))

df_symbols = pd.DataFrame(JSON_object['symbols'])
df_symbols = df_symbols[df_symbols['status']=='TRADING']


# In[5]:


binance_uri = binance_url + binance_endpoints['price'][1] #+ '?symbol=BTCEUR'

web_url = urllib.request.urlopen(binance_uri)
data = web_url.read()
encoding = web_url.info().get_content_charset('utf-8')
JSON_object = json.loads(data.decode(encoding))
df_prices = pd.DataFrame(JSON_object)


# In[6]:


symbols = df_symbols['baseAsset'].unique()


# In[7]:


df_prices['first_symbol'] = np.NaN
for i in range(df_prices['symbol'].apply(len).max()):
    mask = df_prices['symbol'].str[0:i].isin(symbols)
    df_prices.loc[mask, 'first_symbol'] = df_prices[mask]['symbol'].str[0:i]
    
df_prices['second_symbol'] = np.NaN
for i in range(df_prices['symbol'].apply(len).max()):
    mask = df_prices['symbol'].str[-(i+1):].isin(symbols)
    df_prices.loc[mask, 'second_symbol'] = df_prices[mask]['symbol'].str[-(i+1):]
    
df_prices = df_prices.drop(index=df_prices[df_prices['first_symbol'].isna()].index)
df_prices = df_prices.drop(index=df_prices[df_prices['second_symbol'].isna()].index)



# In[25]:


change_matrix_foo = pd.DataFrame(np.identity(len(symbols)), index=symbols, columns=symbols)

for index, row in df_prices.iterrows():
    change_matrix_foo.loc[row['first_symbol'], row['second_symbol']] = row['price']
    
change_matrix_foo = change_matrix_foo.astype('float')


# In[26]:


symbols_lite = ['BTC','ETH','EUR','USDT']
matrix_lite = change_matrix_foo.loc[symbols_lite, symbols_lite].copy()
matrix_lite


# In[38]:


matrix_l = np.tril(matrix_lite.to_numpy().copy())
matrix_l_mask = matrix_l!=0
upper_matrix = np.reciprocal(matrix_l, where=matrix_l_mask).T

matrix_u = np.triu(matrix_lite.to_numpy().copy())
matrix_u_mask = matrix_u!=0
lower_matrix = np.reciprocal(matrix_u, where=matrix_u_mask).T


# In[41]:


print(np.reciprocal(matrix_l, where=matrix_l_mask).T)


# In[40]:


print(upper_matrix)


# In[13]:


print(np.reciprocal(matrix_u, where=matrix_u_mask).T)


# In[14]:


print(lower_matrix)

sys.exit(0)


# In[15]:


np.add(np.reciprocal(matrix_l, where=matrix_l_mask).T, np.reciprocal(matrix_u, where=matrix_u_mask).T)


# ---

# In[16]:


matrix_lite_reciprocal = pd.DataFrame(np.add(upper_matrix, lower_matrix) - np.identity(len(matrix_lite))*2, index=symbols_lite, columns=symbols_lite)
matrix_lite_reciprocal


# In[17]:


matrix_lite = matrix_lite + matrix_lite_reciprocal


# In[18]:


matrix_lite


# ### try arbitrage algorithm

# In[19]:


def compute_API(lambda_max, n):
    return np.abs(lambda_max-n)/(n-1)


# In[20]:


A = matrix_lite.to_numpy()

#####
eigvals, eigvects = np.linalg.eig(A)
idxmax = np.argmax(eigvals)
valmax = eigvals[idxmax]
valapi = compute_API(valmax, len(A))
vecmax = eigvects[:,idxmax]
print(idxmax, valmax, valapi)
print(vecmax)

if valapi>0:
    print('Arbitrage oportunity detected.')
else:
    print('Arbitrage oportunity no detected.')
    
#####
B = np.fromfunction(lambda i, j: vecmax[i] / vecmax[j], (len(A),len(A)), dtype=int)
C = np.divide(A, B)

######
C_idx_max_i = int(C.argmax()/C.shape[0])
C_idx_max_j = C.argmax()%C.shape[0]
C_idx_min_i = int(C.argmin()/C.shape[0])
C_idx_min_j = C.argmin()%C.shape[0]

overvalued_idx = C_idx_max_i, C_idx_max_j
undervalued_idx = C_idx_min_i, C_idx_min_j
overvalued_val = C[overvalued_idx]
undervalued_val = C[undervalued_idx]

bridge_idx = C_idx_min_j, C_idx_max_j
base_currency_idx = C_idx_min_j, C_idx_min_j
bridge_val = C[bridge_idx]

######
print('Arbitrage orders:')
print(f'BUY  foreign currency EUR/YEN in Frankfurt(EUR):  1 / {A[C_idx_max_i,C_idx_min_j]:.4} = x YEN')
print(f'SELL foreign currency YEN/USDT in New York(USDT): x * {A[C_idx_max_i, C_idx_max_j]:.4} = y USDT')
print(f'BUY  foreign currency UDST/EUR in New York(USDT): y / {A[C_idx_min_j, C_idx_max_j]:.4} = z EUR')
z = 1/A[C_idx_max_i,C_idx_min_j] * A[C_idx_max_i, C_idx_max_j] / A[C_idx_min_j, C_idx_max_j]
print(f'There is a increase of {z-1:.3%}')


# In[21]:


(C_idx_max_i+1, C_idx_max_j+1), (C_idx_min_i+1, C_idx_min_j+1)


# In[ ]:




