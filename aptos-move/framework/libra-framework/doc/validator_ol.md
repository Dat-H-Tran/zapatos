
<a name="0x1_validator"></a>

# Module `0x1::validator`


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


-  [Resource `StakePool`](#0x1_validator_StakePool)
-  [Resource `ValidatorConfig`](#0x1_validator_ValidatorConfig)
-  [Struct `ValidatorInfo`](#0x1_validator_ValidatorInfo)
-  [Resource `ValidatorSet`](#0x1_validator_ValidatorSet)
-  [Struct `IndividualValidatorPerformance`](#0x1_validator_IndividualValidatorPerformance)
-  [Resource `ValidatorPerformance`](#0x1_validator_ValidatorPerformance)
-  [Struct `RegisterValidatorCandidateEvent`](#0x1_validator_RegisterValidatorCandidateEvent)
-  [Struct `SetOperatorEvent`](#0x1_validator_SetOperatorEvent)
-  [Struct `RotateConsensusKeyEvent`](#0x1_validator_RotateConsensusKeyEvent)
-  [Struct `UpdateNetworkAndFullnodeAddressesEvent`](#0x1_validator_UpdateNetworkAndFullnodeAddressesEvent)
-  [Struct `JoinValidatorSetEvent`](#0x1_validator_JoinValidatorSetEvent)
-  [Struct `DistributeRewardsEvent`](#0x1_validator_DistributeRewardsEvent)
-  [Struct `LeaveValidatorSetEvent`](#0x1_validator_LeaveValidatorSetEvent)
-  [Resource `ValidatorFees`](#0x1_validator_ValidatorFees)
-  [Constants](#@Constants_0)
-  [Function `initialize_validator_fees`](#0x1_validator_initialize_validator_fees)
-  [Function `add_transaction_fee`](#0x1_validator_add_transaction_fee)
-  [Function `get_validator_state`](#0x1_validator_get_validator_state)
-  [Function `get_operator`](#0x1_validator_get_operator)
-  [Function `get_validator_index`](#0x1_validator_get_validator_index)
-  [Function `get_current_epoch_proposal_counts`](#0x1_validator_get_current_epoch_proposal_counts)
-  [Function `get_validator_config`](#0x1_validator_get_validator_config)
-  [Function `stake_pool_exists`](#0x1_validator_stake_pool_exists)
-  [Function `initialize`](#0x1_validator_initialize)
-  [Function `initialize_validator`](#0x1_validator_initialize_validator)
-  [Function `initialize_owner`](#0x1_validator_initialize_owner)
-  [Function `set_operator`](#0x1_validator_set_operator)
-  [Function `rotate_consensus_key`](#0x1_validator_rotate_consensus_key)
-  [Function `update_network_and_fullnode_addresses`](#0x1_validator_update_network_and_fullnode_addresses)
-  [Function `join_validator_set`](#0x1_validator_join_validator_set)
-  [Function `join_validator_set_internal`](#0x1_validator_join_validator_set_internal)
-  [Function `is_current_epoch_validator`](#0x1_validator_is_current_epoch_validator)
-  [Function `update_performance_statistics`](#0x1_validator_update_performance_statistics)
-  [Function `on_new_epoch`](#0x1_validator_on_new_epoch)
-  [Function `calculate_rewards_amount`](#0x1_validator_calculate_rewards_amount)
-  [Function `distribute_rewards`](#0x1_validator_distribute_rewards)
-  [Function `append`](#0x1_validator_append)
-  [Function `find_validator`](#0x1_validator_find_validator)
-  [Function `generate_validator_info`](#0x1_validator_generate_validator_info)
-  [Function `assert_stake_pool_exists`](#0x1_validator_assert_stake_pool_exists)
-  [Specification](#@Specification_1)


<pre><code><b>use</b> <a href="account.md#0x1_account">0x1::account</a>;
<b>use</b> <a href="aptos_coin.md#0x1_aptos_coin">0x1::aptos_coin</a>;
<b>use</b> <a href="../../aptos-stdlib/doc/bls12381.md#0x1_bls12381">0x1::bls12381</a>;
<b>use</b> <a href="coin.md#0x1_coin">0x1::coin</a>;
<b>use</b> <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error">0x1::error</a>;
<b>use</b> <a href="event.md#0x1_event">0x1::event</a>;
<b>use</b> <a href="../../aptos-stdlib/../move-stdlib/doc/option.md#0x1_option">0x1::option</a>;
<b>use</b> <a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">0x1::signer</a>;
<b>use</b> <a href="system_addresses.md#0x1_system_addresses">0x1::system_addresses</a>;
<b>use</b> <a href="../../aptos-stdlib/doc/table.md#0x1_table">0x1::table</a>;
<b>use</b> <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">0x1::vector</a>;
</code></pre>



<a name="0x1_validator_StakePool"></a>

## Resource `StakePool`

Each validator has a separate StakePool resource and can provide a stake.
Changes in stake for an active validator:
1. If a validator calls add_stake, the newly added stake is moved to pending_active.
2. If validator calls unlock, their stake is moved to pending_inactive.
2. When the next epoch starts, any pending_inactive stake is moved to inactive and can be withdrawn.
Any pending_active stake is moved to active and adds to the validator's voting power.

Changes in stake for an inactive validator:
1. If a validator calls add_stake, the newly added stake is moved directly to active.
2. If validator calls unlock, their stake is moved directly to inactive.
3. When the next epoch starts, the validator can be activated if their active stake is more than the minimum.


<pre><code><b>struct</b> <a href="validator_ol.md#0x1_validator_StakePool">StakePool</a> <b>has</b> key
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>operator_address: <b>address</b></code>
</dt>
<dd>

</dd>
<dt>
<code>initialize_validator_events: <a href="event.md#0x1_event_EventHandle">event::EventHandle</a>&lt;<a href="validator_ol.md#0x1_validator_RegisterValidatorCandidateEvent">validator::RegisterValidatorCandidateEvent</a>&gt;</code>
</dt>
<dd>

</dd>
<dt>
<code>set_operator_events: <a href="event.md#0x1_event_EventHandle">event::EventHandle</a>&lt;<a href="validator_ol.md#0x1_validator_SetOperatorEvent">validator::SetOperatorEvent</a>&gt;</code>
</dt>
<dd>

</dd>
<dt>
<code>rotate_consensus_key_events: <a href="event.md#0x1_event_EventHandle">event::EventHandle</a>&lt;<a href="validator_ol.md#0x1_validator_RotateConsensusKeyEvent">validator::RotateConsensusKeyEvent</a>&gt;</code>
</dt>
<dd>

</dd>
<dt>
<code>update_network_and_fullnode_addresses_events: <a href="event.md#0x1_event_EventHandle">event::EventHandle</a>&lt;<a href="validator_ol.md#0x1_validator_UpdateNetworkAndFullnodeAddressesEvent">validator::UpdateNetworkAndFullnodeAddressesEvent</a>&gt;</code>
</dt>
<dd>

</dd>
<dt>
<code>join_validator_set_events: <a href="event.md#0x1_event_EventHandle">event::EventHandle</a>&lt;<a href="validator_ol.md#0x1_validator_JoinValidatorSetEvent">validator::JoinValidatorSetEvent</a>&gt;</code>
</dt>
<dd>

</dd>
<dt>
<code>distribute_rewards_events: <a href="event.md#0x1_event_EventHandle">event::EventHandle</a>&lt;<a href="validator_ol.md#0x1_validator_DistributeRewardsEvent">validator::DistributeRewardsEvent</a>&gt;</code>
</dt>
<dd>

</dd>
<dt>
<code>leave_validator_set_events: <a href="event.md#0x1_event_EventHandle">event::EventHandle</a>&lt;<a href="validator_ol.md#0x1_validator_LeaveValidatorSetEvent">validator::LeaveValidatorSetEvent</a>&gt;</code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="0x1_validator_ValidatorConfig"></a>

## Resource `ValidatorConfig`

Validator info stored in validator address.


<pre><code><b>struct</b> <a href="validator_ol.md#0x1_validator_ValidatorConfig">ValidatorConfig</a> <b>has</b> <b>copy</b>, drop, store, key
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>consensus_pubkey: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;</code>
</dt>
<dd>

</dd>
<dt>
<code>network_addresses: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;</code>
</dt>
<dd>

</dd>
<dt>
<code>fullnode_addresses: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;</code>
</dt>
<dd>

</dd>
<dt>
<code>validator_index: u64</code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="0x1_validator_ValidatorInfo"></a>

## Struct `ValidatorInfo`

Consensus information per validator, stored in ValidatorSet.


<pre><code><b>struct</b> <a href="validator_ol.md#0x1_validator_ValidatorInfo">ValidatorInfo</a> <b>has</b> <b>copy</b>, drop, store
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>addr: <b>address</b></code>
</dt>
<dd>

</dd>
<dt>
<code>config: <a href="validator_ol.md#0x1_validator_ValidatorConfig">validator::ValidatorConfig</a></code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="0x1_validator_ValidatorSet"></a>

## Resource `ValidatorSet`

Full ValidatorSet, stored in @aptos_framework.
1. join_validator_set adds to pending_active queue.
2. leave_valdiator_set moves from active to pending_inactive queue.
3. on_new_epoch processes two pending queues and refresh ValidatorInfo from the owner's address.


<pre><code><b>struct</b> <a href="validator_ol.md#0x1_validator_ValidatorSet">ValidatorSet</a> <b>has</b> key
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>consensus_scheme: u8</code>
</dt>
<dd>

</dd>
<dt>
<code>active_validators: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;<a href="validator_ol.md#0x1_validator_ValidatorInfo">validator::ValidatorInfo</a>&gt;</code>
</dt>
<dd>

</dd>
<dt>
<code>pending_inactive: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;<a href="validator_ol.md#0x1_validator_ValidatorInfo">validator::ValidatorInfo</a>&gt;</code>
</dt>
<dd>

</dd>
<dt>
<code>pending_active: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;<a href="validator_ol.md#0x1_validator_ValidatorInfo">validator::ValidatorInfo</a>&gt;</code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="0x1_validator_IndividualValidatorPerformance"></a>

## Struct `IndividualValidatorPerformance`



<pre><code><b>struct</b> <a href="validator_ol.md#0x1_validator_IndividualValidatorPerformance">IndividualValidatorPerformance</a> <b>has</b> drop, store
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>successful_proposals: u64</code>
</dt>
<dd>

</dd>
<dt>
<code>failed_proposals: u64</code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="0x1_validator_ValidatorPerformance"></a>

## Resource `ValidatorPerformance`



<pre><code><b>struct</b> <a href="validator_ol.md#0x1_validator_ValidatorPerformance">ValidatorPerformance</a> <b>has</b> key
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>validators: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;<a href="validator_ol.md#0x1_validator_IndividualValidatorPerformance">validator::IndividualValidatorPerformance</a>&gt;</code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="0x1_validator_RegisterValidatorCandidateEvent"></a>

## Struct `RegisterValidatorCandidateEvent`



<pre><code><b>struct</b> <a href="validator_ol.md#0x1_validator_RegisterValidatorCandidateEvent">RegisterValidatorCandidateEvent</a> <b>has</b> drop, store
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>pool_address: <b>address</b></code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="0x1_validator_SetOperatorEvent"></a>

## Struct `SetOperatorEvent`



<pre><code><b>struct</b> <a href="validator_ol.md#0x1_validator_SetOperatorEvent">SetOperatorEvent</a> <b>has</b> drop, store
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>pool_address: <b>address</b></code>
</dt>
<dd>

</dd>
<dt>
<code>old_operator: <b>address</b></code>
</dt>
<dd>

</dd>
<dt>
<code>new_operator: <b>address</b></code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="0x1_validator_RotateConsensusKeyEvent"></a>

## Struct `RotateConsensusKeyEvent`



<pre><code><b>struct</b> <a href="validator_ol.md#0x1_validator_RotateConsensusKeyEvent">RotateConsensusKeyEvent</a> <b>has</b> drop, store
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>pool_address: <b>address</b></code>
</dt>
<dd>

</dd>
<dt>
<code>old_consensus_pubkey: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;</code>
</dt>
<dd>

</dd>
<dt>
<code>new_consensus_pubkey: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;</code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="0x1_validator_UpdateNetworkAndFullnodeAddressesEvent"></a>

## Struct `UpdateNetworkAndFullnodeAddressesEvent`



<pre><code><b>struct</b> <a href="validator_ol.md#0x1_validator_UpdateNetworkAndFullnodeAddressesEvent">UpdateNetworkAndFullnodeAddressesEvent</a> <b>has</b> drop, store
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>pool_address: <b>address</b></code>
</dt>
<dd>

</dd>
<dt>
<code>old_network_addresses: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;</code>
</dt>
<dd>

</dd>
<dt>
<code>new_network_addresses: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;</code>
</dt>
<dd>

</dd>
<dt>
<code>old_fullnode_addresses: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;</code>
</dt>
<dd>

</dd>
<dt>
<code>new_fullnode_addresses: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;</code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="0x1_validator_JoinValidatorSetEvent"></a>

## Struct `JoinValidatorSetEvent`



<pre><code><b>struct</b> <a href="validator_ol.md#0x1_validator_JoinValidatorSetEvent">JoinValidatorSetEvent</a> <b>has</b> drop, store
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>pool_address: <b>address</b></code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="0x1_validator_DistributeRewardsEvent"></a>

## Struct `DistributeRewardsEvent`



<pre><code><b>struct</b> <a href="validator_ol.md#0x1_validator_DistributeRewardsEvent">DistributeRewardsEvent</a> <b>has</b> drop, store
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>pool_address: <b>address</b></code>
</dt>
<dd>

</dd>
<dt>
<code>rewards_amount: u64</code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="0x1_validator_LeaveValidatorSetEvent"></a>

## Struct `LeaveValidatorSetEvent`



<pre><code><b>struct</b> <a href="validator_ol.md#0x1_validator_LeaveValidatorSetEvent">LeaveValidatorSetEvent</a> <b>has</b> drop, store
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>pool_address: <b>address</b></code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="0x1_validator_ValidatorFees"></a>

## Resource `ValidatorFees`

Stores transaction fees assigned to validators. All fees are distributed to validators
at the end of the epoch.


<pre><code><b>struct</b> <a href="validator_ol.md#0x1_validator_ValidatorFees">ValidatorFees</a> <b>has</b> key
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>fees_table: <a href="../../aptos-stdlib/doc/table.md#0x1_table_Table">table::Table</a>&lt;<b>address</b>, <a href="coin.md#0x1_coin_Coin">coin::Coin</a>&lt;<a href="aptos_coin.md#0x1_aptos_coin_AptosCoin">aptos_coin::AptosCoin</a>&gt;&gt;</code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="@Constants_0"></a>

## Constants


<a name="0x1_validator_MAX_U64"></a>

max value of u64


<pre><code><b>const</b> <a href="validator_ol.md#0x1_validator_MAX_U64">MAX_U64</a>: u128 = 18446744073709551615;
</code></pre>



<a name="0x1_validator_EALREADY_ACTIVE_VALIDATOR"></a>

Account is already a validator or pending validator.


<pre><code><b>const</b> <a href="validator_ol.md#0x1_validator_EALREADY_ACTIVE_VALIDATOR">EALREADY_ACTIVE_VALIDATOR</a>: u64 = 4;
</code></pre>



<a name="0x1_validator_EALREADY_REGISTERED"></a>

Account is already registered as a validator candidate.


<pre><code><b>const</b> <a href="validator_ol.md#0x1_validator_EALREADY_REGISTERED">EALREADY_REGISTERED</a>: u64 = 8;
</code></pre>



<a name="0x1_validator_EFEES_TABLE_ALREADY_EXISTS"></a>

Table to store collected transaction fees for each validator already exists.


<pre><code><b>const</b> <a href="validator_ol.md#0x1_validator_EFEES_TABLE_ALREADY_EXISTS">EFEES_TABLE_ALREADY_EXISTS</a>: u64 = 19;
</code></pre>



<a name="0x1_validator_EINVALID_PUBLIC_KEY"></a>

Invalid consensus public key


<pre><code><b>const</b> <a href="validator_ol.md#0x1_validator_EINVALID_PUBLIC_KEY">EINVALID_PUBLIC_KEY</a>: u64 = 11;
</code></pre>



<a name="0x1_validator_ELAST_VALIDATOR"></a>

Can't remove last validator.


<pre><code><b>const</b> <a href="validator_ol.md#0x1_validator_ELAST_VALIDATOR">ELAST_VALIDATOR</a>: u64 = 6;
</code></pre>



<a name="0x1_validator_ENOT_OPERATOR"></a>

Account does not have the right operator capability.


<pre><code><b>const</b> <a href="validator_ol.md#0x1_validator_ENOT_OPERATOR">ENOT_OPERATOR</a>: u64 = 9;
</code></pre>



<a name="0x1_validator_ENOT_VALIDATOR"></a>

Account is not a validator.


<pre><code><b>const</b> <a href="validator_ol.md#0x1_validator_ENOT_VALIDATOR">ENOT_VALIDATOR</a>: u64 = 5;
</code></pre>



<a name="0x1_validator_ESTAKE_POOL_DOES_NOT_EXIST"></a>

Stake pool does not exist at the provided pool address.


<pre><code><b>const</b> <a href="validator_ol.md#0x1_validator_ESTAKE_POOL_DOES_NOT_EXIST">ESTAKE_POOL_DOES_NOT_EXIST</a>: u64 = 14;
</code></pre>



<a name="0x1_validator_EVALIDATOR_CONFIG"></a>

Validator Config not published.


<pre><code><b>const</b> <a href="validator_ol.md#0x1_validator_EVALIDATOR_CONFIG">EVALIDATOR_CONFIG</a>: u64 = 1;
</code></pre>



<a name="0x1_validator_EVALIDATOR_SET_TOO_LARGE"></a>

Validator set exceeds the limit


<pre><code><b>const</b> <a href="validator_ol.md#0x1_validator_EVALIDATOR_SET_TOO_LARGE">EVALIDATOR_SET_TOO_LARGE</a>: u64 = 12;
</code></pre>



<a name="0x1_validator_MAX_VALIDATOR_SET_SIZE"></a>

Limit the maximum size to u16::max, it's the current limit of the bitvec
https://github.com/aptos-labs/aptos-core/blob/main/crates/aptos-bitvec/src/lib.rs#L20


<pre><code><b>const</b> <a href="validator_ol.md#0x1_validator_MAX_VALIDATOR_SET_SIZE">MAX_VALIDATOR_SET_SIZE</a>: u64 = 65536;
</code></pre>



<a name="0x1_validator_VALIDATOR_STATUS_ACTIVE"></a>



<pre><code><b>const</b> <a href="validator_ol.md#0x1_validator_VALIDATOR_STATUS_ACTIVE">VALIDATOR_STATUS_ACTIVE</a>: u64 = 2;
</code></pre>



<a name="0x1_validator_VALIDATOR_STATUS_INACTIVE"></a>



<pre><code><b>const</b> <a href="validator_ol.md#0x1_validator_VALIDATOR_STATUS_INACTIVE">VALIDATOR_STATUS_INACTIVE</a>: u64 = 4;
</code></pre>



<a name="0x1_validator_VALIDATOR_STATUS_PENDING_ACTIVE"></a>

Validator status enum. We can switch to proper enum later once Move supports it.


<pre><code><b>const</b> <a href="validator_ol.md#0x1_validator_VALIDATOR_STATUS_PENDING_ACTIVE">VALIDATOR_STATUS_PENDING_ACTIVE</a>: u64 = 1;
</code></pre>



<a name="0x1_validator_VALIDATOR_STATUS_PENDING_INACTIVE"></a>



<pre><code><b>const</b> <a href="validator_ol.md#0x1_validator_VALIDATOR_STATUS_PENDING_INACTIVE">VALIDATOR_STATUS_PENDING_INACTIVE</a>: u64 = 3;
</code></pre>



<a name="0x1_validator_initialize_validator_fees"></a>

## Function `initialize_validator_fees`

Initializes the resource storing information about collected transaction fees per validator.
Used by <code><a href="transaction_fee.md#0x1_transaction_fee">transaction_fee</a>.<b>move</b></code> to initialize fee collection and distribution.


<pre><code><b>public</b>(<b>friend</b>) <b>fun</b> <a href="validator_ol.md#0x1_validator_initialize_validator_fees">initialize_validator_fees</a>(aptos_framework: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b>(<b>friend</b>) <b>fun</b> <a href="validator_ol.md#0x1_validator_initialize_validator_fees">initialize_validator_fees</a>(aptos_framework: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>) {
    <a href="system_addresses.md#0x1_system_addresses_assert_aptos_framework">system_addresses::assert_aptos_framework</a>(aptos_framework);
    <b>assert</b>!(
        !<b>exists</b>&lt;<a href="validator_ol.md#0x1_validator_ValidatorFees">ValidatorFees</a>&gt;(@aptos_framework),
        <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_already_exists">error::already_exists</a>(<a href="validator_ol.md#0x1_validator_EFEES_TABLE_ALREADY_EXISTS">EFEES_TABLE_ALREADY_EXISTS</a>)
    );
    <b>move_to</b>(aptos_framework, <a href="validator_ol.md#0x1_validator_ValidatorFees">ValidatorFees</a> { fees_table: <a href="../../aptos-stdlib/doc/table.md#0x1_table_new">table::new</a>() });
}
</code></pre>



</details>

<a name="0x1_validator_add_transaction_fee"></a>

## Function `add_transaction_fee`

Stores the transaction fee collected to the specified validator address.


<pre><code><b>public</b>(<b>friend</b>) <b>fun</b> <a href="validator_ol.md#0x1_validator_add_transaction_fee">add_transaction_fee</a>(validator_addr: <b>address</b>, fee: <a href="coin.md#0x1_coin_Coin">coin::Coin</a>&lt;<a href="aptos_coin.md#0x1_aptos_coin_AptosCoin">aptos_coin::AptosCoin</a>&gt;)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b>(<b>friend</b>) <b>fun</b> <a href="validator_ol.md#0x1_validator_add_transaction_fee">add_transaction_fee</a>(validator_addr: <b>address</b>, fee: Coin&lt;AptosCoin&gt;) <b>acquires</b> <a href="validator_ol.md#0x1_validator_ValidatorFees">ValidatorFees</a> {
    <b>let</b> fees_table = &<b>mut</b> <b>borrow_global_mut</b>&lt;<a href="validator_ol.md#0x1_validator_ValidatorFees">ValidatorFees</a>&gt;(@aptos_framework).fees_table;
    <b>if</b> (<a href="../../aptos-stdlib/doc/table.md#0x1_table_contains">table::contains</a>(fees_table, validator_addr)) {
        <b>let</b> collected_fee = <a href="../../aptos-stdlib/doc/table.md#0x1_table_borrow_mut">table::borrow_mut</a>(fees_table, validator_addr);
        <a href="coin.md#0x1_coin_merge">coin::merge</a>(collected_fee, fee);
    } <b>else</b> {
        <a href="../../aptos-stdlib/doc/table.md#0x1_table_add">table::add</a>(fees_table, validator_addr, fee);
    }
}
</code></pre>



</details>

<a name="0x1_validator_get_validator_state"></a>

## Function `get_validator_state`

Returns the validator's state.


<pre><code><b>public</b> <b>fun</b> <a href="validator_ol.md#0x1_validator_get_validator_state">get_validator_state</a>(pool_address: <b>address</b>): u64
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="validator_ol.md#0x1_validator_get_validator_state">get_validator_state</a>(pool_address: <b>address</b>): u64 <b>acquires</b> <a href="validator_ol.md#0x1_validator_ValidatorSet">ValidatorSet</a> {
    <b>let</b> validator_set = <b>borrow_global</b>&lt;<a href="validator_ol.md#0x1_validator_ValidatorSet">ValidatorSet</a>&gt;(@aptos_framework);
    <b>if</b> (<a href="../../aptos-stdlib/../move-stdlib/doc/option.md#0x1_option_is_some">option::is_some</a>(&<a href="validator_ol.md#0x1_validator_find_validator">find_validator</a>(&validator_set.pending_active, pool_address))) {
        <a href="validator_ol.md#0x1_validator_VALIDATOR_STATUS_PENDING_ACTIVE">VALIDATOR_STATUS_PENDING_ACTIVE</a>
    } <b>else</b> <b>if</b> (<a href="../../aptos-stdlib/../move-stdlib/doc/option.md#0x1_option_is_some">option::is_some</a>(&<a href="validator_ol.md#0x1_validator_find_validator">find_validator</a>(&validator_set.active_validators, pool_address))) {
        <a href="validator_ol.md#0x1_validator_VALIDATOR_STATUS_ACTIVE">VALIDATOR_STATUS_ACTIVE</a>
    } <b>else</b> <b>if</b> (<a href="../../aptos-stdlib/../move-stdlib/doc/option.md#0x1_option_is_some">option::is_some</a>(&<a href="validator_ol.md#0x1_validator_find_validator">find_validator</a>(&validator_set.pending_inactive, pool_address))) {
        <a href="validator_ol.md#0x1_validator_VALIDATOR_STATUS_PENDING_INACTIVE">VALIDATOR_STATUS_PENDING_INACTIVE</a>
    } <b>else</b> {
        <a href="validator_ol.md#0x1_validator_VALIDATOR_STATUS_INACTIVE">VALIDATOR_STATUS_INACTIVE</a>
    }
}
</code></pre>



</details>

<a name="0x1_validator_get_operator"></a>

## Function `get_operator`

Return the operator of the validator at <code>pool_address</code>.


<pre><code><b>public</b> <b>fun</b> <a href="validator_ol.md#0x1_validator_get_operator">get_operator</a>(pool_address: <b>address</b>): <b>address</b>
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="validator_ol.md#0x1_validator_get_operator">get_operator</a>(pool_address: <b>address</b>): <b>address</b> <b>acquires</b> <a href="validator_ol.md#0x1_validator_StakePool">StakePool</a> {
    <a href="validator_ol.md#0x1_validator_assert_stake_pool_exists">assert_stake_pool_exists</a>(pool_address);
    <b>borrow_global</b>&lt;<a href="validator_ol.md#0x1_validator_StakePool">StakePool</a>&gt;(pool_address).operator_address
}
</code></pre>



</details>

<a name="0x1_validator_get_validator_index"></a>

## Function `get_validator_index`

Return the validator index for <code>pool_address</code>.


<pre><code><b>public</b> <b>fun</b> <a href="validator_ol.md#0x1_validator_get_validator_index">get_validator_index</a>(pool_address: <b>address</b>): u64
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="validator_ol.md#0x1_validator_get_validator_index">get_validator_index</a>(pool_address: <b>address</b>): u64 <b>acquires</b> <a href="validator_ol.md#0x1_validator_ValidatorConfig">ValidatorConfig</a> {
    <a href="validator_ol.md#0x1_validator_assert_stake_pool_exists">assert_stake_pool_exists</a>(pool_address);
    <b>borrow_global</b>&lt;<a href="validator_ol.md#0x1_validator_ValidatorConfig">ValidatorConfig</a>&gt;(pool_address).validator_index
}
</code></pre>



</details>

<a name="0x1_validator_get_current_epoch_proposal_counts"></a>

## Function `get_current_epoch_proposal_counts`

Return the number of successful and failed proposals for the proposal at the given validator index.


<pre><code><b>public</b> <b>fun</b> <a href="validator_ol.md#0x1_validator_get_current_epoch_proposal_counts">get_current_epoch_proposal_counts</a>(validator_index: u64): (u64, u64)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="validator_ol.md#0x1_validator_get_current_epoch_proposal_counts">get_current_epoch_proposal_counts</a>(validator_index: u64): (u64, u64) <b>acquires</b> <a href="validator_ol.md#0x1_validator_ValidatorPerformance">ValidatorPerformance</a> {
    <b>let</b> validator_performances = &<b>borrow_global</b>&lt;<a href="validator_ol.md#0x1_validator_ValidatorPerformance">ValidatorPerformance</a>&gt;(@aptos_framework).validators;
    <b>let</b> validator_performance = <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_borrow">vector::borrow</a>(validator_performances, validator_index);
    (validator_performance.successful_proposals, validator_performance.failed_proposals)
}
</code></pre>



</details>

<a name="0x1_validator_get_validator_config"></a>

## Function `get_validator_config`

Return the validator's config.


<pre><code><b>public</b> <b>fun</b> <a href="validator_ol.md#0x1_validator_get_validator_config">get_validator_config</a>(pool_address: <b>address</b>): (<a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;, <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;, <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="validator_ol.md#0x1_validator_get_validator_config">get_validator_config</a>(pool_address: <b>address</b>): (<a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;, <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;, <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;) <b>acquires</b> <a href="validator_ol.md#0x1_validator_ValidatorConfig">ValidatorConfig</a> {
    <a href="validator_ol.md#0x1_validator_assert_stake_pool_exists">assert_stake_pool_exists</a>(pool_address);
    <b>let</b> validator_config = <b>borrow_global</b>&lt;<a href="validator_ol.md#0x1_validator_ValidatorConfig">ValidatorConfig</a>&gt;(pool_address);
    (validator_config.consensus_pubkey, validator_config.network_addresses, validator_config.fullnode_addresses)
}
</code></pre>



</details>

<a name="0x1_validator_stake_pool_exists"></a>

## Function `stake_pool_exists`



<pre><code><b>public</b> <b>fun</b> <a href="validator_ol.md#0x1_validator_stake_pool_exists">stake_pool_exists</a>(addr: <b>address</b>): bool
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="validator_ol.md#0x1_validator_stake_pool_exists">stake_pool_exists</a>(addr: <b>address</b>): bool {
    <b>exists</b>&lt;<a href="validator_ol.md#0x1_validator_StakePool">StakePool</a>&gt;(addr)
}
</code></pre>



</details>

<a name="0x1_validator_initialize"></a>

## Function `initialize`

Initialize validator set to the core resource account.


<pre><code><b>public</b>(<b>friend</b>) <b>fun</b> <a href="validator_ol.md#0x1_validator_initialize">initialize</a>(aptos_framework: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b>(<b>friend</b>) <b>fun</b> <a href="validator_ol.md#0x1_validator_initialize">initialize</a>(aptos_framework: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>) {
    <a href="system_addresses.md#0x1_system_addresses_assert_aptos_framework">system_addresses::assert_aptos_framework</a>(aptos_framework);

    <b>move_to</b>(aptos_framework, <a href="validator_ol.md#0x1_validator_ValidatorSet">ValidatorSet</a> {
        consensus_scheme: 0,
        active_validators: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_empty">vector::empty</a>(),
        pending_active: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_empty">vector::empty</a>(),
        pending_inactive: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_empty">vector::empty</a>(),
        // total_voting_power: 0,
        // total_joining_power: 0,
    });

    <b>move_to</b>(aptos_framework, <a href="validator_ol.md#0x1_validator_ValidatorPerformance">ValidatorPerformance</a> {
        validators: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_empty">vector::empty</a>(),
    });
}
</code></pre>



</details>

<a name="0x1_validator_initialize_validator"></a>

## Function `initialize_validator`

Initialize the validator account and give ownership to the signing account.


<pre><code><b>public</b> entry <b>fun</b> <a href="validator_ol.md#0x1_validator_initialize_validator">initialize_validator</a>(<a href="account.md#0x1_account">account</a>: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>, consensus_pubkey: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;, proof_of_possession: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;, network_addresses: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;, fullnode_addresses: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> entry <b>fun</b> <a href="validator_ol.md#0x1_validator_initialize_validator">initialize_validator</a>(
    <a href="account.md#0x1_account">account</a>: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>,
    consensus_pubkey: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;,
    proof_of_possession: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;,
    network_addresses: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;,
    fullnode_addresses: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;,
)  {
    // Checks the <b>public</b> key <b>has</b> a valid proof-of-possession <b>to</b> prevent rogue-key attacks.
    <b>let</b> pubkey_from_pop = &<b>mut</b> <a href="../../aptos-stdlib/doc/bls12381.md#0x1_bls12381_public_key_from_bytes_with_pop">bls12381::public_key_from_bytes_with_pop</a>(
        consensus_pubkey,
        &<a href="../../aptos-stdlib/doc/bls12381.md#0x1_bls12381_proof_of_possession_from_bytes">bls12381::proof_of_possession_from_bytes</a>(proof_of_possession)
    );
    <b>assert</b>!(<a href="../../aptos-stdlib/../move-stdlib/doc/option.md#0x1_option_is_some">option::is_some</a>(pubkey_from_pop), <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_invalid_argument">error::invalid_argument</a>(<a href="validator_ol.md#0x1_validator_EINVALID_PUBLIC_KEY">EINVALID_PUBLIC_KEY</a>));

    <a href="validator_ol.md#0x1_validator_initialize_owner">initialize_owner</a>(<a href="account.md#0x1_account">account</a>);
    <b>move_to</b>(<a href="account.md#0x1_account">account</a>, <a href="validator_ol.md#0x1_validator_ValidatorConfig">ValidatorConfig</a> {
        consensus_pubkey,
        network_addresses,
        fullnode_addresses,
        validator_index: 0,
    });
}
</code></pre>



</details>

<a name="0x1_validator_initialize_owner"></a>

## Function `initialize_owner`



<pre><code><b>fun</b> <a href="validator_ol.md#0x1_validator_initialize_owner">initialize_owner</a>(owner: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>fun</b> <a href="validator_ol.md#0x1_validator_initialize_owner">initialize_owner</a>(owner: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>) {
    <b>let</b> owner_address = <a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer_address_of">signer::address_of</a>(owner);
    // <b>assert</b>!(is_allowed(owner_address), <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_not_found">error::not_found</a>(EINELIGIBLE_VALIDATOR));
    <b>assert</b>!(!<a href="validator_ol.md#0x1_validator_stake_pool_exists">stake_pool_exists</a>(owner_address), <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_already_exists">error::already_exists</a>(<a href="validator_ol.md#0x1_validator_EALREADY_REGISTERED">EALREADY_REGISTERED</a>));

    <b>move_to</b>(owner, <a href="validator_ol.md#0x1_validator_StakePool">StakePool</a> {
        // active: <a href="coin.md#0x1_coin_zero">coin::zero</a>&lt;AptosCoin&gt;(),
        // pending_active: <a href="coin.md#0x1_coin_zero">coin::zero</a>&lt;AptosCoin&gt;(),
        // pending_inactive: <a href="coin.md#0x1_coin_zero">coin::zero</a>&lt;AptosCoin&gt;(),
        // inactive: <a href="coin.md#0x1_coin_zero">coin::zero</a>&lt;AptosCoin&gt;(),
        // locked_until_secs: 0,
        operator_address: owner_address,
        // delegated_voter: owner_address,
        // Events.
        initialize_validator_events: <a href="account.md#0x1_account_new_event_handle">account::new_event_handle</a>&lt;<a href="validator_ol.md#0x1_validator_RegisterValidatorCandidateEvent">RegisterValidatorCandidateEvent</a>&gt;(owner),
        set_operator_events: <a href="account.md#0x1_account_new_event_handle">account::new_event_handle</a>&lt;<a href="validator_ol.md#0x1_validator_SetOperatorEvent">SetOperatorEvent</a>&gt;(owner),
        // add_stake_events: <a href="account.md#0x1_account_new_event_handle">account::new_event_handle</a>&lt;AddStakeEvent&gt;(owner),
        // reactivate_stake_events: <a href="account.md#0x1_account_new_event_handle">account::new_event_handle</a>&lt;ReactivateStakeEvent&gt;(owner),
        rotate_consensus_key_events: <a href="account.md#0x1_account_new_event_handle">account::new_event_handle</a>&lt;<a href="validator_ol.md#0x1_validator_RotateConsensusKeyEvent">RotateConsensusKeyEvent</a>&gt;(owner),
        update_network_and_fullnode_addresses_events: <a href="account.md#0x1_account_new_event_handle">account::new_event_handle</a>&lt;<a href="validator_ol.md#0x1_validator_UpdateNetworkAndFullnodeAddressesEvent">UpdateNetworkAndFullnodeAddressesEvent</a>&gt;(owner),
        // increase_lockup_events: <a href="account.md#0x1_account_new_event_handle">account::new_event_handle</a>&lt;IncreaseLockupEvent&gt;(owner),
        join_validator_set_events: <a href="account.md#0x1_account_new_event_handle">account::new_event_handle</a>&lt;<a href="validator_ol.md#0x1_validator_JoinValidatorSetEvent">JoinValidatorSetEvent</a>&gt;(owner),
        distribute_rewards_events: <a href="account.md#0x1_account_new_event_handle">account::new_event_handle</a>&lt;<a href="validator_ol.md#0x1_validator_DistributeRewardsEvent">DistributeRewardsEvent</a>&gt;(owner),
        // unlock_stake_events: <a href="account.md#0x1_account_new_event_handle">account::new_event_handle</a>&lt;UnlockStakeEvent&gt;(owner),
        // withdraw_stake_events: <a href="account.md#0x1_account_new_event_handle">account::new_event_handle</a>&lt;WithdrawStakeEvent&gt;(owner),
        leave_validator_set_events: <a href="account.md#0x1_account_new_event_handle">account::new_event_handle</a>&lt;<a href="validator_ol.md#0x1_validator_LeaveValidatorSetEvent">LeaveValidatorSetEvent</a>&gt;(owner),
    });

}
</code></pre>



</details>

<a name="0x1_validator_set_operator"></a>

## Function `set_operator`

Allows an owner to change the operator of the stake pool.


<pre><code><b>public</b> <b>fun</b> <a href="validator_ol.md#0x1_validator_set_operator">set_operator</a>(owner: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>, new_operator: <b>address</b>)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="validator_ol.md#0x1_validator_set_operator">set_operator</a>(owner: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>, new_operator: <b>address</b>) <b>acquires</b> <a href="validator_ol.md#0x1_validator_StakePool">StakePool</a> {
    // <b>let</b> pool_address = owner_cap.pool_address;
    <b>let</b> pool_address = <a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer_address_of">signer::address_of</a>(owner);
    <a href="validator_ol.md#0x1_validator_assert_stake_pool_exists">assert_stake_pool_exists</a>(pool_address);
    <b>let</b> stake_pool = <b>borrow_global_mut</b>&lt;<a href="validator_ol.md#0x1_validator_StakePool">StakePool</a>&gt;(pool_address);
    <b>let</b> old_operator = stake_pool.operator_address;
    stake_pool.operator_address = new_operator;

    <a href="event.md#0x1_event_emit_event">event::emit_event</a>(
        &<b>mut</b> stake_pool.set_operator_events,
        <a href="validator_ol.md#0x1_validator_SetOperatorEvent">SetOperatorEvent</a> {
            pool_address,
            old_operator,
            new_operator,
        },
    );
}
</code></pre>



</details>

<a name="0x1_validator_rotate_consensus_key"></a>

## Function `rotate_consensus_key`

Rotate the consensus key of the validator, it'll take effect in next epoch.


<pre><code><b>public</b> entry <b>fun</b> <a href="validator_ol.md#0x1_validator_rotate_consensus_key">rotate_consensus_key</a>(operator: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>, pool_address: <b>address</b>, new_consensus_pubkey: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;, proof_of_possession: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> entry <b>fun</b> <a href="validator_ol.md#0x1_validator_rotate_consensus_key">rotate_consensus_key</a>(
    operator: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>,
    pool_address: <b>address</b>,
    new_consensus_pubkey: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;,
    proof_of_possession: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;,
) <b>acquires</b> <a href="validator_ol.md#0x1_validator_StakePool">StakePool</a>, <a href="validator_ol.md#0x1_validator_ValidatorConfig">ValidatorConfig</a> {
    <a href="validator_ol.md#0x1_validator_assert_stake_pool_exists">assert_stake_pool_exists</a>(pool_address);
    <b>let</b> stake_pool = <b>borrow_global_mut</b>&lt;<a href="validator_ol.md#0x1_validator_StakePool">StakePool</a>&gt;(pool_address);
    <b>assert</b>!(<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer_address_of">signer::address_of</a>(operator) == stake_pool.operator_address, <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_unauthenticated">error::unauthenticated</a>(<a href="validator_ol.md#0x1_validator_ENOT_OPERATOR">ENOT_OPERATOR</a>));

    <b>assert</b>!(<b>exists</b>&lt;<a href="validator_ol.md#0x1_validator_ValidatorConfig">ValidatorConfig</a>&gt;(pool_address), <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_not_found">error::not_found</a>(<a href="validator_ol.md#0x1_validator_EVALIDATOR_CONFIG">EVALIDATOR_CONFIG</a>));
    <b>let</b> validator_info = <b>borrow_global_mut</b>&lt;<a href="validator_ol.md#0x1_validator_ValidatorConfig">ValidatorConfig</a>&gt;(pool_address);
    <b>let</b> old_consensus_pubkey = validator_info.consensus_pubkey;
    // Checks the <b>public</b> key <b>has</b> a valid proof-of-possession <b>to</b> prevent rogue-key attacks.
    <b>let</b> pubkey_from_pop = &<b>mut</b> <a href="../../aptos-stdlib/doc/bls12381.md#0x1_bls12381_public_key_from_bytes_with_pop">bls12381::public_key_from_bytes_with_pop</a>(
        new_consensus_pubkey,
        &<a href="../../aptos-stdlib/doc/bls12381.md#0x1_bls12381_proof_of_possession_from_bytes">bls12381::proof_of_possession_from_bytes</a>(proof_of_possession)
    );
    <b>assert</b>!(<a href="../../aptos-stdlib/../move-stdlib/doc/option.md#0x1_option_is_some">option::is_some</a>(pubkey_from_pop), <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_invalid_argument">error::invalid_argument</a>(<a href="validator_ol.md#0x1_validator_EINVALID_PUBLIC_KEY">EINVALID_PUBLIC_KEY</a>));
    validator_info.consensus_pubkey = new_consensus_pubkey;

    <a href="event.md#0x1_event_emit_event">event::emit_event</a>(
        &<b>mut</b> stake_pool.rotate_consensus_key_events,
        <a href="validator_ol.md#0x1_validator_RotateConsensusKeyEvent">RotateConsensusKeyEvent</a> {
            pool_address,
            old_consensus_pubkey,
            new_consensus_pubkey,
        },
    );
}
</code></pre>



</details>

<a name="0x1_validator_update_network_and_fullnode_addresses"></a>

## Function `update_network_and_fullnode_addresses`

Update the network and full node addresses of the validator. This only takes effect in the next epoch.


<pre><code><b>public</b> entry <b>fun</b> <a href="validator_ol.md#0x1_validator_update_network_and_fullnode_addresses">update_network_and_fullnode_addresses</a>(operator: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>, pool_address: <b>address</b>, new_network_addresses: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;, new_fullnode_addresses: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> entry <b>fun</b> <a href="validator_ol.md#0x1_validator_update_network_and_fullnode_addresses">update_network_and_fullnode_addresses</a>(
    operator: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>,
    pool_address: <b>address</b>,
    new_network_addresses: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;,
    new_fullnode_addresses: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u8&gt;,
) <b>acquires</b> <a href="validator_ol.md#0x1_validator_StakePool">StakePool</a>, <a href="validator_ol.md#0x1_validator_ValidatorConfig">ValidatorConfig</a> {
    <a href="validator_ol.md#0x1_validator_assert_stake_pool_exists">assert_stake_pool_exists</a>(pool_address);
    <b>let</b> stake_pool = <b>borrow_global_mut</b>&lt;<a href="validator_ol.md#0x1_validator_StakePool">StakePool</a>&gt;(pool_address);
    <b>assert</b>!(<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer_address_of">signer::address_of</a>(operator) == stake_pool.operator_address, <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_unauthenticated">error::unauthenticated</a>(<a href="validator_ol.md#0x1_validator_ENOT_OPERATOR">ENOT_OPERATOR</a>));

    <b>assert</b>!(<b>exists</b>&lt;<a href="validator_ol.md#0x1_validator_ValidatorConfig">ValidatorConfig</a>&gt;(pool_address), <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_not_found">error::not_found</a>(<a href="validator_ol.md#0x1_validator_EVALIDATOR_CONFIG">EVALIDATOR_CONFIG</a>));
    <b>let</b> validator_info = <b>borrow_global_mut</b>&lt;<a href="validator_ol.md#0x1_validator_ValidatorConfig">ValidatorConfig</a>&gt;(pool_address);
    <b>let</b> old_network_addresses = validator_info.network_addresses;
    validator_info.network_addresses = new_network_addresses;
    <b>let</b> old_fullnode_addresses = validator_info.fullnode_addresses;
    validator_info.fullnode_addresses = new_fullnode_addresses;

    <a href="event.md#0x1_event_emit_event">event::emit_event</a>(
        &<b>mut</b> stake_pool.update_network_and_fullnode_addresses_events,
        <a href="validator_ol.md#0x1_validator_UpdateNetworkAndFullnodeAddressesEvent">UpdateNetworkAndFullnodeAddressesEvent</a> {
            pool_address,
            old_network_addresses,
            new_network_addresses,
            old_fullnode_addresses,
            new_fullnode_addresses,
        },
    );
}
</code></pre>



</details>

<a name="0x1_validator_join_validator_set"></a>

## Function `join_validator_set`

This can only called by the operator of the validator/staking pool.


<pre><code><b>public</b> entry <b>fun</b> <a href="validator_ol.md#0x1_validator_join_validator_set">join_validator_set</a>(operator: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>, pool_address: <b>address</b>)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> entry <b>fun</b> <a href="validator_ol.md#0x1_validator_join_validator_set">join_validator_set</a>(
    operator: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>,
    pool_address: <b>address</b>
) <b>acquires</b> <a href="validator_ol.md#0x1_validator_ValidatorConfig">ValidatorConfig</a>, <a href="validator_ol.md#0x1_validator_ValidatorSet">ValidatorSet</a> {
    // <b>assert</b>!(
    //     staking_config::get_allow_validator_set_change(&staking_config::get()),
    //     <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_invalid_argument">error::invalid_argument</a>(ENO_POST_GENESIS_VALIDATOR_SET_CHANGE_ALLOWED),
    // );

    <a href="validator_ol.md#0x1_validator_join_validator_set_internal">join_validator_set_internal</a>(operator, pool_address);
}
</code></pre>



</details>

<a name="0x1_validator_join_validator_set_internal"></a>

## Function `join_validator_set_internal`

Request to have <code>pool_address</code> join the validator set. Can only be called after calling <code>initialize_validator</code>.
If the validator has the required stake (more than minimum and less than maximum allowed), they will be
added to the pending_active queue. All validators in this queue will be added to the active set when the next
epoch starts (eligibility will be rechecked).

This internal version can only be called by the Genesis module during Genesis.


<pre><code><b>public</b>(<b>friend</b>) <b>fun</b> <a href="validator_ol.md#0x1_validator_join_validator_set_internal">join_validator_set_internal</a>(_operator: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>, pool_address: <b>address</b>)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b>(<b>friend</b>) <b>fun</b> <a href="validator_ol.md#0x1_validator_join_validator_set_internal">join_validator_set_internal</a>(
    _operator: &<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer">signer</a>,
    pool_address: <b>address</b>
) <b>acquires</b> <a href="validator_ol.md#0x1_validator_ValidatorConfig">ValidatorConfig</a>, <a href="validator_ol.md#0x1_validator_ValidatorSet">ValidatorSet</a> {
    // <a href="validator_ol.md#0x1_validator_assert_stake_pool_exists">assert_stake_pool_exists</a>(pool_address);
    // <b>let</b> stake_pool = <b>borrow_global_mut</b>&lt;<a href="validator_ol.md#0x1_validator_StakePool">StakePool</a>&gt;(pool_address);
    // <b>assert</b>!(<a href="../../aptos-stdlib/../move-stdlib/doc/signer.md#0x1_signer_address_of">signer::address_of</a>(operator) == stake_pool.operator_address, <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_unauthenticated">error::unauthenticated</a>(<a href="validator_ol.md#0x1_validator_ENOT_OPERATOR">ENOT_OPERATOR</a>));
    // <b>assert</b>!(
    //     <a href="validator_ol.md#0x1_validator_get_validator_state">get_validator_state</a>(pool_address) == <a href="validator_ol.md#0x1_validator_VALIDATOR_STATUS_INACTIVE">VALIDATOR_STATUS_INACTIVE</a>,
    //     <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_invalid_state">error::invalid_state</a>(<a href="validator_ol.md#0x1_validator_EALREADY_ACTIVE_VALIDATOR">EALREADY_ACTIVE_VALIDATOR</a>),
    // );

    // <b>let</b> config = staking_config::get();
    // <b>let</b> (minimum_stake, maximum_stake) = staking_config::get_required_stake(&config);
    // <b>let</b> voting_power = get_next_epoch_voting_power(stake_pool);
    // <b>assert</b>!(voting_power &gt;= minimum_stake, <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_invalid_argument">error::invalid_argument</a>(ESTAKE_TOO_LOW));
    // <b>assert</b>!(voting_power &lt;= maximum_stake, <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_invalid_argument">error::invalid_argument</a>(ESTAKE_TOO_HIGH));

    // Track and validate <a href="voting.md#0x1_voting">voting</a> power increase.
    // update_voting_power_increase(voting_power);

    // Add <a href="validator_ol.md#0x1_validator">validator</a> <b>to</b> pending_active, <b>to</b> be activated in the next epoch.
    <b>let</b> validator_config = <b>borrow_global_mut</b>&lt;<a href="validator_ol.md#0x1_validator_ValidatorConfig">ValidatorConfig</a>&gt;(pool_address);
    <b>assert</b>!(!<a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_is_empty">vector::is_empty</a>(&validator_config.consensus_pubkey), <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_invalid_argument">error::invalid_argument</a>(<a href="validator_ol.md#0x1_validator_EINVALID_PUBLIC_KEY">EINVALID_PUBLIC_KEY</a>));

    // Validate the current <a href="validator_ol.md#0x1_validator">validator</a> set size <b>has</b> not exceeded the limit.
    <b>let</b> validator_set = <b>borrow_global_mut</b>&lt;<a href="validator_ol.md#0x1_validator_ValidatorSet">ValidatorSet</a>&gt;(@aptos_framework);
    // TODO: v7: refactor this

    // <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_push_back">vector::push_back</a>(&<b>mut</b> validator_set.pending_active,
    // <a href="validator_ol.md#0x1_validator_generate_validator_info">generate_validator_info</a>(pool_address, stake_pool, *validator_config));

    <b>let</b> validator_set_size = <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_length">vector::length</a>(&validator_set.active_validators) + <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_length">vector::length</a>(&validator_set.pending_active);
    <b>assert</b>!(validator_set_size &lt;= <a href="validator_ol.md#0x1_validator_MAX_VALIDATOR_SET_SIZE">MAX_VALIDATOR_SET_SIZE</a>, <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_invalid_argument">error::invalid_argument</a>(<a href="validator_ol.md#0x1_validator_EVALIDATOR_SET_TOO_LARGE">EVALIDATOR_SET_TOO_LARGE</a>));

    // TODO: v7: refactor this
    // <a href="event.md#0x1_event_emit_event">event::emit_event</a>(
    //     &<b>mut</b> stake_pool.join_validator_set_events,
    //     <a href="validator_ol.md#0x1_validator_JoinValidatorSetEvent">JoinValidatorSetEvent</a> { pool_address },
    // );
}
</code></pre>



</details>

<a name="0x1_validator_is_current_epoch_validator"></a>

## Function `is_current_epoch_validator`

Returns true if the current validator can still vote in the current epoch.
This includes validators that requested to leave but are still in the pending_inactive queue and will be removed
when the epoch starts.


<pre><code><b>public</b> <b>fun</b> <a href="validator_ol.md#0x1_validator_is_current_epoch_validator">is_current_epoch_validator</a>(pool_address: <b>address</b>): bool
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="validator_ol.md#0x1_validator_is_current_epoch_validator">is_current_epoch_validator</a>(pool_address: <b>address</b>): bool <b>acquires</b> <a href="validator_ol.md#0x1_validator_ValidatorSet">ValidatorSet</a> {
    <a href="validator_ol.md#0x1_validator_assert_stake_pool_exists">assert_stake_pool_exists</a>(pool_address);
    <b>let</b> validator_state = <a href="validator_ol.md#0x1_validator_get_validator_state">get_validator_state</a>(pool_address);
    validator_state == <a href="validator_ol.md#0x1_validator_VALIDATOR_STATUS_ACTIVE">VALIDATOR_STATUS_ACTIVE</a> || validator_state == <a href="validator_ol.md#0x1_validator_VALIDATOR_STATUS_PENDING_INACTIVE">VALIDATOR_STATUS_PENDING_INACTIVE</a>
}
</code></pre>



</details>

<a name="0x1_validator_update_performance_statistics"></a>

## Function `update_performance_statistics`

Update the validator performance (proposal statistics). This is only called by block::prologue().
This function cannot abort.


<pre><code><b>public</b>(<b>friend</b>) <b>fun</b> <a href="validator_ol.md#0x1_validator_update_performance_statistics">update_performance_statistics</a>(proposer_index: <a href="../../aptos-stdlib/../move-stdlib/doc/option.md#0x1_option_Option">option::Option</a>&lt;u64&gt;, failed_proposer_indices: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u64&gt;)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b>(<b>friend</b>) <b>fun</b> <a href="validator_ol.md#0x1_validator_update_performance_statistics">update_performance_statistics</a>(proposer_index: Option&lt;u64&gt;, failed_proposer_indices: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;u64&gt;) <b>acquires</b> <a href="validator_ol.md#0x1_validator_ValidatorPerformance">ValidatorPerformance</a> {
    // Validator set cannot change until the end of the epoch, so the <a href="validator_ol.md#0x1_validator">validator</a> index in arguments should
    // match <b>with</b> those of the validators in <a href="validator_ol.md#0x1_validator_ValidatorPerformance">ValidatorPerformance</a> resource.
    <b>let</b> validator_perf = <b>borrow_global_mut</b>&lt;<a href="validator_ol.md#0x1_validator_ValidatorPerformance">ValidatorPerformance</a>&gt;(@aptos_framework);
    <b>let</b> validator_len = <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_length">vector::length</a>(&validator_perf.validators);

    // proposer_index is an <a href="../../aptos-stdlib/../move-stdlib/doc/option.md#0x1_option">option</a> because it can be missing (for NilBlocks)
    <b>if</b> (<a href="../../aptos-stdlib/../move-stdlib/doc/option.md#0x1_option_is_some">option::is_some</a>(&proposer_index)) {
        <b>let</b> cur_proposer_index = <a href="../../aptos-stdlib/../move-stdlib/doc/option.md#0x1_option_extract">option::extract</a>(&<b>mut</b> proposer_index);
        // Here, and in all other <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_borrow">vector::borrow</a>, skip <a href="../../aptos-stdlib/doc/any.md#0x1_any">any</a> <a href="validator_ol.md#0x1_validator">validator</a> indices that are out of bounds,
        // this <b>ensures</b> that this function doesn't <b>abort</b> <b>if</b> there are out of bounds errors.
        <b>if</b> (cur_proposer_index &lt; validator_len) {
            <b>let</b> <a href="validator_ol.md#0x1_validator">validator</a> = <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_borrow_mut">vector::borrow_mut</a>(&<b>mut</b> validator_perf.validators, cur_proposer_index);
            <b>spec</b> {
                <b>assume</b> <a href="validator_ol.md#0x1_validator">validator</a>.successful_proposals + 1 &lt;= <a href="validator_ol.md#0x1_validator_MAX_U64">MAX_U64</a>;
            };
            <a href="validator_ol.md#0x1_validator">validator</a>.successful_proposals = <a href="validator_ol.md#0x1_validator">validator</a>.successful_proposals + 1;
        };
    };

    <b>let</b> f = 0;
    <b>let</b> f_len = <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_length">vector::length</a>(&failed_proposer_indices);
    <b>while</b> ({
        <b>spec</b> {
            <b>invariant</b> len(validator_perf.validators) == validator_len;
        };
        f &lt; f_len
    }) {
        <b>let</b> validator_index = *<a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_borrow">vector::borrow</a>(&failed_proposer_indices, f);
        <b>if</b> (validator_index &lt; validator_len) {
            <b>let</b> <a href="validator_ol.md#0x1_validator">validator</a> = <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_borrow_mut">vector::borrow_mut</a>(&<b>mut</b> validator_perf.validators, validator_index);
            <b>spec</b> {
                <b>assume</b> <a href="validator_ol.md#0x1_validator">validator</a>.failed_proposals + 1 &lt;= <a href="validator_ol.md#0x1_validator_MAX_U64">MAX_U64</a>;
            };
            <a href="validator_ol.md#0x1_validator">validator</a>.failed_proposals = <a href="validator_ol.md#0x1_validator">validator</a>.failed_proposals + 1;
        };
        f = f + 1;
    };
}
</code></pre>



</details>

<a name="0x1_validator_on_new_epoch"></a>

## Function `on_new_epoch`

Triggers at epoch boundary. This function shouldn't abort.

1. Distribute transaction fees and rewards to stake pools of active and pending inactive validators (requested
to leave but not yet removed).
2. Officially move pending active stake to active and move pending inactive stake to inactive.
The staking pool's voting power in this new epoch will be updated to the total active stake.
3. Add pending active validators to the active set if they satisfy requirements so they can vote and remove
pending inactive validators so they no longer can vote.
4. The validator's voting power in the validator set is updated to be the corresponding staking pool's voting
power.


<pre><code><b>public</b>(<b>friend</b>) <b>fun</b> <a href="validator_ol.md#0x1_validator_on_new_epoch">on_new_epoch</a>()
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b>(<b>friend</b>) <b>fun</b> <a href="validator_ol.md#0x1_validator_on_new_epoch">on_new_epoch</a>() <b>acquires</b> <a href="validator_ol.md#0x1_validator_ValidatorPerformance">ValidatorPerformance</a>, <a href="validator_ol.md#0x1_validator_ValidatorSet">ValidatorSet</a> {
    <b>let</b> _validator_set = <b>borrow_global_mut</b>&lt;<a href="validator_ol.md#0x1_validator_ValidatorSet">ValidatorSet</a>&gt;(@aptos_framework);
    // <b>let</b> config = staking_config::get();
    <b>let</b> _validator_perf = <b>borrow_global_mut</b>&lt;<a href="validator_ol.md#0x1_validator_ValidatorPerformance">ValidatorPerformance</a>&gt;(@aptos_framework);

}
</code></pre>



</details>

<a name="0x1_validator_calculate_rewards_amount"></a>

## Function `calculate_rewards_amount`

Calculate the rewards amount.


<pre><code><b>fun</b> <a href="validator_ol.md#0x1_validator_calculate_rewards_amount">calculate_rewards_amount</a>(_stake_amount: u64, _num_successful_proposals: u64, _num_total_proposals: u64, _rewards_rate: u64, _rewards_rate_denominator: u64): u64
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>fun</b> <a href="validator_ol.md#0x1_validator_calculate_rewards_amount">calculate_rewards_amount</a>(
    _stake_amount: u64,
    _num_successful_proposals: u64,
    _num_total_proposals: u64,
    _rewards_rate: u64,
    _rewards_rate_denominator: u64,
): u64 {

    100
}
</code></pre>



</details>

<a name="0x1_validator_distribute_rewards"></a>

## Function `distribute_rewards`

Mint rewards corresponding to current epoch's <code>stake</code> and <code>num_successful_votes</code>.


<pre><code><b>fun</b> <a href="validator_ol.md#0x1_validator_distribute_rewards">distribute_rewards</a>(_stake: &<b>mut</b> <a href="coin.md#0x1_coin_Coin">coin::Coin</a>&lt;<a href="aptos_coin.md#0x1_aptos_coin_AptosCoin">aptos_coin::AptosCoin</a>&gt;, _num_successful_proposals: u64, _num_total_proposals: u64, _rewards_rate: u64, _rewards_rate_denominator: u64): u64
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>fun</b> <a href="validator_ol.md#0x1_validator_distribute_rewards">distribute_rewards</a>(
    _stake: &<b>mut</b> Coin&lt;AptosCoin&gt;,
    _num_successful_proposals: u64,
    _num_total_proposals: u64,
    _rewards_rate: u64,
    _rewards_rate_denominator: u64,
): u64  {
    // TODO
    1000
}
</code></pre>



</details>

<a name="0x1_validator_append"></a>

## Function `append`



<pre><code><b>fun</b> <a href="validator_ol.md#0x1_validator_append">append</a>&lt;T&gt;(v1: &<b>mut</b> <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;T&gt;, v2: &<b>mut</b> <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;T&gt;)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>fun</b> <a href="validator_ol.md#0x1_validator_append">append</a>&lt;T&gt;(v1: &<b>mut</b> <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;T&gt;, v2: &<b>mut</b> <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;T&gt;) {
    <b>while</b> (!<a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_is_empty">vector::is_empty</a>(v2)) {
        <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_push_back">vector::push_back</a>(v1, <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_pop_back">vector::pop_back</a>(v2));
    }
}
</code></pre>



</details>

<a name="0x1_validator_find_validator"></a>

## Function `find_validator`



<pre><code><b>fun</b> <a href="validator_ol.md#0x1_validator_find_validator">find_validator</a>(v: &<a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;<a href="validator_ol.md#0x1_validator_ValidatorInfo">validator::ValidatorInfo</a>&gt;, addr: <b>address</b>): <a href="../../aptos-stdlib/../move-stdlib/doc/option.md#0x1_option_Option">option::Option</a>&lt;u64&gt;
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>fun</b> <a href="validator_ol.md#0x1_validator_find_validator">find_validator</a>(v: &<a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;<a href="validator_ol.md#0x1_validator_ValidatorInfo">ValidatorInfo</a>&gt;, addr: <b>address</b>): Option&lt;u64&gt; {
    <b>let</b> i = 0;
    <b>let</b> len = <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_length">vector::length</a>(v);
    <b>while</b> ({
        <b>spec</b> {
            <b>invariant</b> !(<b>exists</b> j in 0..i: v[j].addr == addr);
        };
        i &lt; len
    }) {
        <b>if</b> (<a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector_borrow">vector::borrow</a>(v, i).addr == addr) {
            <b>return</b> <a href="../../aptos-stdlib/../move-stdlib/doc/option.md#0x1_option_some">option::some</a>(i)
        };
        i = i + 1;
    };
    <a href="../../aptos-stdlib/../move-stdlib/doc/option.md#0x1_option_none">option::none</a>()
}
</code></pre>



</details>

<a name="0x1_validator_generate_validator_info"></a>

## Function `generate_validator_info`



<pre><code><b>fun</b> <a href="validator_ol.md#0x1_validator_generate_validator_info">generate_validator_info</a>(addr: <b>address</b>, _stake_pool: &<a href="validator_ol.md#0x1_validator_StakePool">validator::StakePool</a>, config: <a href="validator_ol.md#0x1_validator_ValidatorConfig">validator::ValidatorConfig</a>): <a href="validator_ol.md#0x1_validator_ValidatorInfo">validator::ValidatorInfo</a>
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>fun</b> <a href="validator_ol.md#0x1_validator_generate_validator_info">generate_validator_info</a>(addr: <b>address</b>, _stake_pool: &<a href="validator_ol.md#0x1_validator_StakePool">StakePool</a>, config: <a href="validator_ol.md#0x1_validator_ValidatorConfig">ValidatorConfig</a>): <a href="validator_ol.md#0x1_validator_ValidatorInfo">ValidatorInfo</a> {
    // <b>let</b> voting_power = get_next_epoch_voting_power(stake_pool);
    <a href="validator_ol.md#0x1_validator_ValidatorInfo">ValidatorInfo</a> {
        addr,
        // voting_power: 1,
        config,
    }
}
</code></pre>



</details>

<a name="0x1_validator_assert_stake_pool_exists"></a>

## Function `assert_stake_pool_exists`



<pre><code><b>fun</b> <a href="validator_ol.md#0x1_validator_assert_stake_pool_exists">assert_stake_pool_exists</a>(pool_address: <b>address</b>)
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>fun</b> <a href="validator_ol.md#0x1_validator_assert_stake_pool_exists">assert_stake_pool_exists</a>(pool_address: <b>address</b>) {
    <b>assert</b>!(<a href="validator_ol.md#0x1_validator_stake_pool_exists">stake_pool_exists</a>(pool_address), <a href="../../aptos-stdlib/../move-stdlib/doc/error.md#0x1_error_invalid_argument">error::invalid_argument</a>(<a href="validator_ol.md#0x1_validator_ESTAKE_POOL_DOES_NOT_EXIST">ESTAKE_POOL_DOES_NOT_EXIST</a>));
}
</code></pre>



</details>

<a name="@Specification_1"></a>

## Specification



<a name="0x1_validator_spec_contains"></a>


<pre><code><b>fun</b> <a href="validator_ol.md#0x1_validator_spec_contains">spec_contains</a>(validators: <a href="../../aptos-stdlib/../move-stdlib/doc/vector.md#0x1_vector">vector</a>&lt;<a href="validator_ol.md#0x1_validator_ValidatorInfo">ValidatorInfo</a>&gt;, addr: <b>address</b>): bool {
   <b>exists</b> i in 0..len(validators): validators[i].addr == addr
}
</code></pre>




<a name="0x1_validator_spec_is_current_epoch_validator"></a>


<pre><code><b>fun</b> <a href="validator_ol.md#0x1_validator_spec_is_current_epoch_validator">spec_is_current_epoch_validator</a>(pool_address: <b>address</b>): bool {
   <b>let</b> validator_set = <b>global</b>&lt;<a href="validator_ol.md#0x1_validator_ValidatorSet">ValidatorSet</a>&gt;(@aptos_framework);
   !<a href="validator_ol.md#0x1_validator_spec_contains">spec_contains</a>(validator_set.pending_active, pool_address)
       && (<a href="validator_ol.md#0x1_validator_spec_contains">spec_contains</a>(validator_set.active_validators, pool_address)
       || <a href="validator_ol.md#0x1_validator_spec_contains">spec_contains</a>(validator_set.pending_inactive, pool_address))
}
</code></pre>


[move-book]: https://aptos.dev/guides/move-guides/book/SUMMARY
