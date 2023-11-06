# Ebtc Zap Router
Route between different zaps and functionality.

## Key Functions
* One-click Leverage: use flash loans via leverage macro to lever loop in one action
* Flippening: a wrapper on leverage where you sell the final eBTC for more stETH (lever long ETH)
* Native ETH: Deposit from native ETH and auto-wrap into stETH
* ETH Variants deposits: come from WETH and wstETH as well for convenience

## User stories
- User starts from ETH, stETH, wstETH, WETH
- Use applies leverage or not
- User swaps their final eBTC debt for stETH or not

## Usage

### Install
Install Foundry and complete yarn install in dependency eBTC repo.
```shell
$ forge install
$ cd lib/ebtc 
$ yarn
$ cd ../../
```

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

