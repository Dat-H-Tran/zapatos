/**
 * Validator lifecycle:
 * 1. Prepare a validator node set up and call stake::initialize_validator
 * 2. Once ready to deposit stake (or have funds assigned by a staking service in exchange for ownership capability),
 * call stake::add_stake (or *_with_cap versions if called from the staking service)
 * 3. Call stake::join_validator_set (or _with_cap version) to join the active validator set. Changes are effective in
 * the next epoch.
 * 4. Validate and gain rewards. The stake will automatically be locked up for a fixed duration (set by governance) and
 * automatically renewed at expiration.
 * 5. At any point, if the validator operator wants to update the consensus key or network/fullnode addresses, they can
 * call stake::rotate_consensus_key and stake::update_network_and_fullnode_addresses. Similar to changes to stake, the
 * changes to consensus key/network/fullnode addresses are only effective in the next epoch.
 * 6. Validator can request to unlock their stake at any time. However, their stake will only become withdrawable when
 * their current lockup expires. This can be at most as long as the fixed lockup duration.
 * 7. After exiting, the validator can either explicitly leave the validator set by calling stake::leave_validator_set
 * or if their stake drops below the min required, they would get removed at the end of the epoch.
 * 8. Validator can always rejoin the validator set by going through steps 2-3 again.
 * 9. An owner can always switch operators by calling stake::set_operator.
 * 10. An owner can always switch designated voter by calling stake::set_designated_voter.
*/
module aptos_framework::validator {
    use std::error;
    // use std::features;
    use std::option::{Self, Option};
    use std::signer;
    use std::vector;
    use aptos_std::bls12381;
    // use aptos_std::math64::min;
    use aptos_std::table::{Self, Table};
    use aptos_std::debug;


    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event::{Self, EventHandle};
    // use aptos_framework::timestamp;
    use aptos_framework::system_addresses;


    friend aptos_framework::block;
    friend aptos_framework::genesis;
    friend aptos_framework::reconfiguration;
    friend aptos_framework::transaction_fee;

    /// Validator Config not published.
    const EVALIDATOR_CONFIG: u64 = 1;
    /// Account is already a validator or pending validator.
    const EALREADY_ACTIVE_VALIDATOR: u64 = 4;
    /// Account is not a validator.
    const ENOT_VALIDATOR: u64 = 5;
    /// Can't remove last validator.
    const ELAST_VALIDATOR: u64 = 6;
    /// Account is already registered as a validator candidate.
    const EALREADY_REGISTERED: u64 = 8;
    /// Account does not have the right operator capability.
    const ENOT_OPERATOR: u64 = 9;
    /// Invalid consensus public key
    const EINVALID_PUBLIC_KEY: u64 = 11;
    /// Validator set exceeds the limit
    const EVALIDATOR_SET_TOO_LARGE: u64 = 12;
    /// Stake pool does not exist at the provided pool address.
    const ESTAKE_POOL_DOES_NOT_EXIST: u64 = 14;

    /// Table to store collected transaction fees for each validator already exists.
    const EFEES_TABLE_ALREADY_EXISTS: u64 = 19;

    /// Validator status enum. We can switch to proper enum later once Move supports it.
    const VALIDATOR_STATUS_PENDING_ACTIVE: u64 = 1;
    const VALIDATOR_STATUS_ACTIVE: u64 = 2;
    const VALIDATOR_STATUS_PENDING_INACTIVE: u64 = 3;
    const VALIDATOR_STATUS_INACTIVE: u64 = 4;

    /// Limit the maximum size to u16::max, it's the current limit of the bitvec
    /// https://github.com/aptos-labs/aptos-core/blob/main/crates/aptos-bitvec/src/lib.rs#L20
    const MAX_VALIDATOR_SET_SIZE: u64 = 65536;

    /// max value of u64
    const MAX_U64: u128 = 18446744073709551615;


