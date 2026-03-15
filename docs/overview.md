# Overview

NFT Strategy Token Hook is a Uniswap v4 hook + strategy vault system for deterministic NFT accumulation from bounded swap flow capture.

Core narrative:
1. Swaps occur in v4 pool.
2. Hook captures configured share into strategy vault.
3. Vault reserves revenue and buys deterministic NFTs once threshold is met.
4. Users hold strategy share token for fungible claim path.
