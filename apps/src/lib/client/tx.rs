use std::borrow::Cow;
use std::convert::TryFrom;

use anoma::proto::Tx;
use anoma::types::address::Address;
use anoma::types::key::ed25519::Keypair;
use anoma::types::token;
use anoma::types::transaction::{pos, Fee, InitAccount, UpdateVp, WrapperTx};
use async_std::io::{self, WriteExt};
use borsh::BorshSerialize;
use jsonpath_lib as jsonpath;
use serde::Serialize;
use tendermint_rpc::query::{EventType, Query};
use tendermint_rpc::Client;

use super::{rpc, signing};
use crate::cli::args::SigningMethod;
use crate::cli::{args, safe_exit, Context};
use crate::client::tendermint_websocket_client::{
    hash_tx, Error, TendermintWebsocketClient, WebSocketAddress,
};
use crate::node::ledger::events::{Attributes, EventType as TmEventType};


const TX_INIT_ACCOUNT_WASM: &str = "wasm/tx_init_account.wasm";
const TX_UPDATE_VP_WASM: &str = "wasm/tx_update_vp.wasm";
const TX_TRANSFER_WASM: &str = "wasm/tx_transfer.wasm";
const VP_USER_WASM: &str = "wasm/vp_user.wasm";
const TX_BOND_WASM: &str = "wasm/tx_bond.wasm";
const TX_UNBOND_WASM: &str = "wasm/tx_unbond.wasm";
const TX_WITHDRAW_WASM: &str = "wasm/tx_withdraw.wasm";

pub async fn submit_custom(mut ctx: Context, args: args::TxCustom) {
    let tx_code = std::fs::read(args.code_path)
        .expect("Expected a file at given code path");
    let data = args.data_path.map(|data_path| {
        std::fs::read(data_path).expect("Expected a file at given data path")
    });
    let keypair = match args.signing_method {
        SigningMethod::SigningKey(signing_key) => ctx.get_cached(signing_key),
        SigningMethod::Signer(signer) => {
            let signer = ctx.get(signer);
            signing::find_keypair(
                &mut ctx.wallet,
                &signer,
                args.tx.ledger_address.clone(),
            )
            .await
        }
    };
    let tx = Tx::new(tx_code, data);
    submit_tx(ctx, args.tx, tx, &keypair).await
}

pub async fn submit_update_vp(mut ctx: Context, args: args::TxUpdateVp) {
    let source = ctx.get(args.addr);
    let keypair = signing::find_keypair(
        &mut ctx.wallet,
        &source,
        args.tx.ledger_address.clone(),
    )
    .await;

    let vp_code = std::fs::read(args.vp_code_path)
        .expect("Expected a file at given code path");
    let tx_code = std::fs::read(TX_UPDATE_VP_WASM)
        .expect("Expected a file at given code path");

    let update_vp = UpdateVp {
        addr: source,
        vp_code,
    };
    let data = update_vp.try_to_vec().expect(
        "Encoding transfer data to update a validity predicate shouldn't fail",
    );
    let tx = Tx::new(tx_code, Some(data)).sign(&keypair);

    submit_tx(ctx, args.tx, tx, &keypair).await
}

pub async fn submit_init_account(mut ctx: Context, args: args::TxInitAccount) {
    let source = ctx.get(args.source);
    let keypair = signing::find_keypair(
        &mut ctx.wallet,
        &source,
        args.tx.ledger_address.clone(),
    )
    .await;
    let public_key = ctx.get_cached(args.public_key);
    let vp_code = args
        .vp_code_path
        .map(|path| {
            std::fs::read(path).expect("Expected a file at given code path")
        })
        .unwrap_or_else(|| {
            std::fs::read(VP_USER_WASM)
                .expect("Expected a file at given code path")
        });
    let tx_code = std::fs::read(TX_INIT_ACCOUNT_WASM)
        .expect("Expected a file at given code path");

    let data = InitAccount {
        public_key,
        vp_code,
    };
    let data = data.try_to_vec().expect(
        "Encoding transfer data to initialize a new account shouldn't fail",
    );
    let tx = Tx::new(tx_code, Some(data));

    submit_tx(ctx, args.tx, tx, &keypair).await
}

pub async fn submit_transfer(mut ctx: Context, args: args::TxTransfer) {
    let source = ctx.get(args.source);
    let target = ctx.get(args.target);
    let token = ctx.get(args.token);
    let keypair = signing::find_keypair(
        &mut ctx.wallet,
        &source,
        args.tx.ledger_address.clone(),
    )
    .await;

    let tx_code = std::fs::read(TX_TRANSFER_WASM).unwrap();
    let transfer = token::Transfer {
        source,
        target,
        token,
        amount: args.amount,
    };
    tracing::debug!("Transfer data {:?}", transfer);
    let data = transfer
        .try_to_vec()
        .expect("Encoding unsigned transfer shouldn't fail");
    let tx = Tx::new(tx_code, Some(data)).sign(&keypair);

    submit_tx(ctx, args.tx, tx, &keypair).await
}

