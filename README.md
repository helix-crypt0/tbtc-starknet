# Setup

## Install Scarb and the Cairo Dev tools
```
curl --proto '=https' --tlsv1.2 -sSf https://sh.starkup.dev | sh
```

## Install Dojo and Starkli
Starkli
```
curl https://get.starkli.sh | sh starkliup
```
Dojo
```
curl -L https://install.dojoengine.org | bash dojoup
```

# Contract Compilation
```
scarb build
```
And source the environment variables
```
source src/.env
```
# Running Tests
```
snforge test
```

# Setting up Environment Variables
In order to use command line tools like starkli to interact with contracts, we need to setup env variables.
Once katana is installed run it in a terminal tab. You should see information for a list of pre-funded
accounts like so:
```
| Account address |  0x127fd5f1fe78a71f8bcd1fec63e3fe2f0486b6ecd5c86a0466c3a21fa5cfcec
| Private key     |  0xc5b2fcab997346f3ea1c00b002ecf6f382c5f9c9659a3894eb783c5320f912
| Public key      |  0x33246ce85ebdc292e6a5c5b4dd51fab2757be34b8ffda847ca6925edf31cb67
```

We want to use this account to interact with our contracts on the command line. Run the following command
```
starkli signer keystore from-key ./keys/katana-0.json
```
Then paste the private key from the pre-funded katana account when prompted.

In your .env file you should have something similar to the following:
```
export STARKNET_ACCOUNT=katana-0        #A pre-funded account on the local development network.
export STARKNET_RPC=http://0.0.0.0:5050 #To specify the network, targeting the local katana devnet.
export STARKNET_KEYSTORE_PATH=./keys/katana-0.json
```

Before running any starkli commands make sure to source your env file in your current terminal tab.

# Deploying to a local network
Run katana in a separate terminal tab
```
katana
```

Then declare the compiled contract. As an example, 
```
starkli declare target/dev/[contract_name].contract_class.json
```

Once the contract is declared you will get a class hash

Example:
```
Declaring Cairo 1 class: 0x01abf3f403b0245368a7bf2c23245ad3532370a62504744cb77a79fc0acbe717
Compiling Sierra class to CASM with compiler version 2.9.4...
CASM class hash: 0x00a3b109389575a420cd0c5ccbd14e9bf2f5b56d50f6085d08202d15ee2b3222
Contract declaration transaction: 0x031e9d82d6a35be4532c107b4ee2b59f795c8ef72aed3dd967f17bb35d7c74d5
Class hash declared:
0x01abf3f403b0245368a7bf2c23245ad3532370a62504744cb77a79fc0acbe717
```

To deploy use the following command with the class hash from above
```
starkli deploy [class-hash]
```

You should see output similar to the following
```

```
## Interacting with the contract
You can now interact with the contract functions that have been deployed
# Deploying to a Testnet

# Troubleshooting
You may run into issues with incompatible Sierra versions. In this case you need to install a specific version
of Cairo on your system. In this case, the katana version on my system required a sierra version of 1.6.0, but
the openzeppelin contracts require Cairo 2.9.4

In this case, you can use asdf and install and set the version with the following
```
asdf install scarb 2.9.4 && asdf set scarb 2.9.4
```


