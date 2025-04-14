// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^1.0.0
use starknet::ContractAddress;

/// @notice Interface for the L2TBTC contract defining all external functions
/// @dev Contains functions for pausing, burning, minting, and role management
#[starknet::interface]
pub trait IL2TBTC<TContractState> {
    /// @notice Pause the contract operations
    fn pause(ref self: TContractState);
    
    /// @notice Unpause the contract operations
    fn unpause(ref self: TContractState);
    
    /// @notice Burn tokens from the caller's balance
    /// @param value: u256 - The amount of tokens to burn
    fn permissioned_burn(ref self: TContractState, value: u256);

    /// @notice Burn tokens from an account, using the caller's allowance
    /// @param account: ContractAddress - The address whose tokens will be burned
    /// @param value: u256 - The amount of tokens to burn
    fn burn_from(ref self: TContractState, account: ContractAddress, value: u256);
    
    /// @notice Mint new tokens to a recipient
    /// @param recipient: ContractAddress - The address receiving the minted tokens
    /// @param amount: u256 - The amount of tokens to mint
    fn permissioned_mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
    
    /// @notice Add a new address to the minters list
    /// @param minter: ContractAddress - The address to add as a minter
    fn add_minter(ref self: TContractState, minter: ContractAddress);
    
    /// @notice Remove an address from the minters list
    /// @param minter: ContractAddress - The address to remove from minters
    fn remove_minter(ref self: TContractState, minter: ContractAddress);
    
    /// @notice Add a new address to the guardians list
    /// @param guardian: ContractAddress - The address to add as a guardian
    fn add_guardian(ref self: TContractState, guardian: ContractAddress);
    
    /// @notice Remove an address from the guardians list
    /// @param guardian: ContractAddress - The address to remove from guardians
    fn remove_guardian(ref self: TContractState, guardian: ContractAddress);
    
    /// @notice Get all minter addresses
    /// @return Array<ContractAddress> - Array of all minter addresses
    fn get_minters(ref self: TContractState) -> Array<ContractAddress>;
    
    /// @notice Get all guardian addresses
    /// @return Array<ContractAddress> - Array of all guardian addresses
    fn get_guardians(ref self: TContractState) -> Array<ContractAddress>;
    
    /// @notice Check if an account is a minter
    /// @param account: ContractAddress - The address to check
    /// @return bool - True if the account is a minter, false otherwise
    fn is_minter(self: @TContractState, account: ContractAddress) -> bool;
    
    /// @notice Check if an account is a guardian
    /// @param account: ContractAddress - The address to check
    /// @return bool - True if the account is a guardian, false otherwise
    fn is_guardian(self: @TContractState, account: ContractAddress) -> bool;

    /// @notice Check if the contract is paused
    /// @return bool - True if the contract is paused, false otherwise
    fn is_paused(self: @TContractState) -> bool;

    /// @notice Recovers ERC20 tokens accidentally sent to this contract
    /// @dev Only the contract owner can recover tokens
    /// @param token: ContractAddress - The address of the ERC20 token to recover
    /// @param recipient: ContractAddress - The address that will receive the recovered tokens
    /// @param amount: u256 - The amount of tokens to recover
    fn recover_ERC20(ref self: TContractState, token: ContractAddress, recipient: ContractAddress, amount: u256);

    /// @notice Recovers ERC721 tokens accidentally sent to this contract
    /// @dev Only the contract owner can recover tokens
    /// @param token: ContractAddress - The address of the ERC721 token to recover
    /// @param recipient: ContractAddress - The address that will receive the recovered token
    /// @param token_id: u256 - The ID of the ERC721 token to recover
    /// @param data: Array<felt252> - Additional data to pass to the safe transfer function
    fn recover_ERC721(ref self: TContractState, token: ContractAddress, recipient: ContractAddress, token_id: u256, data: Array<felt252>);
    
}  

#[starknet::contract]
pub mod L2TBTC {
    use starknet::event::EventEmitter;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::security::pausable::PausableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::utils::cryptography::nonces::NoncesComponent;

    use openzeppelin::utils::snip12::{SNIP12Metadata, SNIP12HashSpanImpl};


    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use openzeppelin::token::erc721::interface::{ERC721ABIDispatcher, ERC721ABIDispatcherTrait};
    