pub async fn submit_bond(mut ctx: Context, args: args::Bond) {
    let validator = ctx.get(args.validator);
    let source = ctx.get_opt(args.source);
    let signer = source.as_ref().unwrap_or(&validator);
    let keypair = signing::find_keypair(
        &mut ctx.wallet,
        signer,
        args.tx.ledger_address.clone(),
    )
    .await;
    let tx_code = std::fs::read(TX_BOND_WASM).unwrap();

    let bond = pos::Bond {
        validator,
        amount: args.amount,
        source,
    };
    tracing::debug!("Bond data {:?}", bond);
    let data = bond.try_to_vec().expect("Encoding tx data shouldn't fail");
    let tx = Tx::new(tx_code, Some(data));

    submit_tx(ctx, args.tx, tx, &keypair).await
}

pub async fn submit_unbond(mut ctx: Context, args: args::Unbond) {
    let validator = ctx.get(args.validator);
    let source = ctx.get_opt(args.source);
    let signer = source.as_ref().unwrap_or(&validator);
    let keypair = signing::find_keypair(
        &mut ctx.wallet,
        signer,
        args.tx.ledger_address.clone(),
    )
    .await;
    let tx_code = std::fs::read(TX_UNBOND_WASM).unwrap();

    let unbond = pos::Unbond {
        validator,
        amount: args.amount,
        source,
    };
    tracing::debug!("Unbond data {:?}", unbond);
    let data = unbond
        .try_to_vec()
        .expect("Encoding tx data shouldn't fail");
    let tx = Tx::new(tx_code, Some(data));

    submit_tx(ctx, args.tx, tx, &keypair).await
}

pub async fn submit_withdraw(mut ctx: Context, args: args::Withdraw) {
    let validator = ctx.get(args.validator);
    let source = ctx.get_opt(args.source);
    let signer = source.as_ref().unwrap_or(&validator);
    let keypair = signing::find_keypair(
        &mut ctx.wallet,
        signer,
        args.tx.ledger_address.clone(),
    )
    .await;
    let tx_code = std::fs::read(TX_WITHDRAW_WASM).unwrap();

    let withdraw = pos::Withdraw { validator, source };
    tracing::debug!("Withdraw data {:?}", withdraw);
    let data = withdraw
        .try_to_vec()
        .expect("Encoding tx data shouldn't fail");
    let tx = Tx::new(tx_code, Some(data));

    submit_tx(ctx, args.tx, tx, &keypair).await
}

async fn submit_tx(ctx: Context, args: args::Tx, tx: Tx, keypair: &Keypair) {
    let tx = WrapperTx::new(
        Fee {
            amount: args.fee_amount,
            token: ctx.get(args.fee_token),
        },
        keypair,
        rpc::query_epoch(args::Query {
            ledger_address: args.ledger_address.clone(),
        })
        .await
        .expect(
            "Getting the epoch of the last committed block should not fail",
        ),
        args.gas_limit,
        tx,
    );

    // NOTE: use this to print the request JSON body:
    // let request =
    // tendermint_rpc::endpoint::broadcast::tx_commit::Request::new(
    //     tx_bytes.clone().into(),
    // );
    // use tendermint_rpc::Request;
    // let request_body = request.into_json();
    // println!("HTTP request body: {}", request_body);

    if args.dry_run {
        rpc::dry_run_tx(&args.ledger_address, tx.sign(&keypair).unwrap().to_bytes()).await
    } else {
        match broadcast_tx(args.ledger_address.clone(), tx, keypair).await {
            Ok(result) => {
                save_initialized_accounts(
                    ctx,
                    args.initialized_account_alias,
                    result,
                )
                .await;
            }
            Err(err) => {
                eprintln!(
                    "Encountered error while broadcasting transaction: {}",
                    err
                );
                safe_exit(1)
            }
        }
    }
}

/// Save accounts initialized from a tx into the wallet, if any.
async fn save_initialized_accounts(
    ctx: Context,
    initialized_account_alias: Option<String>,
    result: TxResponse,
) {
    let len = result.initialized_accounts.len();
    if len != 0 {
        // Store newly initialized account addresses in the wallet
        println!(
            "The transaction initialized {} new account{}",
            len,
            if len == 1 { "" } else { "s" }
        );
        // Store newly initialized account addresses in the wallet
        let mut wallet = ctx.wallet;
        for (ix, address) in result.initialized_accounts.iter().enumerate() {
            let encoded = address.encode();
            let mut added = false;
            while !added {
                let alias: Cow<str> = match &initialized_account_alias {
                    Some(initialized_account_alias) => {
                        if len == 1 {
                            // If there's only one account, use the
                            // alias as is
                            initialized_account_alias.into()
                        } else {
                            // If there're multiple accounts, use
                            // the alias as prefix, followed by
                            // index number
                            format!("{}{}", initialized_account_alias, ix)
                                .into()
                        }
                    }
                    None => {
                        print!("Choose an alias for {}: ", encoded);
                        io::stdout().flush().await.unwrap();
                        let mut alias = String::new();
                        io::stdin().read_line(&mut alias).await.unwrap();
                        alias.trim().to_owned().into()
                    }
                };
                added = if alias.is_empty() {
                    println!(
                        "Empty alias given, using {} as the alias.",
                        encoded
                    );
                    wallet.add_address(encoded.clone(), address.clone())
                } else {
                    let alias = alias.into_owned();
                    let added =
                        wallet.add_address(alias.clone(), address.clone());
                    if added {
                        println!(
                            "Added alias {} for address {}.",
                            alias, encoded
                        );
                    }
                    added
                }
            }
        }
        wallet.save().unwrap_or_else(|err| eprintln!("{}", err));
    }
}