    /// Each validator has a separate StakePool resource and can provide a stake.
    /// Changes in stake for an active validator:
    /// 1. If a validator calls add_stake, the newly added stake is moved to pending_active.
    /// 2. If validator calls unlock, their stake is moved to pending_inactive.
    /// 2. When the next epoch starts, any pending_inactive stake is moved to inactive and can be withdrawn.
    ///    Any pending_active stake is moved to active and adds to the validator's voting power.
    ///
    /// Changes in stake for an inactive validator:
    /// 1. If a validator calls add_stake, the newly added stake is moved directly to active.
    /// 2. If validator calls unlock, their stake is moved directly to inactive.
    /// 3. When the next epoch starts, the validator can be activated if their active stake is more than the minimum.
    struct StakePool has key {
        // Only the account holding OwnerCapability of the staking pool can update this.
        operator_address: address,
        // The events emitted for the entire StakePool's lifecycle.
        initialize_validator_events: EventHandle<RegisterValidatorCandidateEvent>,
        set_operator_events: EventHandle<SetOperatorEvent>,
        rotate_consensus_key_events: EventHandle<RotateConsensusKeyEvent>,
        update_network_and_fullnode_addresses_events: EventHandle<UpdateNetworkAndFullnodeAddressesEvent>,
        join_validator_set_events: EventHandle<JoinValidatorSetEvent>,
        distribute_rewards_events: EventHandle<DistributeRewardsEvent>,
        leave_validator_set_events: EventHandle<LeaveValidatorSetEvent>,
    }

    /// Validator info stored in validator address.
    struct ValidatorConfig has key, copy, store, drop {
        consensus_pubkey: vector<u8>,
        network_addresses: vector<u8>,
        // to make it compatible with previous definition, remove later
        fullnode_addresses: vector<u8>,
        // Index in the active set if the validator corresponding to this stake pool is active.
        validator_index: u64,
    }

    /// Consensus information per validator, stored in ValidatorSet.
    struct ValidatorInfo has copy, store, drop {
        addr: address,
        // voting_power: u64, // TODO: V7: voting power is the same for all.
        config: ValidatorConfig,
    }

    /// Full ValidatorSet, stored in @aptos_framework.
    /// 1. join_validator_set adds to pending_active queue.
    /// 2. leave_valdiator_set moves from active to pending_inactive queue.
    /// 3. on_new_epoch processes two pending queues and refresh ValidatorInfo from the owner's address.
    struct ValidatorSet has key {
        consensus_scheme: u8,
        // Active validators for the current epoch.
        active_validators: vector<ValidatorInfo>,
        // Pending validators to leave in next epoch (still active).
        pending_inactive: vector<ValidatorInfo>,
        // Pending validators to join in next epoch.
        pending_active: vector<ValidatorInfo>,
        // Current total voting power.
        // total_voting_power: u128,
        // Total voting power waiting to join in the next epoch.
        // total_joining_power: u128,
    }

    struct ValidatorUniverse has key {
      all_vals: vector<address>
    }

    struct IndividualValidatorPerformance has store, drop {
        successful_proposals: u64,
        failed_proposals: u64,
    }

    struct ValidatorPerformance has key {
        validators: vector<IndividualValidatorPerformance>,
    }

    struct RegisterValidatorCandidateEvent has drop, store {
        pool_address: address,
    }

    struct SetOperatorEvent has drop, store {
        pool_address: address,
        old_operator: address,
        new_operator: address,
    }

    struct RotateConsensusKeyEvent has drop, store {
        pool_address: address,
        old_consensus_pubkey: vector<u8>,
        new_consensus_pubkey: vector<u8>,
    }

    struct UpdateNetworkAndFullnodeAddressesEvent has drop, store {
        pool_address: address,
        old_network_addresses: vector<u8>,
        new_network_addresses: vector<u8>,
        old_fullnode_addresses: vector<u8>,
        new_fullnode_addresses: vector<u8>,
    }

    struct JoinValidatorSetEvent has drop, store {
        pool_address: address,
    }

    struct DistributeRewardsEvent has drop, store {
        pool_address: address,
        rewards_amount: u64,
    }

