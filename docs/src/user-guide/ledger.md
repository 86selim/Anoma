# The Anoma Ledger

To start a local Anoma ledger node, run:

```shell
anoma ledger
```

The node will attempt to connect to the persistent validator nodes and other peers in the network and synchronize to the latest block.

By default, the ledger will store its configuration and state in the `.anoma` directory relative to the current working directory. You can use `--base-dir` CLI global argument or `ANOMA_BASE_DIR` environment variable to change it.

If not found on start up, the ledger will generate a configuration file at `.anoma/config.toml`.

The ledger also needs access to the built WASM files that are used in the genesis block. These files are included in release and shouldn't be modified, otherwise your node will fail with consensus error on the genesis block. By default, these are expected to be in the `wasm` directory, relative to the current working directory. This can also be set with `--wasm-dir` CLI global argument, `ANOMA_WASM_DIR` environment variable or the configuration file.

## 📝Initialize an account

First, let's generate a key in the wallet that we'll use for the account.

```shell
anoma wallet key gen --alias my-key
```

Then send a transaction to initialize the account and save its address with alias `my-new-acc`. The `my-key` public key will be written into the account's storage for authorizing future transactions. We also sign this transaction with `my-key`.

```shell
anoma client init-account \
  --alias my-new-acc \
  --public-key my-key \
  --source my-key
```

Once this transaction has been applied, the client will automatically see the new address created by the transaction and add it to your [wallet](./wallet.md) with the chosen alias `my-new-acc`.

By default, this command will use the prebuilt user validity predicate (from the [vp_user](https://github.com/anoma/anoma/blob/fb445f67ffe3afe3bf50eb71658b01ff760e909d/wasm/wasm_source/src/vp_user.rs) source). You can supply a different validity predicate with `--code-path` argument. We'll come back to this topic and cover how to write and deploy custom validity predicates in the [custom validity predicates section](ledger/customize.md#validity-predicates).

## 💸Token transactions and queries

In Anoma, tokens are implemented as accounts with a token validity predicate. It checks that its total supply is preserved in any transaction that uses this token. Your wallet will be pre-loaded with some token addresses that are initialized in the genesis block.

You can see the tokens addresses known by the client when you query all tokens balances:

```shell
anoma client balance
```

XAN is Anoma's native token. To obtain some tokens in a testnet, there's a special "faucet" account that allows anyone to withdraw up to 1000 of any token that is posses in a single transaction. You can find the address of this account in your wallet. To get some tokens from the faucet account:

```shell
anoma client transfer \
  --source faucet \
  --target my-new-acc \
  --signer my-new-acc
  --token XAN \
  --amount 1000 \
```

Note that because you don't have the key to sign transfer from the faucet account, in the command above we set the `--signer` explicitly to your account's address.

To submit a regular token transfer from your account to `validator-1` address:

```shell
anoma client transfer \
  --source my-new-acc \
  --target validator-1 \
  --token XAN \
  --amount 1000 \
```

This command will attempt to find and use the key of the source address to sign the transaction.

To query token balances for a specific token and/or owner:

```shell
anoma client balance --token XAN --owner my-new-acc
```

Note that for any client command that submits a transaction (`init-account`, `transfer`, `tx`, `update` and [PoS transactions](ledger/pos.md)), you can use the `--dry-run` flag to simulate the transaction being applied in the block, to see what its result would be.
