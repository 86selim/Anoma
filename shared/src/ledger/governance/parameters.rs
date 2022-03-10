use borsh::{BorshDeserialize, BorshSerialize};

use super::storage as gov_storage;
use crate::ledger::storage::types::encode;
use crate::ledger::storage::{self, Storage};
use crate::types::token::Amount;

#[derive(
    Clone,
    Debug,
    PartialEq,
    Eq,
    PartialOrd,
    Ord,
    Hash,
    BorshSerialize,
    BorshDeserialize,
)]
/// Governance parameter structure
pub struct GovParams {
    /// Minimum amount of locked funds
    pub min_proposal_fund: u64,
    /// Maximum kilobyte length for proposal code
    pub max_proposal_code_size: u64,
    /// Minimum proposal voting period in epochs
    pub min_proposal_period: u64,
    /// Maximimum number of characters for proposal content
    pub max_proposal_content: u64,
}

impl Default for GovParams {
    fn default() -> Self {
        Self {
            min_proposal_fund: 500,
            max_proposal_code_size: 500,
            min_proposal_period: 3,
            max_proposal_content: 10000,
        }
    }
}

impl GovParams {
    /// Initialize governance parameters into storage
    pub fn init_storage<DB, H>(&self, storage: &mut Storage<DB, H>)
    where
        DB: storage::DB + for<'iter> storage::DBIter<'iter>,
        H: storage::StorageHasher,
    {
        let min_proposal_fund_key = gov_storage::get_min_proposal_fund_key();
        let amount = Amount::whole(self.min_proposal_fund);
        println!("Amount: {}, {}", amount, self.min_proposal_fund);
        storage
            .write(&min_proposal_fund_key, encode(&amount))
            .unwrap();

        let max_proposal_code_size_key =
            gov_storage::get_max_proposal_code_size_key();
        storage
            .write(
                &max_proposal_code_size_key,
                encode(&self.max_proposal_code_size),
            )
            .unwrap();

        let min_proposal_period_key =
            gov_storage::get_min_proposal_period_key();
        storage
            .write(&min_proposal_period_key, encode(&self.min_proposal_period))
            .unwrap();

        let max_proposal_content_key =
            gov_storage::get_max_proposal_content_key();
        storage
            .write(
                &max_proposal_content_key,
                encode(&self.max_proposal_content),
            )
            .unwrap();

        let counter_key = gov_storage::get_counter_key();
        storage.write(&counter_key, encode(&u64::MIN)).unwrap();
    }
}