    struct LeaveValidatorSetEvent has drop, store {
        pool_address: address,
    }

    /// Stores transaction fees assigned to validators. All fees are distributed to validators
    /// at the end of the epoch.
    struct ValidatorFees has key {
        fees_table: Table<address, Coin<AptosCoin>>,
    }

    /// Initializes the resource storing information about collected transaction fees per validator.
    /// Used by `transaction_fee.move` to initialize fee collection and distribution.
    public(friend) fun initialize_validator_fees(aptos_framework: &signer) {
        system_addresses::assert_aptos_framework(aptos_framework);
        assert!(
            !exists<ValidatorFees>(@aptos_framework),
            error::already_exists(EFEES_TABLE_ALREADY_EXISTS)
        );
        move_to(aptos_framework, ValidatorFees { fees_table: table::new() });
        move_to(
            aptos_framework,
            ValidatorUniverse {
                all_vals: vector::empty(),
            },
        );
    }

    /// Stores the transaction fee collected to the specified validator address.
    public(friend) fun add_transaction_fee(validator_addr: address, fee: Coin<AptosCoin>) acquires ValidatorFees {
        let fees_table = &mut borrow_global_mut<ValidatorFees>(@aptos_framework).fees_table;
        if (table::contains(fees_table, validator_addr)) {
            let collected_fee = table::borrow_mut(fees_table, validator_addr);
            coin::merge(collected_fee, fee);
        } else {
            table::add(fees_table, validator_addr, fee);
        }
    }


    #[view]
    /// Returns the validator's state.
    public fun get_validator_state(pool_address: address): u64 acquires ValidatorSet {
        let validator_set = borrow_global<ValidatorSet>(@aptos_framework);
        if (option::is_some(&find_validator(&validator_set.pending_active, pool_address))) {
            VALIDATOR_STATUS_PENDING_ACTIVE
        } else if (option::is_some(&find_validator(&validator_set.active_validators, pool_address))) {
            VALIDATOR_STATUS_ACTIVE
        } else if (option::is_some(&find_validator(&validator_set.pending_inactive, pool_address))) {
            VALIDATOR_STATUS_PENDING_INACTIVE
        } else {
            VALIDATOR_STATUS_INACTIVE
        }
    }

    #[view]
    /// Return the operator of the validator at `pool_address`.
    public fun get_operator(pool_address: address): address acquires StakePool {
        assert_stake_pool_exists(pool_address);
        borrow_global<StakePool>(pool_address).operator_address
    }

    #[view]
    /// Return the validator index for `pool_address`.
    public fun get_validator_index(pool_address: address): u64 acquires ValidatorConfig {
        assert_stake_pool_exists(pool_address);
        borrow_global<ValidatorConfig>(pool_address).validator_index
    }

    #[view]
    /// Return the number of successful and failed proposals for the proposal at the given validator index.
    public fun get_current_epoch_proposal_counts(validator_index: u64): (u64, u64) acquires ValidatorPerformance {
        let validator_performances = &borrow_global<ValidatorPerformance>(@aptos_framework).validators;
        let validator_performance = vector::borrow(validator_performances, validator_index);
        (validator_performance.successful_proposals, validator_performance.failed_proposals)
    }

    #[view]
    /// Return the validator's config.
    public fun get_validator_config(pool_address: address): (vector<u8>, vector<u8>, vector<u8>) acquires ValidatorConfig {
        assert_stake_pool_exists(pool_address);
        let validator_config = borrow_global<ValidatorConfig>(pool_address);
        (validator_config.consensus_pubkey, validator_config.network_addresses, validator_config.fullnode_addresses)
    }

    #[view]
    public fun stake_pool_exists(addr: address): bool {
        exists<StakePool>(addr)
    }

    /// Initialize validator set to the core resource account.
    public(friend) fun initialize(aptos_framework: &signer) {
        system_addresses::assert_aptos_framework(aptos_framework);

        move_to(aptos_framework, ValidatorSet {
            consensus_scheme: 0,
            active_validators: vector::empty(),
            pending_active: vector::empty(),
            pending_inactive: vector::empty(),
            // total_voting_power: 0,
            // total_joining_power: 0,
        });

        move_to(aptos_framework, ValidatorPerformance {
            validators: vector::empty(),
        });
    }

