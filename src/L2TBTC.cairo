// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^1.0.0
use starknet::ContractAddress;

#[starknet::interface]
trait IL2TBTC<TContractState> {
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
    fn burn(ref self: TContractState, value: u256);
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
}

#[starknet::contract]
mod L2TBTC {
    use starknet::event::EventEmitter;
use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::security::pausable::PausableComponent;
    use openzeppelin::token::erc20::ERC20Component;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use openzeppelin::upgrades::UpgradeableComponent;
    use starknet::{ClassHash, ContractAddress, get_caller_address};
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry, Map,
        Vec, VecTrait, MutableVecTrait
    };

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    // External
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;

    // Internal
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
    impl PausableInternalImpl = PausableComponent::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,

        is_minter: Map<ContractAddress, bool>,
        minters:  Vec<ContractAddress>,

    }

    #[derive(Drop, starknet::Event)]
    struct MinterAdded {
        minter: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct MinterRemoved {
        minter: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,

        MinterAdded: MinterAdded,
        MinterRemoved: MinterRemoved,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.erc20.initializer("L2TBTC", "TBTC");
        self.ownable.initializer(owner);
    }

    impl ERC20HooksImpl of ERC20Component::ERC20HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC20Component::ComponentState<ContractState>,
            from: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {
            let contract_state = self.get_contract();
            contract_state.pausable.assert_not_paused();
        }
    }
    
    #[generate_trait]
    #[abi(per_item)]
    impl ExternalImpl of ExternalTrait {
        #[external(v0)]
        fn pause(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.pausable.pause();
            //println!("pause");
        }

        #[external(v0)]
        fn unpause(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.pausable.unpause();
        }

        #[external(v0)]
        fn burn(ref self: ContractState, value: u256) {
            self.erc20.burn(get_caller_address(), value);
        }

        #[external(v0)]
        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            let caller = get_caller_address();
            let num_minters = self.minters.len();
            let mut is_minter = false;
            for i in 0..num_minters {
                let minter = self.minters.at(i).read();
                if minter == caller {
                    is_minter = true;
                    break;
                }
            };
            assert(self.ownable.owner() == caller || is_minter, 'not owner or minter');
            self.erc20.mint(recipient, amount);
        }

        #[external(v0)]
        fn add_minter(ref self: ContractState, minter: ContractAddress) {
            self.ownable.assert_only_owner();
            self.is_minter.entry(minter).write(true);
            self.minters.append().write(minter);
            self.emit(MinterAdded { minter });
        }

        #[external(v0)]
        fn remove_minter(ref self: ContractState, minter: ContractAddress) {
            self.ownable.assert_only_owner();
            self.is_minter.entry(minter).write(false);
            // Find and remove the minter from the array
            self.emit(MinterRemoved { minter });
        }
    }



    //
    // Upgradeable
    //
    
    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
    }
}


