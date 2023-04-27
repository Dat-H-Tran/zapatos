spec aptos_framework::validator {
    spec fun spec_contains(validators: vector<ValidatorInfo>, addr: address): bool {
        exists i in 0..len(validators): validators[i].addr == addr
    }


    spec fun spec_is_current_epoch_validator(pool_address: address): bool {
        let validator_set = global<ValidatorSet>(@aptos_framework);
        !spec_contains(validator_set.pending_active, pool_address)
            && (spec_contains(validator_set.active_validators, pool_address)
            || spec_contains(validator_set.pending_inactive, pool_address))
    }

}