        /// Initialize the validator account and give ownership to the signing account
    /// except it leaves the ValidatorConfig to be set by another entity.
    /// Note: this triggers setting the operator and owner, set it to the account's address
    /// to set later.
    public entry fun initialize_stake_owner(
        owner: &signer,
        _initial_stake_amount: u64,
        operator: address,
        _voter: address,
    ) acquires StakePool {
        debug::print(&2000);
        initialize_owner(owner);
        move_to(owner, ValidatorConfig {
            consensus_pubkey: vector::empty(),
            network_addresses: vector::empty(),
            fullnode_addresses: vector::empty(),
            validator_index: 0,
        });

        // if (initial_stake_amount > 0) {
        //     add_stake(owner, initial_stake_amount);
        // };

        let account_address = signer::address_of(owner);
        if (account_address != operator) {
            set_operator(owner, operator)
        };
        // if (account_address != voter) {
        //     set_delegated_voter(owner, voter)
        // };
    }



    /// Initialize the validator account and give ownership to the signing account.
    public entry fun initialize_validator(
        account: &signer,
        consensus_pubkey: vector<u8>,
        proof_of_possession: vector<u8>,
        network_addresses: vector<u8>,
        fullnode_addresses: vector<u8>,
    )  {
        // Checks the public key has a valid proof-of-possession to prevent rogue-key attacks.
        let pubkey_from_pop = &mut bls12381::public_key_from_bytes_with_pop(
            consensus_pubkey,
            &bls12381::proof_of_possession_from_bytes(proof_of_possession)
        );
        assert!(option::is_some(pubkey_from_pop), error::invalid_argument(EINVALID_PUBLIC_KEY));

        initialize_owner(account);
        move_to(account, ValidatorConfig {
            consensus_pubkey,
            network_addresses,
            fullnode_addresses,
            validator_index: 0,
        });
    }

    fun initialize_owner(owner: &signer) {
        debug::print(&2001);

        let owner_address = signer::address_of(owner);
        // assert!(is_allowed(owner_address), error::not_found(EINELIGIBLE_VALIDATOR));
        assert!(!stake_pool_exists(owner_address), error::already_exists(EALREADY_REGISTERED));

        move_to(owner, StakePool {
            // active: coin::zero<AptosCoin>(),
            // pending_active: coin::zero<AptosCoin>(),
            // pending_inactive: coin::zero<AptosCoin>(),
            // inactive: coin::zero<AptosCoin>(),
            // locked_until_secs: 0,
            operator_address: owner_address,
            // delegated_voter: owner_address,
            // Events.
            initialize_validator_events: account::new_event_handle<RegisterValidatorCandidateEvent>(owner),
            set_operator_events: account::new_event_handle<SetOperatorEvent>(owner),
            // add_stake_events: account::new_event_handle<AddStakeEvent>(owner),
            // reactivate_stake_events: account::new_event_handle<ReactivateStakeEvent>(owner),
            rotate_consensus_key_events: account::new_event_handle<RotateConsensusKeyEvent>(owner),
            update_network_and_fullnode_addresses_events: account::new_event_handle<UpdateNetworkAndFullnodeAddressesEvent>(owner),
            // increase_lockup_events: account::new_event_handle<IncreaseLockupEvent>(owner),
            join_validator_set_events: account::new_event_handle<JoinValidatorSetEvent>(owner),
            distribute_rewards_events: account::new_event_handle<DistributeRewardsEvent>(owner),
            // unlock_stake_events: account::new_event_handle<UnlockStakeEvent>(owner),
            // withdraw_stake_events: account::new_event_handle<WithdrawStakeEvent>(owner),
            leave_validator_set_events: account::new_event_handle<LeaveValidatorSetEvent>(owner),
        });

    }



