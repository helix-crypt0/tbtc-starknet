// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^1.0.0
use starknet::ContractAddress;

#[starknet::interface]
trait IL2TBTC<TContractState> {
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
    fn burn(ref self: TContractState, value: u256);
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
    fn addMinter(ref self: TContractState, minter: ContractAddress);
    fn removeMinter(ref self: TContractState, minter: ContractAddress);
    fn addGuardian(ref self: TContractState, guardian: ContractAddress);
    fn removeGuardian(ref self: TContractState, guardian: ContractAddress);
    fn getMinters(ref self: TContractState) -> Array<ContractAddress>;
    fn getGuardians(ref self: TContractState) -> Array<ContractAddress>;
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
        Vec, MutableVecTrait
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

        // need getters for these
        isMinter: Map<ContractAddress, bool>,
        minters:  Vec<ContractAddress>,
        isGuardian: Map<ContractAddress, bool>,
        guardians: Vec<ContractAddress>,
    }

    #[derive(Drop, starknet::Event)]
    struct MinterAdded {
        minter: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct MinterRemoved {
        minter: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct GuardianAdded {
        guardian: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct GuardianRemoved {
        guardian: ContractAddress,
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
        GuardianAdded: GuardianAdded,
        GuardianRemoved: GuardianRemoved,
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

    // Internal implementation for role access control
    #[generate_trait]
    impl InternalRolesImpl of InternalRolesTrait {

        fn is_minter(self: @ContractState, caller: ContractAddress) -> bool {
            self.isMinter.entry(caller).read()
        }

        fn is_guardian(self: @ContractState, caller: ContractAddress) -> bool {
            self.isGuardian.entry(caller).read()
        }
    }
    
    #[generate_trait]
    #[abi(per_item)]
    impl ExternalImpl of ExternalTrait {
        // assert minter for mints
        // assert guardian for pause
        #[external(v0)]
        fn pause(ref self: ContractState) {
            let caller = get_caller_address();
            assert(InternalRolesImpl::is_guardian(@self, caller), 'Caller is not a guardian');
            self.pausable.pause();
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
            
            // Check if caller is owner or minter
            let is_owner = self.ownable.owner() == caller;
            let is_minter = InternalRolesImpl::is_minter(@self, caller);
            
            assert(is_owner || is_minter, 'not owner or minter');
            self.erc20.mint(recipient, amount);
        }
        
        #[external(v0)]
        fn addMinter(ref self: ContractState, minter: ContractAddress) {
            self.ownable.assert_only_owner();
            assert(!InternalRolesImpl::is_minter(@self, minter), 'Already a minter');
            self.isMinter.entry(minter).write(true);
            self.minters.push(minter);
            self.emit(MinterAdded { minter });
        }

        #[external(v0)]
        fn removeMinter(ref self: ContractState, minter: ContractAddress) {
            self.ownable.assert_only_owner();
            self.isMinter.entry(minter).write(false);
    
            let minters_len = self.minters.len();
            for i in 0..minters_len {
                if self.minters.at(i).read() == minter {
                    if i < minters_len - 1 {
                        let last_minter = self.minters.at(minters_len - 1).read();
                        self.minters.at(i).write(last_minter);
                    }
                    // Directly call pop() on the storage vector.
                    let _ = self.minters.pop();
                    break;
                }
            };
    
            self.emit(MinterRemoved { minter });
        }

        #[external(v0)]
        fn addGuardian(ref self: ContractState, guardian: ContractAddress) {
            self.ownable.assert_only_owner();
            assert(!self.isGuardian.entry(guardian).read(), 'Already a guardian');
            self.isGuardian.entry(guardian).write(true);
            self.guardians.push(guardian);
            self.emit(GuardianAdded { guardian });
        }

        #[external(v0)]
        fn removeGuardian(ref self: ContractState, guardian: ContractAddress) {
            self.ownable.assert_only_owner();
            self.isGuardian.entry(guardian).write(false);

            let guardians_len = self.guardians.len();
            for i in 0..guardians_len {
                if self.guardians.at(i).read() == guardian {
                    if i < guardians_len - 1 {
                        let last_guardian = self.guardians.at(guardians_len - 1).read();
                        self.guardians.at(i).write(last_guardian);
                    }
                    let _ = self.guardians.pop();
                    break;
                }
            };
            

            self.emit(GuardianRemoved { guardian });
        }

        #[external(v0)]
        fn getMinters(ref self: ContractState) -> Array<ContractAddress> {
            let mut minters_array = array![];
            let minters_len = self.minters.len();
            for i in 0..minters_len {
                minters_array.append(self.minters.at(i).read());
            }
            minters_array
        }

        #[external(v0)]
        fn getGuardians(ref self: ContractState) -> Array<ContractAddress> {
            let mut guardians_array = array![];
            let guardians_len = self.guardians.len();
            for i in 0..guardians_len {
                guardians_array.append(self.guardians.at(i).read());
            }
            guardians_array
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


