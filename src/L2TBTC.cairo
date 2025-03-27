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
    fn isMinter(self: @TContractState, account: ContractAddress) -> bool;
    fn isGuardian(self: @TContractState, account: ContractAddress) -> bool;
}   

#[starknet::contract]
mod L2TBTC {
    use starknet::event::EventEmitter;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::security::pausable::PausableComponent;
    use openzeppelin::token::erc20::ERC20Component;
    use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use openzeppelin::token::erc721::interface::{ERC721ABIDispatcher, ERC721ABIDispatcherTrait};
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

        isMinter: Map<ContractAddress, bool>,
        minters:  Vec<ContractAddress>,
        isGuardian: Map<ContractAddress, bool>,
        guardians: Vec<ContractAddress>,
    }

    const ALREADY_MINTER: felt252 = 'Already a minter';
    const NOT_MINTER: felt252 = 'Not a minter';
    const NOT_GUARDIAN: felt252 = 'Not a guardian';
    const ALREADY_GUARDIAN: felt252 = 'Already a guardian';
    const NOT_OWNER: felt252 = 'Not owner';

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
        self.erc20.initializer("Starknet tBTC", "tBTC");
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

        #[external(v0)]
        fn addMinter(ref self: ContractState, minter: ContractAddress) {
            self.ownable.assert_only_owner();
            assert(!InternalRolesImpl::is_minter(@self, minter), ALREADY_MINTER);
            self.isMinter.entry(minter).write(true);
            self.minters.push(minter);
            self.emit(MinterAdded { minter });
        }

        #[external(v0)]
        fn removeMinter(ref self: ContractState, minter: ContractAddress) {
            self.ownable.assert_only_owner();
            assert(InternalRolesImpl::is_minter(@self, minter), NOT_MINTER);

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
            assert(!self.isGuardian.entry(guardian).read(), ALREADY_GUARDIAN);
            self.isGuardian.entry(guardian).write(true);
            self.guardians.push(guardian);
            self.emit(GuardianAdded { guardian });
        }

        #[external(v0)]
        fn removeGuardian(ref self: ContractState, guardian: ContractAddress) {
            self.ownable.assert_only_owner();
            assert(InternalRolesImpl::is_guardian(@self, guardian), NOT_GUARDIAN);
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

        /// @notice Allows the owner of the token contract to recover any ERC20 sent mistakenly to the token contract address
        /// @param token The address of the token to be recovered
        /// @param recipient The token recipient address that will receive recovered tokens
        /// @param amount The amount to be recovered
        #[external(v0)]
        fn recoverERC20(
            ref self: ContractState,
            token: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            self.ownable.assert_only_owner();
            let erc20 = ERC20ABIDispatcher { contract_address: token };
            let success = erc20.transfer(recipient, amount);
            assert(success, 'ERC20 transfer failed');
        }

        /// @notice Allows the owner of the token contract to recover any ERC721 sent mistakenly to the token contract address
        /// @param token The address of the token to be recovered
        /// @param recipient The token recipient address that will receive recovered token
        /// @param token_id The ID of the ERC721 token to be recovered
        /// @param data Additional data to be passed to the safe transfer
        #[external(v0)]
        fn recoverERC721(
            ref self: ContractState,
            token: ContractAddress,
            recipient: ContractAddress,
            token_id: u256,
            data: Array<felt252>
        ) {
            self.ownable.assert_only_owner();
            let erc721 = ERC721ABIDispatcher { contract_address: token };
            erc721.safe_transfer_from(get_caller_address(), recipient, token_id, data.span());
        }

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
        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            self.pausable.assert_not_paused();

            let caller = get_caller_address();
            assert(InternalRolesImpl::is_minter(@self, caller), NOT_MINTER);

            self.erc20.mint(recipient, amount);
        }

        #[external(v0)]
        fn burn(ref self: ContractState, value: u256) {
            self.pausable.assert_not_paused();
            self.erc20.burn(get_caller_address(), value);
        }

        #[external(v0)]
        fn burnFrom(ref self: ContractState, account: ContractAddress, value: u256) {
            self.pausable.assert_not_paused();
            let caller = get_caller_address();
            // Spend allowance
            self.erc20._spend_allowance(account, caller, value);
            // Burn tokens
            self.erc20.burn(account, value);
        }

        #[external(v0)]
        fn getMinters(self: @ContractState) -> Array<ContractAddress> {
            let mut minters_array = array![];
            for i in 0..self.minters.len() {
                minters_array.append(self.minters.at(i).read());
            }
            minters_array
        }

        #[external(v0)]
        fn getGuardians(self: @ContractState) -> Array<ContractAddress> {
            let mut guardians_array = array![];
            for i in 0..self.guardians.len() {
                guardians_array.append(self.guardians.at(i).read());
            }
            guardians_array
        }

        #[external(v0)]
        fn isMinter(self: @ContractState, account: ContractAddress) -> bool {
            InternalRolesImpl::is_minter(self, account)
        }

        #[external(v0)]
        fn isGuardian(self: @ContractState, account: ContractAddress) -> bool {
            InternalRolesImpl::is_guardian(self, account)
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