    /// Allows an owner to change the operator of the stake pool.
    public fun set_operator(owner: &signer, new_operator: address) acquires StakePool {
        // let pool_address = owner_cap.pool_address;
        let pool_address = signer::address_of(owner);
        assert_stake_pool_exists(pool_address);
        let stake_pool = borrow_global_mut<StakePool>(pool_address);
        let old_operator = stake_pool.operator_address;
        stake_pool.operator_address = new_operator;

        event::emit_event(
            &mut stake_pool.set_operator_events,
            SetOperatorEvent {
                pool_address,
                old_operator,
                new_operator,
            },
        );
    }

    /// Rotate the consensus key of the validator, it'll take effect in next epoch.
    public entry fun rotate_consensus_key(
        operator: &signer,
        pool_address: address,
        new_consensus_pubkey: vector<u8>,
        proof_of_possession: vector<u8>,
    ) acquires StakePool, ValidatorConfig {
        assert_stake_pool_exists(pool_address);
        let stake_pool = borrow_global_mut<StakePool>(pool_address);
        assert!(signer::address_of(operator) == stake_pool.operator_address, error::unauthenticated(ENOT_OPERATOR));

        assert!(exists<ValidatorConfig>(pool_address), error::not_found(EVALIDATOR_CONFIG));
        let validator_info = borrow_global_mut<ValidatorConfig>(pool_address);
        let old_consensus_pubkey = validator_info.consensus_pubkey;
        // Checks the public key has a valid proof-of-possession to prevent rogue-key attacks.
        let pubkey_from_pop = &mut bls12381::public_key_from_bytes_with_pop(
            new_consensus_pubkey,
            &bls12381::proof_of_possession_from_bytes(proof_of_possession)
        );
        assert!(option::is_some(pubkey_from_pop), error::invalid_argument(EINVALID_PUBLIC_KEY));
        validator_info.consensus_pubkey = new_consensus_pubkey;

        event::emit_event(
            &mut stake_pool.rotate_consensus_key_events,
            RotateConsensusKeyEvent {
                pool_address,
                old_consensus_pubkey,
                new_consensus_pubkey,
            },
        );
    }

    /// Update the network and full node addresses of the validator. This only takes effect in the next epoch.
    public entry fun update_network_and_fullnode_addresses(
        operator: &signer,
        pool_address: address,
        new_network_addresses: vector<u8>,
        new_fullnode_addresses: vector<u8>,
    ) acquires StakePool, ValidatorConfig {
        assert_stake_pool_exists(pool_address);
        let stake_pool = borrow_global_mut<StakePool>(pool_address);
        assert!(signer::address_of(operator) == stake_pool.operator_address, error::unauthenticated(ENOT_OPERATOR));

        assert!(exists<ValidatorConfig>(pool_address), error::not_found(EVALIDATOR_CONFIG));
        let validator_info = borrow_global_mut<ValidatorConfig>(pool_address);
        let old_network_addresses = validator_info.network_addresses;
        validator_info.network_addresses = new_network_addresses;
        let old_fullnode_addresses = validator_info.fullnode_addresses;
        validator_info.fullnode_addresses = new_fullnode_addresses;

        event::emit_event(
            &mut stake_pool.update_network_and_fullnode_addresses_events,
            UpdateNetworkAndFullnodeAddressesEvent {
                pool_address,
                old_network_addresses,
                new_network_addresses,
                old_fullnode_addresses,
                new_fullnode_addresses,
            },
        );
    }

    /// This can only called by the operator of the validator/staking pool.
    public entry fun join_validator_set(
        operator: &signer,
        pool_address: address
    ) acquires ValidatorConfig, ValidatorSet {
        // assert!(
        //     staking_config::get_allow_validator_set_change(&staking_config::get()),
        //     error::invalid_argument(ENO_POST_GENESIS_VALIDATOR_SET_CHANGE_ALLOWED),
        // );

        join_validator_set_internal(operator, pool_address);
    }