/// Broadcast a transaction to be included in the blockchain.
///
/// Checks that
/// 1. The tx has been successfully included into the mempool of a validator
/// 2. The tx with encrypted payload has been included on the blockchain
/// 3. The decrypted payload of the tx has been included on the blockchain.
///
/// In the case of errors in any of those stages, an error message is returned
pub async fn broadcast_tx(
    address: tendermint::net::Address,
    tx: WrapperTx,
    keypair: &Keypair,
) -> Result<TxResponse, Error> {
    // We use this to determine when the wrapper tx makes it on-chain
    let wrapper_tx_hash = hash_tx(&tx.try_to_vec().unwrap()).to_string();
    // We use this to determine when the decrypted inner tx makes it on-chain
    let decrypted_tx_hash = tx.tx_hash.to_string();
    // we sign all txs
    let tx = tx.sign(keypair).expect("Signing of the wrapper transaction should not fail");
    let tx_bytes = tx.to_bytes();

    let mut wrapper_tx_subscription =
        TendermintWebsocketClient::open(WebSocketAddress::try_from(address.clone())?)?;
    let mut decrypted_tx_subscription =
        TendermintWebsocketClient::open(WebSocketAddress::try_from(address)?)?;
    // It is better to subscribe to the transaction before it is broadcast
    //
    // Note that the `applied.hash` key comes from a custom event
    // created by the shell
    let query = Query::from(EventType::NewBlock)
        .and_eq("accepted.hash", wrapper_tx_hash.as_str());
    wrapper_tx_subscription.subscribe(query)?;
    let query = Query::from(EventType::NewBlock)
        .and_eq("applied.hash", decrypted_tx_hash.as_str());
    decrypted_tx_subscription.subscribe(query)?;

    let response = wrapper_tx_subscription
        .broadcast_tx_sync(tx_bytes.into())
        .await
        .map_err(|err| Error::Response(format!("{:?}", err)))?;

    let parsed = if response.code == 0.into() {
        println!("Transaction added to mempool: {:?}", response);
        let parsed = parse(
            wrapper_tx_subscription.receive_response()?,
            TmEventType::Accepted,
            &wrapper_tx_hash.to_string(),
        );
        println!(
            "Transaction accepted with result: {}",
            serde_json::to_string_pretty(&parsed).unwrap()
        );

        // The transaction is now on chain. We wait for it to be decrypted and
        // applied
        if parsed.code == 0.to_string() {
            let parsed = parse(
                decrypted_tx_subscription.receive_response()?,
                TmEventType::Applied,
                &decrypted_tx_hash,
            );
            println!(
                "Transaction applied with result: {}",
                serde_json::to_string_pretty(&parsed).unwrap()
            );
            Ok(parsed)
        } else {
            Ok(parsed)
        }
    } else {
        Err(Error::Response(response.log.to_string()))
    };
    wrapper_tx_subscription.unsubscribe()?;
    wrapper_tx_subscription.close();
    decrypted_tx_subscription.unsubscribe()?;
    decrypted_tx_subscription.close();
    parsed
}

#[derive(Debug, Serialize)]
pub struct TxResponse {
    info: String,
    height: String,
    hash: String,
    code: String,
    gas_used: String,
    initialized_accounts: Vec<Address>,
}

/// Parse the JSON payload recieved from a subscription
///
/// Searches for custom events emitted from the ledger and converts
/// them back to thin wrapper around a hashmap for further parsing.
fn parse(json: serde_json::Value, event_type: TmEventType, tx_hash: &String) -> TxResponse {
    let mut selector = jsonpath::selector(&json);
    let mut event = selector(&format!(
        "$.events.[?(@.type=='{}')]",
        event_type.to_string()
    ))
    .unwrap()
    .iter()
    .filter_map(|event| {
        let attrs = Attributes::from(*event);
        match attrs.get("hash") {
            Some(hash) if hash == tx_hash => {
                Some(attrs)
            }
            _ => None
        }
    })
    .collect::<Vec::<Attributes>>()
    .remove(0);

    let info = event.take("info").unwrap();
    let height = event.take("height").unwrap();
    let hash = event.take("hash").unwrap();
    let code = event.take("code").unwrap();
    let gas_used= event.take("gas_used").unwrap();
    let initialized_accounts = event.take("initialized_accounts");
    let initialized_accounts = match initialized_accounts {
        Some(values) => {
            serde_json::from_str(&values).unwrap()
        }
        _ => vec![],
    };
    TxResponse {
        info,
        height,
        hash,
        code,
        gas_used,
        initialized_accounts,
    }
}

