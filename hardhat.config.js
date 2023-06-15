/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  networks: {
    // goerli: {
    //   gas: "auto",
    //   gasPrice: "auto",
    //   url: 'https://goerli.infura.io/v3/f92e5c4c343f48d7a98e62a2443a6956'
    // },
  },
  solidity: {
    version: '0.8.18',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
};