    /// Request to have `pool_address` join the validator set. Can only be called after calling `initialize_validator`.
    /// If the validator has the required stake (more than minimum and less than maximum allowed), they will be
    /// added to the pending_active queue. All validators in this queue will be added to the active set when the next
    /// epoch starts (eligibility will be rechecked).
    ///
    /// This internal version can only be called by the Genesis module during Genesis.
    public(friend) fun join_validator_set_internal(
        _operator: &signer,
        pool_address: address
    ) acquires ValidatorConfig, ValidatorSet {
        // assert_stake_pool_exists(pool_address);
        // let stake_pool = borrow_global_mut<StakePool>(pool_address);
        // assert!(signer::address_of(operator) == stake_pool.operator_address, error::unauthenticated(ENOT_OPERATOR));
        // assert!(
        //     get_validator_state(pool_address) == VALIDATOR_STATUS_INACTIVE,
        //     error::invalid_state(EALREADY_ACTIVE_VALIDATOR),
        // );

        // let config = staking_config::get();
        // let (minimum_stake, maximum_stake) = staking_config::get_required_stake(&config);
        // let voting_power = get_next_epoch_voting_power(stake_pool);
        // assert!(voting_power >= minimum_stake, error::invalid_argument(ESTAKE_TOO_LOW));
        // assert!(voting_power <= maximum_stake, error::invalid_argument(ESTAKE_TOO_HIGH));

        // Track and validate voting power increase.
        // update_voting_power_increase(voting_power);

        // Add validator to pending_active, to be activated in the next epoch.
        let validator_config = borrow_global_mut<ValidatorConfig>(pool_address);
        assert!(!vector::is_empty(&validator_config.consensus_pubkey), error::invalid_argument(EINVALID_PUBLIC_KEY));

        // Validate the current validator set size has not exceeded the limit.
        let validator_set = borrow_global_mut<ValidatorSet>(@aptos_framework);
        // TODO: v7: refactor this

        // vector::push_back(&mut validator_set.pending_active,
        // generate_validator_info(pool_address, stake_pool, *validator_config));

        let validator_set_size = vector::length(&validator_set.active_validators) + vector::length(&validator_set.pending_active);
        assert!(validator_set_size <= MAX_VALIDATOR_SET_SIZE, error::invalid_argument(EVALIDATOR_SET_TOO_LARGE));

        // TODO: v7: refactor this
        // event::emit_event(
        //     &mut stake_pool.join_validator_set_events,
        //     JoinValidatorSetEvent { pool_address },
        // );
    }

    /// Returns true if the current validator can still vote in the current epoch.
    /// This includes validators that requested to leave but are still in the pending_inactive queue and will be removed
    /// when the epoch starts.
    public fun is_current_epoch_validator(pool_address: address): bool acquires ValidatorSet {
        assert_stake_pool_exists(pool_address);
        let validator_state = get_validator_state(pool_address);
        validator_state == VALIDATOR_STATUS_ACTIVE || validator_state == VALIDATOR_STATUS_PENDING_INACTIVE
    }

    /// Update the validator performance (proposal statistics). This is only called by block::prologue().
    /// This function cannot abort.
    public(friend) fun update_performance_statistics(proposer_index: Option<u64>, failed_proposer_indices: vector<u64>) acquires ValidatorPerformance {
        // Validator set cannot change until the end of the epoch, so the validator index in arguments should
        // match with those of the validators in ValidatorPerformance resource.
        let validator_perf = borrow_global_mut<ValidatorPerformance>(@aptos_framework);
        let validator_len = vector::length(&validator_perf.validators);

        // proposer_index is an option because it can be missing (for NilBlocks)
        if (option::is_some(&proposer_index)) {
            let cur_proposer_index = option::extract(&mut proposer_index);
            // Here, and in all other vector::borrow, skip any validator indices that are out of bounds,
            // this ensures that this function doesn't abort if there are out of bounds errors.
            if (cur_proposer_index < validator_len) {
                let validator = vector::borrow_mut(&mut validator_perf.validators, cur_proposer_index);
                spec {
                    assume validator.successful_proposals + 1 <= MAX_U64;
                };
                validator.successful_proposals = validator.successful_proposals + 1;
            };
        };

        let f = 0;
        let f_len = vector::length(&failed_proposer_indices);
        while ({
            spec {
                invariant len(validator_perf.validators) == validator_len;
            };
            f < f_len
        }) {
            let validator_index = *vector::borrow(&failed_proposer_indices, f);
            if (validator_index < validator_len) {
                let validator = vector::borrow_mut(&mut validator_perf.validators, validator_index);
                spec {
                    assume validator.failed_proposals + 1 <= MAX_U64;
                };
                validator.failed_proposals = validator.failed_proposals + 1;
            };
            f = f + 1;
        };
    }

