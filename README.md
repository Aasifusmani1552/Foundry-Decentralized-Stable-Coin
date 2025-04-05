# Decentralized Stable Coin (DSC)

This project implements a **Decentralized Stable Coin (DSC)** system inspired by the principles of decentralized finance (DeFi). It features a 1:1 dollar-pegged stablecoin backed by exogenous collateral and stabilized algorithmically.

## 🧾 Overview

The **Decentralized Stable Coin (DSC)** is designed to maintain price stability through a combination of:
- **Exogenous Collateralization** – accepts external assets like WETH and WBTC as collateral
- **Algorithmic Stability** – managed through a smart contract system called `DSCEngine`
- **1:1 USD Peg** – the value of one DSC is intended to remain as close as possible to 1 USD

## ⚙️ How It Works

1. **Collateral Deposit**: Users deposit accepted collateral (WETH or WBTC) into the protocol.
2. **Minting DSC**: Based on the deposited collateral, users can mint DSC up to a safe collateralization ratio.
3. **Stability Mechanism**:
   - The `DSCEngine` continuously monitors the **health factor** of all users.
   - A health factor below `1` indicates an undercollateralized position.
   - While the protocol itself **does not automatically liquidate**, **any external user** can call the `liquidate()` function on an undercollateralized position.
   - The liquidator repays part of the debt and receives collateral at a **10% discount** as an incentive.
4. **Redemption**: Users can burn DSC to retrieve their deposited collateral.

## 🏦 Collateral Types

The protocol currently supports:
- **WETH** (Wrapped Ether)
- **WBTC** (Wrapped Bitcoin)

## 🛡️ Key Properties

- 🔗 **Decentralized**: No central authority governs the issuance or management.
- 💵 **Stable**: Pegged 1:1 with the U.S. Dollar.
- 🪙 **Overcollateralized**: Always backed by more value than the DSC minted.
- 🤖 **Algorithmically Stabilized**: Stability logic is enforced through smart contracts (`DSCEngine`).
- ⚖️ **Community-Driven Liquidation**: Bad debt is resolved by external actors incentivized with a liquidation bonus.
- 🔒 **Secure & Transparent**: Built with smart contracts and verifiable on-chain.

## 🛠️ Contracts

- `DSC.sol`: The stablecoin contract implementing ERC20.
- `DSCEngine.sol`: The core logic for collateral management, minting, redemption, and liquidations.

## 📄 License

This project is open-source and available under the MIT License.
