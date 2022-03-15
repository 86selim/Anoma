//! A tx to initialize a new validator account and staking reward account with a
//! given public keys and a validity predicates.

use anoma_tx_prelude::transaction::InitValidator;
use anoma_tx_prelude::*;

#[transaction]
fn apply_tx(tx_data: Vec<u8>) {
    let signed = SignedTxData::try_from_slice(&tx_data[..]).unwrap();
    let init_validator =
        InitValidator::try_from_slice(&signed.data.unwrap()[..]).unwrap();
    debug_log!("apply_tx called to init a new validator account");

    // Register the validator in PoS
    match proof_of_stake::init_validator(init_validator) {
        Ok((validator_address, staking_reward_address)) => {
            debug_log!(
                "Created validator {} and staking reward account {}",
                validator_address.encode(),
                staking_reward_address.encode()
            )
        }
        Err(err) => {
            debug_log!("Validator creation failed with: {}", err);
            panic!()
        }
    }
}