    /// Triggers at epoch boundary. This function shouldn't abort.
    ///
    /// 1. Distribute transaction fees and rewards to stake pools of active and pending inactive validators (requested
    /// to leave but not yet removed).
    /// 2. Officially move pending active stake to active and move pending inactive stake to inactive.
    /// The staking pool's voting power in this new epoch will be updated to the total active stake.
    /// 3. Add pending active validators to the active set if they satisfy requirements so they can vote and remove
    /// pending inactive validators so they no longer can vote.
    /// 4. The validator's voting power in the validator set is updated to be the corresponding staking pool's voting
    /// power.
    public(friend) fun on_new_epoch() acquires ValidatorPerformance, ValidatorSet, ValidatorUniverse, ValidatorConfig {
        let validator_set = borrow_global_mut<ValidatorSet>(@aptos_framework);
        debug::print(validator_set);

        // let config = staking_config::get();
        let _validator_perf = borrow_global_mut<ValidatorPerformance>(@aptos_framework);

        let universe = borrow_global<ValidatorUniverse>(@aptos_framework);

        validator_set.active_validators = vector::empty<ValidatorInfo>();
        let i = 0;
        let len = vector::length<address>(&universe.all_vals);
        while (i < len) {
            let addr = vector::borrow(&universe.all_vals, i);
            let config =  borrow_global<ValidatorConfig>(*addr);
            let info = ValidatorInfo {
              addr: *addr,
              config: *config,
            };


            vector::push_back(&mut validator_set.active_validators, info);
            i = i + 1;
        };


    }

    /// Calculate the rewards amount.
    fun calculate_rewards_amount(
        _stake_amount: u64,
        _num_successful_proposals: u64,
        _num_total_proposals: u64,
        _rewards_rate: u64,
        _rewards_rate_denominator: u64,
    ): u64 {

        100
    }

    /// Mint rewards corresponding to current epoch's `stake` and `num_successful_votes`.
    fun distribute_rewards(
        _stake: &mut Coin<AptosCoin>,
        _num_successful_proposals: u64,
        _num_total_proposals: u64,
        _rewards_rate: u64,
        _rewards_rate_denominator: u64,
    ): u64  {
        // TODO
        1000
    }

    fun append<T>(v1: &mut vector<T>, v2: &mut vector<T>) {
        while (!vector::is_empty(v2)) {
            vector::push_back(v1, vector::pop_back(v2));
        }
    }

    fun find_validator(v: &vector<ValidatorInfo>, addr: address): Option<u64> {
        let i = 0;
        let len = vector::length(v);
        while ({
            spec {
                invariant !(exists j in 0..i: v[j].addr == addr);
            };
            i < len
        }) {
            if (vector::borrow(v, i).addr == addr) {
                return option::some(i)
            };
            i = i + 1;
        };
        option::none()
    }

    fun generate_validator_info(addr: address, _stake_pool: &StakePool, config: ValidatorConfig): ValidatorInfo {
        // let voting_power = get_next_epoch_voting_power(stake_pool);
        ValidatorInfo {
            addr,
            // voting_power: 1,
            config,
        }
    }

    fun assert_stake_pool_exists(pool_address: address) {
        assert!(stake_pool_exists(pool_address), error::invalid_argument(ESTAKE_POOL_DOES_NOT_EXIST));
    }
}
