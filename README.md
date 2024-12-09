# Decentralized Stablecoin Project

## Summary
A decentralized, algorithmic stablecoin implementation built using Foundry. This stablecoin is pegged to USD and backed by cryptocurrency collateral (wETH and wBTC), ensuring decentralized price stability through smart contract mechanisms.

## Project Overview
This project implements a stablecoin with the following key features:

### 1. Price Stability
- Pegged 1:1 to USD using Chainlink price feeds
- Maintains stability through algorithmic mechanisms
- Real-time price conversion for ETH/BTC to USD

### 2. Collateralization
- Exogenous crypto collateral using:
  - Wrapped Ethereum (wETH)
  - Wrapped Bitcoin (wBTC)
- Over-collateralization to ensure stability
- Smart contract-enforced minting rules

### 3. Decentralized Minting
- Algorithmic minting mechanism
- Requires sufficient collateral for new coin creation
- Automated collateral validation

## Technical Stack
Built using Foundry, a powerful Ethereum development toolkit that includes:
- **Forge**: Testing framework
- **Cast**: Contract interaction tool
- **Anvil**: Local Ethereum node
- **Chisel**: Solidity REPL

## Getting Started

### Prerequisites
- Install Foundry (https://book.getfoundry.sh/getting-started/installation)
- Clone this repository

### Build and Test
```shell
# Build the project
forge build

# Run tests
forge test

# Format code
forge fmt

# Generate gas snapshots
forge snapshot
```

### Local Development
```shell
# Start local node
anvil

# Deploy to local network
forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Helpful Commands
```shell
# Get help
forge --help
anvil --help
cast --help
```

## Documentation
For more detailed information about Foundry, visit: https://book.getfoundry.sh/