    use starknet::{ClassHash, ContractAddress, get_caller_address};
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry, Map,
        Vec, VecTrait, MutableVecTrait
    };

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: NoncesComponent, storage: nonces, event: NoncesEvent);

    // External
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20PermitImpl = ERC20Component::ERC20PermitImpl<ContractState>;
    
    impl SNIP12MetadataImpl of SNIP12Metadata {
        fn name() -> felt252 {
            'Starknet tBTC'
        }
    
        fn version() -> felt252 { '1.0.0' }
    }

    // Internal
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
    impl PausableInternalImpl = PausableComponent::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;
    impl NoncesInternalImpl = NoncesComponent::InternalImpl<ContractState>;

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
        #[substorage(v0)]
        nonces: NoncesComponent::Storage,

        /// @notice Indicates if the given address is a minter. Only minters can
        ///         mint the token.
        is_minter_map: Map<ContractAddress, bool>,
        /// @notice List of all minters.
        minters:  Vec<ContractAddress>,

        /// @notice Indicates if the given address is a guardian. Only guardians can
        ///         pause the contract.
        is_guardian_map: Map<ContractAddress, bool>,
        /// @notice List of all guardians.
        guardians: Vec<ContractAddress>,
    }

    /// @notice Error message when an address is already a minter
    const ALREADY_MINTER: felt252 = 'Already a minter';
    /// @notice Error message when an address is not a minter
    const NOT_MINTER: felt252 = 'Not a minter';
    /// @notice Error message when an address is not a guardian
    const NOT_GUARDIAN: felt252 = 'Not a guardian';
    /// @notice Error message when an address is already a guardian
    const ALREADY_GUARDIAN: felt252 = 'Already a guardian';

    /// @notice Event emitted when a new minter is added
    /// @param minter: ContractAddress - The address added as a minter
    #[derive(Drop, starknet::Event)]
    pub struct MinterAdded {
        pub minter: ContractAddress,
    }

    /// @notice Event emitted when a minter is removed
    /// @param minter: ContractAddress - The address removed from minters
    #[derive(Drop, starknet::Event)]
    pub struct MinterRemoved {
        pub minter: ContractAddress,
    }

    /// @notice Event emitted when a new guardian is added
    /// @param guardian: ContractAddress - The address added as a guardian
    #[derive(Drop, starknet::Event)]
    pub struct GuardianAdded {
        pub guardian: ContractAddress,
    }

    /// @notice Event emitted when a guardian is removed
    /// @param guardian: ContractAddress - The address removed from guardians
    #[derive(Drop, starknet::Event)]
    pub struct GuardianRemoved {
        pub guardian: ContractAddress,
    }

    /// @notice Event emitted when ERC20 tokens are recovered from the contract
    /// @param token: ContractAddress - The address of the recovered ERC20 token
    /// @param recipient: ContractAddress - The address that received the tokens
    /// @param amount: u256 - The amount of tokens recovered
    #[derive(Drop, starknet::Event)]
    pub struct ERC20Recovered {
        pub token: ContractAddress,
        pub recipient: ContractAddress,
        pub amount: u256,
    }

    /// @notice Event emitted when ERC721 tokens are recovered from the contract
    /// @param token: ContractAddress - The address of the recovered ERC721 token
    /// @param recipient: ContractAddress - The address that received the token
    /// @param token_id: u256 - The ID of the recovered token
    #[derive(Drop, starknet::Event)]
    pub struct ERC721Recovered {
        pub token: ContractAddress,
        pub recipient: ContractAddress,
        pub token_id: u256,
    }
    
        

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        #[flat]
        NoncesEvent: NoncesComponent::Event,

        MinterAdded: MinterAdded,
        MinterRemoved: MinterRemoved,
        GuardianAdded: GuardianAdded,
        GuardianRemoved: GuardianRemoved,
        ERC20Recovered: ERC20Recovered,
        ERC721Recovered: ERC721Recovered,
    }
    
    /// @notice Constructor function to initialize the contract
    /// @param owner: ContractAddress - The address that will own the contract
    #[constructor]
    fn constructor(
        ref self: ContractState,
        _name_ignore: felt252,
        _symbol_ignore: felt252,
        _decimals_ignore: u8,
        _initial_supply_ignore: u256,
        _initial_recipient_ignore: ContractAddress,
        _initial_minter_ignore: ContractAddress,
        owner: ContractAddress,
        _upgrade_delay_ignore: u64,
    ) {
        self.erc20.initializer("Starknet tBTC", "tBTC");
        self.ownable.initializer(owner);
    }

    /// @notice Internal implementation for role access control
    #[generate_trait]
    impl InternalRolesImpl of InternalRolesTrait {
        /// @notice Check if an address is a minter
        /// @param caller: ContractAddress - The address to check
        /// @return bool - True if the caller is a minter, false otherwise
        fn is_minter(self: @ContractState, caller: ContractAddress) -> bool {
            self.is_minter_map.entry(caller).read()
        }

        /// @notice Check if an address is a guardian
        /// @param caller: ContractAddress - The address to check
        /// @return bool - True if the caller is a guardian, false otherwise
        fn is_guardian(self: @ContractState, caller: ContractAddress) -> bool {
            self.is_guardian_map.entry(caller).read()
        }
    }
    
    #[generate_trait]
    #[abi(per_item)]
    impl ExternalImpl of ExternalTrait {
        /// @notice Adds an address to the minters list
        /// @dev Only the contract owner can add minters
        /// @param minter: ContractAddress - The address to be added as a minter
        #[external(v0)]
        fn add_minter(ref self: ContractState, minter: ContractAddress) {
            self.ownable.assert_only_owner();
            assert(!InternalRolesImpl::is_minter(@self, minter), ALREADY_MINTER);
            self.is_minter_map.entry(minter).write(true);
            self.minters.push(minter);
            self.emit(MinterAdded { minter });
        }

        /// @notice Removes an address from the minters list
        /// @dev Only the contract owner can remove minters
        /// @param minter: ContractAddress - The address to be removed from the minters list
        #[external(v0)]
        fn remove_minter(ref self: ContractState, minter: ContractAddress) {
            self.ownable.assert_only_owner();
            assert(InternalRolesImpl::is_minter(@self, minter), NOT_MINTER);

            self.is_minter_map.entry(minter).write(false);
    
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

        /// @notice Adds an address to the guardians list
        /// @dev Only the contract owner can add guardians
        /// @param guardian: ContractAddress - The address to be added as a guardian
        #[external(v0)]
        fn add_guardian(ref self: ContractState, guardian: ContractAddress) {
            self.ownable.assert_only_owner();
            assert(!self.is_guardian_map.entry(guardian).read(), ALREADY_GUARDIAN);
            self.is_guardian_map.entry(guardian).write(true);
            self.guardians.push(guardian);
            self.emit(GuardianAdded { guardian });
        }

        /// @notice Removes an address from the guardians list
        /// @dev Only the contract owner can remove guardians
        /// @param guardian: ContractAddress - The address to be removed from the guardians list
        #[external(v0)]
        fn remove_guardian(ref self: ContractState, guardian: ContractAddress) {
            self.ownable.assert_only_owner();
            assert(InternalRolesImpl::is_guardian(@self, guardian), NOT_GUARDIAN);
            self.is_guardian_map.entry(guardian).write(false);

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

        /// @notice Recovers ERC20 tokens accidentally sent to this contract
        /// @dev Only the contract owner can recover tokens
        /// @param token: ContractAddress - The address of the ERC20 token to recover
        /// @param recipient: ContractAddress - The address that will receive the recovered tokens
        /// @param amount: u256 - The amount of tokens to recover
        #[external(v0)]
        fn recover_ERC20(
            ref self: ContractState,
            token: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            self.ownable.assert_only_owner();
            let erc20 = ERC20ABIDispatcher { contract_address: token };
            let success = erc20.transfer(recipient, amount);
            assert(success, 'ERC20 transfer failed');
            self.emit(ERC20Recovered { token, recipient, amount });
        }

        /// @notice Recovers ERC721 tokens accidentally sent to this contract
        /// @dev Only the contract owner can recover tokens
        /// @param token: ContractAddress - The address of the ERC721 token contract
        /// @param recipient: ContractAddress - The address that will receive the recovered token
        /// @param token_id: u256 - The ID of the ERC721 token to recover
        /// @param data: Array<felt252> - Additional data to pass to the safe transfer function
        #[external(v0)]
        fn recover_ERC721(
            ref self: ContractState,
            token: ContractAddress,
            recipient: ContractAddress,
            token_id: u256,
            data: Array<felt252>
        ) {
            self.ownable.assert_only_owner();
            
            // Get the ERC721 contract reference
            let erc721 = ERC721ABIDispatcher { contract_address: token };
            
            // Use the L2TBTC contract's own address instead of `get_caller_address()`
            let contract_addr = starknet::get_contract_address();
            
            erc721.safe_transfer_from(contract_addr, recipient, token_id, data.span());
            self.emit(ERC721Recovered { token, recipient, token_id });
        }

        /// @notice Pauses all token mints and burns
        /// @dev Only guardians can pause the contract
        #[external(v0)]
        fn pause(ref self: ContractState) {
            let caller = get_caller_address();
            assert(InternalRolesImpl::is_guardian(@self, caller), 'Caller is not a guardian');
            self.pausable.pause();
        }

        /// @notice Unpauses the contract mints and burns
        /// @dev Only the contract owner can unpause the contract
        #[external(v0)]
        fn unpause(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.pausable.unpause();
        }

        /// @notice Mints new tokens to a recipient
        /// @dev Only minters can mint tokens and contract must not be paused
        /// @param recipient: ContractAddress - The address receiving the minted tokens
        /// @param amount: u256 - The amount of tokens to mint
        #[external(v0)]
        fn permissioned_mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            self.pausable.assert_not_paused();

            let caller = get_caller_address();
            assert(InternalRolesImpl::is_minter(@self, caller), NOT_MINTER);

            self.erc20.mint(recipient, amount);
        }

        /// @notice Burns tokens from the caller's balance
        /// @dev Contract must not be paused
        /// @param value: u256 - The amount of tokens to burn
        #[external(v0)]
        fn permissioned_burn(ref self: ContractState, value: u256) {
            self.pausable.assert_not_paused();
            self.erc20.burn(get_caller_address(), value);
        }

        /// @notice Burns tokens from an account, using the caller's allowance
        /// @dev Caller must have sufficient allowance, contract must not be paused
        /// @param account: ContractAddress - The address whose tokens will be burned
        /// @param value: u256 - The amount of tokens to burn
        #[external(v0)]
        fn burn_from(ref self: ContractState, account: ContractAddress, value: u256) {
            self.pausable.assert_not_paused();
            let caller = get_caller_address();
            // Spend allowance
            self.erc20._spend_allowance(account, caller, value);
            // Burn tokens
            self.erc20.burn(account, value);
        }

        /// @notice Returns an array of all minter addresses
        /// @return Array<ContractAddress> - Array containing all minter addresses
        #[external(v0)]
        fn get_minters(self: @ContractState) -> Array<ContractAddress> {
            let mut minters_array = array![];
            for i in 0..self.minters.len() {
                minters_array.append(self.minters.at(i).read());
            }
            minters_array
        }

        /// @notice Returns an array of all guardian addresses
        /// @return Array<ContractAddress> - Array containing all guardian addresses
        #[external(v0)]
        fn get_guardians(self: @ContractState) -> Array<ContractAddress> {
            let mut guardians_array = array![];
            for i in 0..self.guardians.len() {
                guardians_array.append(self.guardians.at(i).read());
            }
            guardians_array
        }

        /// @notice Checks if an account is a minter
        /// @param account: ContractAddress - The address to check
        /// @return bool - True if the account is a minter, false otherwise
        #[external(v0)]
        fn is_minter(self: @ContractState, account: ContractAddress) -> bool {
            InternalRolesImpl::is_minter(self, account)
        }

        /// @notice Checks if an account is a guardian
        /// @param account: ContractAddress - The address to check
        /// @return bool - True if the account is a guardian, false otherwise
        #[external(v0)]
        fn is_guardian(self: @ContractState, account: ContractAddress) -> bool {
            InternalRolesImpl::is_guardian(self, account)
        }
    }

    //
    // Upgradeable
    //
    /// @notice Implementation of the upgrade functionality
    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        /// @notice Upgrades the contract to a new implementation
        /// @dev Only the contract owner can upgrade the contract
        /// @param new_class_hash: ClassHash - The hash of the new contract implementation
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
    }
}
