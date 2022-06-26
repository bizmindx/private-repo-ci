# To properly run on local host the testing fe network.

In one terminal

```
npx hardhat node --fork https://eth-mainnet.alchemyapi.io/v2/_BQD0Esx8ZAKb9KAB-0yX40UzodFYCmn
```

In another terminal

```
npx hardhat run scripts/fe_deploy.js --network localhost
```
