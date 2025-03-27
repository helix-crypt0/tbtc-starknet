use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, 
    start_cheat_caller_address, stop_cheat_caller_address,
    spy_events, EventSpyAssertionsTrait};

use starknet::{ContractAddress, contract_address_const};
// Import openzeppelin traits for the components used in L2TBTC
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use openzeppelin::token::erc20::ERC20Component;
use openzeppelin::token::erc721::interface::{IERC721Dispatcher, ERC721ABIDispatcher, ERC721ABIDispatcherTrait};
use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin::security::pausable::PausableComponent::{PausableImpl};

// Define event for testing
#[derive(Drop, starknet::Event)]
struct MinterAdded {
    minter: ContractAddress,
}

// Define event for testing
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

#[derive(Drop, starknet::Event)]
struct Paused {
    account: ContractAddress,
}

#[derive(Drop, starknet::Event)]
struct Unpaused {
    account: ContractAddress,
}

// Define event enum for testing
#[derive(Drop, starknet::Event)]
enum Event {
    MinterAdded: MinterAdded,
    MinterRemoved: MinterRemoved,
    GuardianAdded: GuardianAdded,
    GuardianRemoved: GuardianRemoved,
    Paused: Paused,
    Unpaused: Unpaused,
}

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
    fn isMinter(self: @TContractState, address: ContractAddress) -> bool;
    fn isGuardian(self: @TContractState, address: ContractAddress) -> bool;
    fn recoverERC20(
        ref self: TContractState,
        token: ContractAddress,
        recipient: ContractAddress,
        amount: u256
    );
    fn recoverERC721(
        ref self: TContractState,
        token: ContractAddress,
        recipient: ContractAddress,
        token_id: u256
    );
    fn is_paused(ref self: TContractState) -> bool;
    fn burnFrom(ref self: TContractState, from: ContractAddress, amount: u256);
}

#[starknet::interface]
trait ITestERC20<TContractState> {
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
}

#[starknet::interface]
trait ITestERC721<TContractState> {
    fn mint(ref self: TContractState, recipient: ContractAddress, token_id: u256);
}


#[test]
fn test_deployment() {
    // Define test owner address
    let owner = contract_address_const::<'OWNER'>();
    
    // Declare and deploy L2TBTC contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    // Directly use string literals as felt252
    let constructor_args: Array<felt252> = array![
        owner.into()
    ];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    
    // Create dispatchers to interact with the contract
    let erc20_dispatcher = ERC20ABIDispatcher { contract_address };
    let ownable_dispatcher = IOwnableDispatcher { contract_address };
    
    // Test contract initialization
    let name = erc20_dispatcher.name();
    
    let symbol = erc20_dispatcher.symbol();
    let contract_owner = ownable_dispatcher.owner();
    let total_supply = erc20_dispatcher.total_supply();
    // Verify contract was initialized correctly
    assert(name == "Starknet tBTC", 'Name should be Starknet tBTC');
    assert(symbol == "tBTC", 'Symbol should be tBTC');
    assert(contract_owner == owner, 'Owner not set correctly');
    assert(total_supply == 0, 'Initial supply should be 0');
}

#[test]
fn test_erc20_basic_operations() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let user1 = contract_address_const::<'USER1'>();
    let user2 = contract_address_const::<'USER2'>();
    let minter = contract_address_const::<'MINTER'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let erc20 = ERC20ABIDispatcher { contract_address };
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Test initial balances
    assert(erc20.balance_of(user1) == 0, 'Initial balance should be 0');
    
    // Add minter role
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Mint tokens to user1 (from minter)
    let mint_amount: u256 = 1000;
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(user1, mint_amount);
    stop_cheat_caller_address(contract_address);
    
    // Test balance after mint
    assert(erc20.balance_of(user1) == mint_amount, 'Balance after mint incorrect');
    
    // Test transfer
    start_cheat_caller_address(contract_address, user1);
    let transfer_amount: u256 = 500;
    erc20.transfer(user2, transfer_amount);
    stop_cheat_caller_address(contract_address);
    
    assert(erc20.balance_of(user1) == 500, 'User1 balance after transfer');
    assert(erc20.balance_of(user2) == 500, 'User2 balance after transfer');
}

#[test]
fn test_mint_and_burn() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    let user1 = contract_address_const::<'USER1'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let erc20 = ERC20ABIDispatcher { contract_address };
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Test initial state
    assert(erc20.total_supply() == 0, 'Initial supply should be 0');
    assert(erc20.balance_of(user1) == 0, 'Initial balance should be 0');
    
    // Test minting (only minters can mint)
    let mint_amount: u256 = 1000;
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(user1, mint_amount);
    stop_cheat_caller_address(contract_address);
    
    // Verify mint results
    assert(erc20.total_supply() == mint_amount, 'Total supply after mint');
    assert(erc20.balance_of(user1) == mint_amount, 'User balance after mint');
    
    // Test burning
    let burn_amount: u256 = 400;
    start_cheat_caller_address(contract_address, user1);
    l2tbtc.burn(burn_amount);
    stop_cheat_caller_address(contract_address);
    
    // Verify burn results
    assert(erc20.total_supply() == mint_amount - burn_amount, 'Total supply after burn');
    assert(erc20.balance_of(user1) == mint_amount - burn_amount, 'User balance after burn');
}

// Negative test scenarios
#[test]
#[should_panic(expected: ('Not a minter',))]
fn test_unauthorized_mint() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let user1 = contract_address_const::<'USER1'>();
    let user2 = contract_address_const::<'USER2'>(); // Unauthorized user
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Try to mint tokens as unauthorized user (should fail)
    let mint_amount: u256 = 1000;
    start_cheat_caller_address(contract_address, user2);
    l2tbtc.mint(user1, mint_amount); // This should panic with 'not owner or minter'
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_unauthorized_add_minter() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let user1 = contract_address_const::<'USER1'>();
    let user2 = contract_address_const::<'USER2'>(); // Unauthorized user
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Try to add a minter as unauthorized user (should fail)
    start_cheat_caller_address(contract_address, user1);
    l2tbtc.addMinter(user2); // This should panic with 'Ownable: caller is not the owner'
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_minter_cannot_add_minter() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let user1 = contract_address_const::<'USER1'>();
    let user2 = contract_address_const::<'USER2'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add user1 as minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(user1);
    stop_cheat_caller_address(contract_address);
    
    // Test that a minter cannot add another minter
    start_cheat_caller_address(contract_address, user1);
    l2tbtc.addMinter(user2); // This should panic with 'Caller is not the owner'
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_add_minter() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let user1 = contract_address_const::<'USER1'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let erc20 = ERC20ABIDispatcher { contract_address };
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add user1 as minter (only owner can add minters)
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(user1);
    stop_cheat_caller_address(contract_address);
    
    // Test initial balance
    assert(erc20.balance_of(user1) == 0, 'Initial balance should be 0');
    
    // Have user1 mint tokens to itself
    let mint_amount: u256 = 1000;
    start_cheat_caller_address(contract_address, user1);
    l2tbtc.mint(user1, mint_amount);
    stop_cheat_caller_address(contract_address);
    
    // Verify mint results
    assert(erc20.total_supply() == mint_amount, 'Total supply after mint');
    assert(erc20.balance_of(user1) == mint_amount, 'User balance after mint');
}

#[test]
#[should_panic]
fn test_add_duplicate_minter() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let user1 = contract_address_const::<'USER1'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add user1 as minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(user1);
    
    // Try to add the same user as minter again (should fail)
    l2tbtc.addMinter(user1); // This should panic with 'Already a minter'
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_minter_added_event() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let user1 = contract_address_const::<'USER1'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Capture events using spy_events approach
    let mut spy = spy_events();
    
    // Add user1 as minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(user1);
    stop_cheat_caller_address(contract_address);
    
    // Assert the emitted event using the local event definition
    spy.assert_emitted(
        @array![
            (
                contract_address,
                Event::MinterAdded(
                    MinterAdded { minter: user1 }
                )
            )
        ]
    );
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_unauthorized_remove_minter() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let user1 = contract_address_const::<'USER1'>();
    let user2 = contract_address_const::<'USER2'>(); // Unauthorized user
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add user1 as minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(user1);
    stop_cheat_caller_address(contract_address);
    
    // Try to remove a minter as unauthorized user (should fail)
    start_cheat_caller_address(contract_address, user2);
    l2tbtc.removeMinter(user1); // This should panic with 'Caller is not the owner'
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_minter_cannot_remove_minter() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let user1 = contract_address_const::<'USER1'>();
    let user2 = contract_address_const::<'USER2'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add user1 and user2 as minters
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(user1);
    l2tbtc.addMinter(user2);
    stop_cheat_caller_address(contract_address);
    
    // Test that a minter cannot remove another minter
    start_cheat_caller_address(contract_address, user1);
    l2tbtc.removeMinter(user2); // This should panic with 'Caller is not the owner'
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_guardian_cannot_remove_minter() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian = contract_address_const::<'GUARDIAN'>();
    let minter = contract_address_const::<'MINTER'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add guardian and minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addGuardian(guardian);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Test that a guardian cannot remove a minter
    start_cheat_caller_address(contract_address, guardian);
    l2tbtc.removeMinter(minter); // This should panic with 'Caller is not the owner'
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not a guardian',))]
fn test_unauthorized_pause() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let user1 = contract_address_const::<'USER1'>(); // Unauthorized user
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Try to pause as unauthorized user (should fail)
    start_cheat_caller_address(contract_address, user1);
    l2tbtc.pause(); // This should panic with 'Ownable: caller is not the owner'
    stop_cheat_caller_address(contract_address);
}


#[test]
fn test_owner_can_remove_minter() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Capture events using spy_events
    let mut spy = spy_events();
    
    // Remove minter as owner
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    l2tbtc.removeMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Assert the emitted event
    spy.assert_emitted(
        @array![
            (
                contract_address,
                Event::MinterRemoved(
                    MinterRemoved { minter }
                )
            )
        ]
    );
}

#[test]
fn test_remove_minter_updates_list_correctly() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter1 = contract_address_const::<'MINTER1'>();
    let minter2 = contract_address_const::<'MINTER2'>();
    let minter3 = contract_address_const::<'MINTER3'>();

    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };

    // Add multiple minters
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter1);
    l2tbtc.addMinter(minter2); 
    l2tbtc.addMinter(minter3);

    // Initial minters list should contain all three
    let initial_minters = l2tbtc.getMinters();
    assert(initial_minters.len() == 3, 'Wrong initial minters count');
    assert(*initial_minters.at(0) == minter1, 'Wrong minter at index 0');
    assert(*initial_minters.at(1) == minter2, 'Wrong minter at index 1');
    assert(*initial_minters.at(2) == minter3, 'Wrong minter at index 2');

    // Remove middle minter (minter2)
    l2tbtc.removeMinter(minter2);

    // Check updated list - should have minter1 and minter3, with minter3 moved to minter2's position
    let updated_minters = l2tbtc.getMinters();
    assert(updated_minters.len() == 2, 'Wrong final minters count');
    assert(*updated_minters.at(0) == minter1, 'Wrong 1st minter after remove');
    assert(*updated_minters.at(1) == minter3, 'Wrong 2nd minter after remove');

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_is_minter() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    let non_minter = contract_address_const::<'NON_MINTER'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Check initial state
    assert(!l2tbtc.isMinter(minter), 'Should not be minter initially');
    assert(!l2tbtc.isMinter(non_minter), 'Should not be minter initially');
    
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Verify minter status
    assert(l2tbtc.isMinter(minter), 'Should be minter after adding');
    assert(!l2tbtc.isMinter(non_minter), 'Should still not be minter');
    
    // Remove minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.removeMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Verify minter status after removal
    assert(!l2tbtc.isMinter(minter), 'Not a minter after removal');
}

#[test]
fn test_multiple_minters_addition() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    // Define multiple minter addresses in a structured way
    let minter1 = contract_address_const::<'MINTER1'>();
    let minter2 = contract_address_const::<'MINTER2'>();
    let minter3 = contract_address_const::<'MINTER3'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Verify initial empty state
    let initial_minters = l2tbtc.getMinters();
    assert(initial_minters.len() == 0, 'Should start with no minters');
    
    // Add multiple minters
    start_cheat_caller_address(contract_address, owner);
    
    // Add first minter and verify
    l2tbtc.addMinter(minter1);
    assert(l2tbtc.isMinter(minter1), 'Minter1 should be minter');
    let minters_after_first = l2tbtc.getMinters();
    assert(minters_after_first.len() == 1, 'Should have one minter');
    assert(*minters_after_first.at(0) == minter1, 'First minter wrong');
    
    // Add second minter and verify
    l2tbtc.addMinter(minter2);
    assert(l2tbtc.isMinter(minter2), 'Minter2 should be minter');
    let minters_after_second = l2tbtc.getMinters();
    assert(minters_after_second.len() == 2, 'Should have two minters');
    assert(*minters_after_second.at(0) == minter1, 'First minter changed');
    assert(*minters_after_second.at(1) == minter2, 'Second minter wrong');
    
    // Add third minter and verify
    l2tbtc.addMinter(minter3);
    assert(l2tbtc.isMinter(minter3), 'Minter3 should be minter');
    let final_minters = l2tbtc.getMinters();
    assert(final_minters.len() == 3, 'Should have three minters');
    assert(*final_minters.at(0) == minter1, 'First minter changed');
    assert(*final_minters.at(1) == minter2, 'Second minter changed');
    assert(*final_minters.at(2) == minter3, 'Third minter wrong');
    
    // Verify all minters are still valid
    assert(l2tbtc.isMinter(minter1), 'Minter1 should still be minter');
    assert(l2tbtc.isMinter(minter2), 'Minter2 should still be minter');
    assert(l2tbtc.isMinter(minter3), 'Minter3 should still be minter');
    
    stop_cheat_caller_address(contract_address);
}


#[test]
#[should_panic(expected: ('Not a minter',))]
fn test_remove_non_minter() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let non_minter = contract_address_const::<'NON_MINTER'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Try to remove a non-minter address
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.removeMinter(non_minter); // Should panic with 'Not a minter'
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_remove_first_minter() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter1 = contract_address_const::<'MINTER1'>();
    let minter2 = contract_address_const::<'MINTER2'>();
    let minter3 = contract_address_const::<'MINTER3'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add three minters
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter1);
    l2tbtc.addMinter(minter2);
    l2tbtc.addMinter(minter3);
    
    // Verify initial state
    let initial_minters = l2tbtc.getMinters();
    assert(initial_minters.len() == 3, 'Should have three minters');
    assert(*initial_minters.at(0) == minter1, 'First minter wrong');
    assert(*initial_minters.at(1) == minter2, 'Second minter wrong');
    assert(*initial_minters.at(2) == minter3, 'Third minter wrong');
    
    // Remove first minter
    let mut spy = spy_events();
    l2tbtc.removeMinter(minter1);
    
    // Verify event was emitted
    spy.assert_emitted(
        @array![
            (
                contract_address,
                Event::MinterRemoved(
                    MinterRemoved { minter: minter1 }
                )
            )
        ]
    );
    
    // Verify minter was removed
    assert(!l2tbtc.isMinter(minter1), 'Minter1 should not be minter');
    
    // Verify remaining minters
    let final_minters = l2tbtc.getMinters();
    assert(final_minters.len() == 2, 'Should have two minters');
    assert(*final_minters.at(0) == minter3, 'First minter wrong'); // Last minter moved to first position
    assert(*final_minters.at(1) == minter2, 'Second minter wrong');
    
    // Verify remaining minters are still valid
    assert(l2tbtc.isMinter(minter2), 'Minter2 should still be minter');
    assert(l2tbtc.isMinter(minter3), 'Minter3 should still be minter');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_remove_last_minter() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter1 = contract_address_const::<'MINTER1'>();
    let minter2 = contract_address_const::<'MINTER2'>();
    let minter3 = contract_address_const::<'MINTER3'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add multiple minters
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter1);
    l2tbtc.addMinter(minter2);
    l2tbtc.addMinter(minter3);
    
    // Verify initial state
    let initial_minters = l2tbtc.getMinters();
    assert(initial_minters.len() == 3, 'Should have three minters');
    assert(*initial_minters.at(0) == minter1, 'First minter wrong');
    assert(*initial_minters.at(1) == minter2, 'Second minter wrong');
    assert(*initial_minters.at(2) == minter3, 'Last minter wrong');
    
    // Remove the last minter
    let mut spy = spy_events();
    l2tbtc.removeMinter(minter3);
    
    // Verify event was emitted
    spy.assert_emitted(
        @array![
            (
                contract_address,
                Event::MinterRemoved(
                    MinterRemoved { minter: minter3 }
                )
            )
        ]
    );
    
    // Verify last minter was removed
    assert(!l2tbtc.isMinter(minter3), 'Last minter should be removed');
    
    // Verify remaining minters array
    let final_minters = l2tbtc.getMinters();
    assert(final_minters.len() == 2, 'Should have two minters');
    assert(*final_minters.at(0) == minter1, 'First minter wrong');
    assert(*final_minters.at(1) == minter2, 'Second minter wrong');
    
    // Verify other minters still exist
    assert(l2tbtc.isMinter(minter1), 'First minter should remain');
    assert(l2tbtc.isMinter(minter2), 'Second minter should remain');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_unauthorized_add_guardian() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let unauthorized = contract_address_const::<'UNAUTHORIZED'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Try to add a guardian as unauthorized user (should fail)
    start_cheat_caller_address(contract_address, unauthorized);
    l2tbtc.addGuardian(unauthorized); // This should panic with 'Caller is not the owner'
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_owner_can_add_guardian() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian = contract_address_const::<'GUARDIAN'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add guardian as owner
    let mut spy = spy_events();
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addGuardian(guardian);
    stop_cheat_caller_address(contract_address);
    
    // Verify guardian was added
    assert(l2tbtc.isGuardian(guardian), 'Should be guardian');
    
    // Verify event was emitted
    spy.assert_emitted(
        @array![
            (
                contract_address,
                Event::GuardianAdded(
                    GuardianAdded { guardian }
                )
            )
        ]
    );
}

#[test]
#[should_panic(expected: ('Already a guardian',))]
fn test_add_duplicate_guardian() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian = contract_address_const::<'GUARDIAN'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add guardian first time
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addGuardian(guardian);
    
    // Try to add same guardian again (should fail)
    l2tbtc.addGuardian(guardian);
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_multiple_guardians() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian1 = contract_address_const::<'GUARDIAN1'>();
    let guardian2 = contract_address_const::<'GUARDIAN2'>();
    let guardian3 = contract_address_const::<'GUARDIAN3'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add multiple guardians
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addGuardian(guardian1);
    l2tbtc.addGuardian(guardian2);
    l2tbtc.addGuardian(guardian3);
    stop_cheat_caller_address(contract_address);
    
    // Get guardians list
    let guardians = l2tbtc.getGuardians();
    
    // Verify guardians list
    assert(guardians.len() == 3, 'Should have three guardians');
    assert(*guardians.at(0) == guardian1, 'First guardian wrong');
    assert(*guardians.at(1) == guardian2, 'Second guardian wrong');
    assert(*guardians.at(2) == guardian3, 'Third guardian wrong');
    
    // Verify each guardian status
    assert(l2tbtc.isGuardian(guardian1), 'Guardian1 should be guardian');
    assert(l2tbtc.isGuardian(guardian2), 'Guardian2 should be guardian');
    assert(l2tbtc.isGuardian(guardian3), 'Guardian3 should be guardian');
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_unauthorized_remove_guardian() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian = contract_address_const::<'GUARDIAN'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>(); // Unauthorized user
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add guardian as owner
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addGuardian(guardian);
    stop_cheat_caller_address(contract_address);
    
    // Try to remove guardian as unauthorized user (should fail)
    start_cheat_caller_address(contract_address, third_party);
    l2tbtc.removeGuardian(guardian); // This should panic with 'Caller is not the owner'
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Not a guardian',))]
fn test_remove_non_guardian() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let non_guardian = contract_address_const::<'NON_GUARDIAN'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Try to remove a non-guardian address (should fail)
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.removeGuardian(non_guardian); // Should panic with 'Not a guardian'
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_guardian_cannot_remove_guardian() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian1 = contract_address_const::<'GUARDIAN1'>();
    let guardian2 = contract_address_const::<'GUARDIAN2'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add guardian1 and guardian2
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addGuardian(guardian1);
    l2tbtc.addGuardian(guardian2);
    stop_cheat_caller_address(contract_address);
    
    // Test that a guardian cannot remove another guardian
    start_cheat_caller_address(contract_address, guardian1);
    l2tbtc.removeGuardian(guardian2); // This should panic with 'Caller is not the owner'
    stop_cheat_caller_address(contract_address);
}

fn test_remove_guardian_success() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian = contract_address_const::<'GUARDIAN'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add guardian first
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addGuardian(guardian);
    
    // Verify guardian was added
    assert(l2tbtc.isGuardian(guardian), 'Should be guardian initially');
    assert(l2tbtc.getGuardians().len() == 1, 'Should have one guardian');
    
    // Capture events for removal
    let mut spy = spy_events();
    
    // Remove guardian
    l2tbtc.removeGuardian(guardian);
    stop_cheat_caller_address(contract_address);
    
    // Verify guardian was removed
    assert(!l2tbtc.isGuardian(guardian), 'Should not be guardian after');
    assert(l2tbtc.getGuardians().len() == 0, 'Should have no guardians');
    
    // Verify event was emitted
    spy.assert_emitted(
        @array![
            (
                contract_address,
                Event::GuardianRemoved(
                    GuardianRemoved { guardian }
                )
            )
        ]
    );
}

#[test]
fn test_remove_guardian_updates_list_correctly() {
    // Setup with multiple guardians
    let owner = contract_address_const::<'OWNER'>();
    let guardian1 = contract_address_const::<'GUARDIAN1'>();
    let guardian2 = contract_address_const::<'GUARDIAN2'>();
    let guardian3 = contract_address_const::<'GUARDIAN3'>();
    let guardian4 = contract_address_const::<'GUARDIAN4'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add multiple guardians
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addGuardian(guardian1);
    l2tbtc.addGuardian(guardian2);
    l2tbtc.addGuardian(guardian3);
    l2tbtc.addGuardian(guardian4);
    
    // Verify initial state
    let initial_guardians = l2tbtc.getGuardians();
    assert(initial_guardians.len() == 4, 'Should have four guardians');
    assert(*initial_guardians.at(0) == guardian1, 'Wrong 1st guardian');
    assert(*initial_guardians.at(1) == guardian2, 'Wrong 2nd guardian');
    assert(*initial_guardians.at(2) == guardian3, 'Wrong 3rd guardian');
    assert(*initial_guardians.at(3) == guardian4, 'Wrong 4th guardian');
    
    // Test removing first guardian
    l2tbtc.removeGuardian(guardian1);
    let guardians_after_first = l2tbtc.getGuardians();
    assert(guardians_after_first.len() == 3, 'Should have three guardians');
    assert(*guardians_after_first.at(0) == guardian4, 'Wrong 1st after remove');
    assert(*guardians_after_first.at(1) == guardian2, 'Wrong 2nd after remove');
    assert(*guardians_after_first.at(2) == guardian3, 'Wrong 3rd after remove');
    
    // Test removing last guardian
    l2tbtc.removeGuardian(guardian3);
    let guardians_after_last = l2tbtc.getGuardians();
    assert(guardians_after_last.len() == 2, 'Should have two guardians');
    assert(*guardians_after_last.at(0) == guardian4, 'Wrong 1st after last');
    assert(*guardians_after_last.at(1) == guardian2, 'Wrong 2nd after last');
    
    // Test removing from middle
    l2tbtc.removeGuardian(guardian2);
    let final_guardians = l2tbtc.getGuardians();
    assert(final_guardians.len() == 1, 'Should have one guardian');
    assert(*final_guardians.at(0) == guardian4, 'Wrong final guardian');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Not a guardian',))]
fn test_remove_non_existent_guardian() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let non_existent = contract_address_const::<'NON_EXISTENT'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Try to remove a non-existent guardian
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.removeGuardian(non_existent); // Should panic with 'Not a guardian'
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_single_guardian_removal() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian = contract_address_const::<'GUARDIAN'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add guardian
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addGuardian(guardian);
    
    // Verify initial state
    assert(l2tbtc.isGuardian(guardian), 'Should be guardian initially');
    let initial_guardians = l2tbtc.getGuardians();
    assert(initial_guardians.len() == 1, 'Should have one guardian');
    assert(*initial_guardians.at(0) == guardian, 'Wrong guardian in list');
    
    // Setup event spy
    let mut spy = spy_events();
    
    // Remove guardian
    l2tbtc.removeGuardian(guardian);
    stop_cheat_caller_address(contract_address);
    
    // Verify guardian was removed
    assert(!l2tbtc.isGuardian(guardian), 'Should not be guardian after');
    let final_guardians = l2tbtc.getGuardians();
    assert(final_guardians.len() == 0, 'Should have no guardians');
    
    // Verify event was emitted
    spy.assert_emitted(
        @array![
            (
                contract_address,
                Event::GuardianRemoved(
                    GuardianRemoved { guardian }
                )
            )
        ]
    );
}

#[test]
fn test_guardian_removal_and_readd() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian = contract_address_const::<'GUARDIAN'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    start_cheat_caller_address(contract_address, owner);
    
    // Add guardian
    l2tbtc.addGuardian(guardian);
    assert(l2tbtc.isGuardian(guardian), 'Should be guardian after add');
    
    // Remove guardian
    l2tbtc.removeGuardian(guardian);
    assert(!l2tbtc.isGuardian(guardian), 'Not a guardian after remove');
    
    // Re-add guardian
    l2tbtc.addGuardian(guardian);
    assert(l2tbtc.isGuardian(guardian), 'Should be guardian after readd');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_guardian_state_after_removal() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian = contract_address_const::<'GUARDIAN'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    start_cheat_caller_address(contract_address, owner);
    
    // Add and remove guardian
    l2tbtc.addGuardian(guardian);
    l2tbtc.removeGuardian(guardian);
    
    // Verify final state
    assert(!l2tbtc.isGuardian(guardian), 'Should not be guardian');
    let guardians = l2tbtc.getGuardians();
    assert(guardians.len() == 0, 'Should have empty guardian list');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_guardian_removal_events_sequence() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian = contract_address_const::<'GUARDIAN'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Setup event spy
    let mut spy = spy_events();
    
    start_cheat_caller_address(contract_address, owner);
    
    // Add guardian
    l2tbtc.addGuardian(guardian);
    
    // Remove guardian
    l2tbtc.removeGuardian(guardian);
    
    stop_cheat_caller_address(contract_address);
    
    // Verify both events were emitted in correct sequence
    spy.assert_emitted(
        @array![
            (
                contract_address,
                Event::GuardianAdded(
                    GuardianAdded { guardian }
                )
            ),
            (
                contract_address,
                Event::GuardianRemoved(
                    GuardianRemoved { guardian }
                )
            )
        ]
    );
}

#[test]
fn test_multiple_guardian_removal() {
    // Setup with multiple guardians
    let owner = contract_address_const::<'OWNER'>();
    let guardian1 = contract_address_const::<'GUARDIAN1'>();
    let guardian2 = contract_address_const::<'GUARDIAN2'>();
    let guardian3 = contract_address_const::<'GUARDIAN3'>();
    let guardian4 = contract_address_const::<'GUARDIAN4'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    start_cheat_caller_address(contract_address, owner);
    
    // Add multiple guardians
    l2tbtc.addGuardian(guardian1);
    l2tbtc.addGuardian(guardian2);
    l2tbtc.addGuardian(guardian3);
    l2tbtc.addGuardian(guardian4);
    
    // Verify initial state
    let initial_guardians = l2tbtc.getGuardians();
    assert(initial_guardians.len() == 4, 'Should have four guardians');
    assert(*initial_guardians.at(0) == guardian1, 'Wrong 1st guardian');
    assert(*initial_guardians.at(1) == guardian2, 'Wrong 2nd guardian');
    assert(*initial_guardians.at(2) == guardian3, 'Wrong 3rd guardian');
    assert(*initial_guardians.at(3) == guardian4, 'Wrong 4th guardian');
    
    // Remove guardians in different order
    l2tbtc.removeGuardian(guardian2); // Remove from middle
    l2tbtc.removeGuardian(guardian4); // Remove from end
    l2tbtc.removeGuardian(guardian1); // Remove from beginning
    
    // Verify final state
    let final_guardians = l2tbtc.getGuardians();
    assert(final_guardians.len() == 1, 'Should have one guardian');
    assert(*final_guardians.at(0) == guardian3, 'Wrong remaining guardian');
    
    // Verify removed guardians status
    assert(!l2tbtc.isGuardian(guardian1), 'Guardian1 should be removed');
    assert(!l2tbtc.isGuardian(guardian2), 'Guardian2 should be removed');
    assert(l2tbtc.isGuardian(guardian3), 'Guardian3 should remain');
    assert(!l2tbtc.isGuardian(guardian4), 'Guardian4 should be removed');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_remove_first_guardian() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian1 = contract_address_const::<'GUARDIAN1'>();
    let guardian2 = contract_address_const::<'GUARDIAN2'>();
    let guardian3 = contract_address_const::<'GUARDIAN3'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    start_cheat_caller_address(contract_address, owner);
    
    // Add guardians
    l2tbtc.addGuardian(guardian1);
    l2tbtc.addGuardian(guardian2);
    l2tbtc.addGuardian(guardian3);
    
    // Remove first guardian
    let mut spy = spy_events();
    l2tbtc.removeGuardian(guardian1);
    
    // Verify event emission
    spy.assert_emitted(
        @array![
            (
                contract_address,
                Event::GuardianRemoved(
                    GuardianRemoved { guardian: guardian1 }
                )
            )
        ]
    );
    
    // Verify list update
    let guardians = l2tbtc.getGuardians();
    assert(guardians.len() == 2, 'Should have two guardians');
    assert(*guardians.at(0) == guardian3, 'Wrong first guardian'); // Last guardian moved to first position
    assert(*guardians.at(1) == guardian2, 'Wrong second guardian');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_remove_middle_guardian() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian1 = contract_address_const::<'GUARDIAN1'>();
    let guardian2 = contract_address_const::<'GUARDIAN2'>();
    let guardian3 = contract_address_const::<'GUARDIAN3'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    start_cheat_caller_address(contract_address, owner);
    
    // Add guardians
    l2tbtc.addGuardian(guardian1);
    l2tbtc.addGuardian(guardian2);
    l2tbtc.addGuardian(guardian3);
    
    // Remove middle guardian
    let mut spy = spy_events();
    l2tbtc.removeGuardian(guardian2);
    
    // Verify event emission
    spy.assert_emitted(
        @array![
            (
                contract_address,
                Event::GuardianRemoved(
                    GuardianRemoved { guardian: guardian2 }
                )
            )
        ]
    );
    
    // Verify list update
    let guardians = l2tbtc.getGuardians();
    assert(guardians.len() == 2, 'Should have two guardians');
    assert(*guardians.at(0) == guardian1, 'Wrong first guardian');
    assert(*guardians.at(1) == guardian3, 'Wrong second guardian');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_remove_last_guardian() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian1 = contract_address_const::<'GUARDIAN1'>();
    let guardian2 = contract_address_const::<'GUARDIAN2'>();
    let guardian3 = contract_address_const::<'GUARDIAN3'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    start_cheat_caller_address(contract_address, owner);
    
    // Add guardians
    l2tbtc.addGuardian(guardian1);
    l2tbtc.addGuardian(guardian2);
    l2tbtc.addGuardian(guardian3);
    
    // Remove last guardian
    let mut spy = spy_events();
    l2tbtc.removeGuardian(guardian3);
    
    // Verify event emission
    spy.assert_emitted(
        @array![
            (
                contract_address,
                Event::GuardianRemoved(
                    GuardianRemoved { guardian: guardian3 }
                )
            )
        ]
    );
    
    // Verify list update
    let guardians = l2tbtc.getGuardians();
    assert(guardians.len() == 2, 'Should have two guardians');
    assert(*guardians.at(0) == guardian1, 'Wrong first guardian');
    assert(*guardians.at(1) == guardian2, 'Wrong second guardian');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_unauthorized_recover_erc20() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>(); // Unauthorized user
    let recipient = contract_address_const::<'RECIPIENT'>();
    
    // Deploy main contract (L2TBTC)
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Deploy another L2TBTC as the token to recover
    let token_contract = declare("L2TBTC").unwrap().contract_class();
    let token_constructor_args = array![owner.into()];
    let (token_address, _) = token_contract.deploy(@token_constructor_args).unwrap();
    let token_l2tbtc = IL2TBTCDispatcher { contract_address: token_address };
    let token_erc20 = ERC20ABIDispatcher { contract_address: token_address };
    
    // First, add owner as a minter on the token contract
    start_cheat_caller_address(token_address, owner);
    token_l2tbtc.addMinter(owner);
    
    // Now mint tokens to the L2TBTC contract (the first one)
    let amount: u256 = 725_000_000_000_000_000_000; // 725 tokens with 18 decimals
    token_l2tbtc.mint(contract_address, amount);
    stop_cheat_caller_address(token_address);
    
    // Verify initial balance
    assert(token_erc20.balance_of(contract_address) == amount, 'Wrong initial balance');
    
    // Try to recover tokens as unauthorized user (should fail)
    start_cheat_caller_address(contract_address, third_party);
    l2tbtc.recoverERC20(token_address, recipient, amount); // This should panic
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_owner_recover_erc20() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let recipient = contract_address_const::<'RECIPIENT'>();
    
    // Deploy main contract (L2TBTC)
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Deploy another L2TBTC as the token to recover
    let token_contract = declare("L2TBTC").unwrap().contract_class();
    let token_constructor_args = array![owner.into()];
    let (token_address, _) = token_contract.deploy(@token_constructor_args).unwrap();
    let token_l2tbtc = IL2TBTCDispatcher { contract_address: token_address };
    let token_erc20 = ERC20ABIDispatcher { contract_address: token_address };
    
    // First, add owner as a minter on the token contract
    start_cheat_caller_address(token_address, owner);
    token_l2tbtc.addMinter(owner);
    
    // Now mint tokens to the L2TBTC contract (the first one)
    let amount: u256 = 725_000_000_000_000_000_000; // 725 tokens with 18 decimals
    token_l2tbtc.mint(contract_address, amount);
    stop_cheat_caller_address(token_address);
    
    // Verify initial balance
    assert(token_erc20.balance_of(contract_address) == amount, 'Wrong initial balance');
    assert(token_erc20.balance_of(recipient) == 0, 'Recipient should have 0');
    
    // Recover tokens as owner
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.recoverERC20(token_address, recipient, amount);
    stop_cheat_caller_address(contract_address);
    
    // Verify balances after recovery
    assert(token_erc20.balance_of(contract_address) == 0, 'Contract should have 0');
    assert(token_erc20.balance_of(recipient) == amount, 'Tokens not transferred');
}

#[test]
fn test_recover_partial_erc20_amount() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let recipient = contract_address_const::<'RECIPIENT'>();
    
    // Deploy main contract (L2TBTC)
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Deploy another L2TBTC as the token to recover
    let token_contract = declare("L2TBTC").unwrap().contract_class();
    let token_constructor_args = array![owner.into()];
    let (token_address, _) = token_contract.deploy(@token_constructor_args).unwrap();
    let token_l2tbtc = IL2TBTCDispatcher { contract_address: token_address };
    let token_erc20 = ERC20ABIDispatcher { contract_address: token_address };
    
    // First, add owner as a minter on the token contract
    start_cheat_caller_address(token_address, owner);
    token_l2tbtc.addMinter(owner);
    
    // Now mint tokens to the L2TBTC contract (the first one)
    let total_amount: u256 = 725_000_000_000_000_000_000; // 725 tokens with 18 decimals
    token_l2tbtc.mint(contract_address, total_amount);
    stop_cheat_caller_address(token_address);
    
    // Verify initial balance
    assert(token_erc20.balance_of(contract_address) == total_amount, 'Wrong initial balance');
    
    // Recover only half of the tokens
    let partial_amount: u256 = total_amount / 2;
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.recoverERC20(token_address, recipient, partial_amount);
    stop_cheat_caller_address(contract_address);
    
    // Verify balances after recovery
    assert(token_erc20.balance_of(contract_address) == partial_amount, 'Wrong contract balance');
    assert(token_erc20.balance_of(recipient) == partial_amount, 'Wrong recipient balance');
}

// #[test]
// fn test_owner_recover_erc721() {
//     // Setup
//     let owner = contract_address_const::<'OWNER'>();
//     let recipient = contract_address_const::<'RECIPIENT'>();
    
//     // Deploy main contract (L2TBTC)
//     let contract = declare("L2TBTC").unwrap().contract_class();
//     let constructor_args = array![owner.into()];
//     let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
//     let l2tbtc = IL2TBTCDispatcher { contract_address };
    
//     // Deploy a TestERC721 as the NFT to recover
//     // The constructor for ERC721 typically needs name, symbol, and owner
//     let token_contract = declare("TestERC721").unwrap().contract_class();
//     // Specify the array type as Array<felt252> so the compiler knows how to infer it:
    
//     let (token_address, _) = token_contract.deploy(@token_constructor_args).unwrap();
    
//     // Create dispatchers for the token contract
//     let test_nft = ITestERC721Dispatcher { contract_address: token_address };
//     let nft_erc721 = ERC721ABIDispatcher { contract_address: token_address };
    
//     // Mint an NFT to the L2TBTC contract
//     let token_id: u256 = 1;
//     start_cheat_caller_address(token_address, owner);
//     test_nft.mint(contract_address, token_id);
//     stop_cheat_caller_address(token_address);
    
//     // Verify initial ownership
//     assert(nft_erc721.owner_of(token_id) == contract_address, 'Wrong initial owner');
    
//     // Recover NFT as owner
//     start_cheat_caller_address(contract_address, owner);
//     l2tbtc.recoverERC721(token_address, recipient, token_id);
//     stop_cheat_caller_address(contract_address);
    
//     // Verify ownership after recovery
//     assert(nft_erc721.owner_of(token_id) == recipient, 'NFT not transferred');
// }

#[test]
fn test_guardian_can_pause() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian = contract_address_const::<'GUARDIAN'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add guardian
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addGuardian(guardian);
    stop_cheat_caller_address(contract_address);
    
    // Guardian pauses the contract
    start_cheat_caller_address(contract_address, guardian);
    l2tbtc.pause();
    stop_cheat_caller_address(contract_address);
    
    // Verify contract is paused
    assert(l2tbtc.is_paused(), 'Contract should be paused');
}

#[test]
#[should_panic(expected: ('Caller is not a guardian',))]
fn test_non_guardian_cannot_pause() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let non_guardian = contract_address_const::<'NON_GUARDIAN'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Non-guardian attempts to pause (should fail)
    start_cheat_caller_address(contract_address, non_guardian);
    l2tbtc.pause();
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_pause_event_emission() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian = contract_address_const::<'GUARDIAN'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add guardian
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addGuardian(guardian);
    stop_cheat_caller_address(contract_address);
    
    // Setup event spy
    let mut spy = spy_events();
    
    // Guardian pauses the contract
    start_cheat_caller_address(contract_address, guardian);
    l2tbtc.pause();
    stop_cheat_caller_address(contract_address);
    
    // Verify Paused event was emitted with correct guardian address
    spy.assert_emitted(
        @array![
            (
                contract_address,
                Event::Paused(
                    Paused { account: guardian }
                )
            )
        ]
    );
}

#[test]
#[should_panic(expected: ('Pausable: paused',))]
fn test_cannot_mint_when_paused() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian = contract_address_const::<'GUARDIAN'>();
    let minter = contract_address_const::<'MINTER'>();
    let recipient = contract_address_const::<'RECIPIENT'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add guardian and minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addGuardian(guardian);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Guardian pauses the contract
    start_cheat_caller_address(contract_address, guardian);
    l2tbtc.pause();
    stop_cheat_caller_address(contract_address);
    
    // Attempt to mint while paused (should fail)
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(recipient, 1000);
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Pausable: paused',))]
fn test_cannot_burn_when_paused() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian = contract_address_const::<'GUARDIAN'>();
    let minter = contract_address_const::<'MINTER'>();
    let holder = contract_address_const::<'HOLDER'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add guardian and minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addGuardian(guardian);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Mint tokens to holder
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(holder, 1000);
    stop_cheat_caller_address(contract_address);
    
    // Guardian pauses the contract
    start_cheat_caller_address(contract_address, guardian);
    l2tbtc.pause();
    stop_cheat_caller_address(contract_address);
    
    // Attempt to burn while paused (should fail)
    start_cheat_caller_address(contract_address, holder);
    l2tbtc.burn(500);
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Pausable: paused',))]
fn test_cannot_transfer_when_paused() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian = contract_address_const::<'GUARDIAN'>();
    let minter = contract_address_const::<'MINTER'>();
    let sender = contract_address_const::<'SENDER'>();
    let recipient = contract_address_const::<'RECIPIENT'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };
    
    // Add guardian and minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addGuardian(guardian);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Mint tokens to sender
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(sender, 1000);
    stop_cheat_caller_address(contract_address);
    
    // Guardian pauses the contract
    start_cheat_caller_address(contract_address, guardian);
    l2tbtc.pause();
    stop_cheat_caller_address(contract_address);
    
    // Attempt transfer while paused (should fail)
    start_cheat_caller_address(contract_address, sender);
    erc20.transfer(recipient, 500);
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_unauthorized_unpause() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian = contract_address_const::<'GUARDIAN'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add guardian and pause the contract
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addGuardian(guardian);
    stop_cheat_caller_address(contract_address);
    
    start_cheat_caller_address(contract_address, guardian);
    l2tbtc.pause();
    stop_cheat_caller_address(contract_address);
    
    // Attempt to unpause as unauthorized user (should fail)
    start_cheat_caller_address(contract_address, third_party);
    l2tbtc.unpause(); // This should panic
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_guardian_cannot_unpause() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian = contract_address_const::<'GUARDIAN'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add guardian and pause the contract
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addGuardian(guardian);
    stop_cheat_caller_address(contract_address);
    
    start_cheat_caller_address(contract_address, guardian);
    l2tbtc.pause();
    stop_cheat_caller_address(contract_address);
    
    // Attempt to unpause as guardian (should fail)
    start_cheat_caller_address(contract_address, guardian);
    l2tbtc.unpause(); // This should panic
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_owner_can_unpause() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian = contract_address_const::<'GUARDIAN'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add guardian and pause the contract
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addGuardian(guardian);
    stop_cheat_caller_address(contract_address);
    
    start_cheat_caller_address(contract_address, guardian);
    l2tbtc.pause();
    stop_cheat_caller_address(contract_address);
    
    assert(l2tbtc.is_paused(), 'Contract should be paused');
    
    // Setup event spy
    let mut spy = spy_events();
    
    // Owner unpauses the contract
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.unpause();
    stop_cheat_caller_address(contract_address);
    
    // Verify contract is unpaused
    assert(!l2tbtc.is_paused(), 'Contract should be unpaused');
    
    // Verify Unpaused event was emitted
    spy.assert_emitted(
        @array![
            (
                contract_address,
                Event::Unpaused(
                    Unpaused { account: owner }
                )
            )
        ]
    );
}

#[test]
fn test_functionality_after_unpause() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let guardian = contract_address_const::<'GUARDIAN'>();
    let minter = contract_address_const::<'MINTER'>();
    let holder = contract_address_const::<'HOLDER'>();
    let recipient = contract_address_const::<'RECIPIENT'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };
    
    // Add guardian and minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addGuardian(guardian);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Pause the contract
    start_cheat_caller_address(contract_address, guardian);
    l2tbtc.pause();
    stop_cheat_caller_address(contract_address);
    
    // Owner unpauses the contract
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.unpause();
    stop_cheat_caller_address(contract_address);
    
    // Test minting after unpause
    let mint_amount: u256 = 1000;
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(holder, mint_amount);
    stop_cheat_caller_address(contract_address);
    
    assert(erc20.balance_of(holder) == mint_amount, 'Mint should succeed');
    
    // Test burning after unpause
    let burn_amount: u256 = 400;
    start_cheat_caller_address(contract_address, holder);
    l2tbtc.burn(burn_amount);
    stop_cheat_caller_address(contract_address);
    
    assert(erc20.balance_of(holder) == mint_amount - burn_amount, 'Burn should succeed');
    
    // Test transfer after unpause
    let transfer_amount: u256 = 300;
    start_cheat_caller_address(contract_address, holder);
    erc20.transfer(recipient, transfer_amount);
    stop_cheat_caller_address(contract_address);
    
    assert(erc20.balance_of(recipient) == transfer_amount, 'Transfer should succeed');
}

#[test]
fn test_multiple_sequential_mints() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    let recipient1 = contract_address_const::<'RECIPIENT1'>();
    let recipient2 = contract_address_const::<'RECIPIENT2'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };
    
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    // First mint to recipient1
    let amount1: u256 = 1000;
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(recipient1, amount1);
    
    // Second mint to recipient1 (same recipient)
    let amount2: u256 = 500;
    l2tbtc.mint(recipient1, amount2);
    
    // Third mint to recipient2 (different recipient)
    let amount3: u256 = 750;
    l2tbtc.mint(recipient2, amount3);
    stop_cheat_caller_address(contract_address);
    
    // Verify balances
    assert(erc20.balance_of(recipient1) == amount1 + amount2, 'Wrong recipient1 balance');
    assert(erc20.balance_of(recipient2) == amount3, 'Wrong recipient2 balance');
    
    // Verify total supply
    assert(erc20.total_supply() == amount1 + amount2 + amount3, 'Wrong total supply');
}

#[test]
fn test_mint_zero_tokens() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    let recipient = contract_address_const::<'RECIPIENT'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };
    
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Mint zero tokens
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(recipient, 0);
    stop_cheat_caller_address(contract_address);
    
    // Verify balance and total supply remain zero
    assert(erc20.balance_of(recipient) == 0, 'Balance should be zero');
    assert(erc20.total_supply() == 0, 'Supply should be zero');
}

#[test]
fn test_mint_to_self() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };
    
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Minter mints tokens to itself
    let amount: u256 = 1000;
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(minter, amount);
    stop_cheat_caller_address(contract_address);
    
    // Verify balance and total supply
    assert(erc20.balance_of(minter) == amount, 'Wrong minter balance');
    assert(erc20.total_supply() == amount, 'Wrong total supply');
}

#[test]
fn test_mint_large_amounts() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    let recipient = contract_address_const::<'RECIPIENT'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };
    
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Mint a very large amount (close to u256 max but not exceeding it)
    let large_amount: u256 = 
        340282366920938463463374607431768211455_u256; // 2^128 - 1, half of u256 max
    
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(recipient, large_amount);
    stop_cheat_caller_address(contract_address);
    
    // Verify balance and total supply
    assert(erc20.balance_of(recipient) == large_amount, 'Wrong recipient balance');
    assert(erc20.total_supply() == large_amount, 'Wrong total supply');
    
    // Mint another large amount to test accumulation
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(recipient, large_amount);
    stop_cheat_caller_address(contract_address);
    
    // Verify updated balance and total supply
    assert(erc20.balance_of(recipient) == large_amount * 2, 'Wrong final balance');
    assert(erc20.total_supply() == large_amount * 2, 'Wrong final supply');
}

#[test]
fn test_total_supply_after_multiple_mints() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };
    
    // Add minter (equivalent to addMinter in the original test)
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Mint 1 token to third party (equivalent to mint(thirdParty.address, to1e18(1)))
    let one_token: u256 = 1000000000000000000; // 1 token with 18 decimals (1e18)
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(third_party, one_token);
    
    // Mint 3 tokens to token holder (equivalent to mint(tokenHolder.address, to1e18(3)))
    let three_tokens: u256 = 3000000000000000000; // 3 tokens with 18 decimals (3e18)
    l2tbtc.mint(token_holder, three_tokens);
    stop_cheat_caller_address(contract_address);
    
    // Check total supply (should be 4 tokens = 4e18)
    let expected_total: u256 = 4000000000000000000; // 4 tokens with 18 decimals
    assert(erc20.total_supply() == expected_total, 'Wrong total supply');
}

#[test]
fn test_balance_of() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };
    
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Mint 7 tokens to token holder (equivalent to 7e18)
    let balance: u256 = 7000000000000000000; // 7 tokens with 18 decimals
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(token_holder, balance);
    stop_cheat_caller_address(contract_address);
    
    // Verify balance
    assert(erc20.balance_of(token_holder) == balance, 'Wrong token balance');
}

#[test]
fn test_transfer() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };
    
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Initial setup - mint 70 tokens to token holder (70e18)
    let initial_balance: u256 = 70000000000000000000; // 70 tokens with 18 decimals
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(token_holder, initial_balance);
    stop_cheat_caller_address(contract_address);
    
    // Transfer 5 tokens (5e18) from token holder to third party
    let transfer_amount: u256 = 5000000000000000000; // 5 tokens with 18 decimals
    start_cheat_caller_address(contract_address, token_holder);
    erc20.transfer(third_party, transfer_amount);
    stop_cheat_caller_address(contract_address);
    
    // Verify balances after transfer
    assert(
        erc20.balance_of(token_holder) == initial_balance - transfer_amount,
        'Wrong sender balance'
    );
    assert(
        erc20.balance_of(third_party) == transfer_amount,
        'Wrong recipient balance'
    );
}

#[test]
fn test_transfer_event_emission() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };
    
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Initial setup - mint 70 tokens to token holder
    let initial_balance: u256 = 70000000000000000000; // 70e18
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(token_holder, initial_balance);
    stop_cheat_caller_address(contract_address);
    
    // Setup event spy
    let mut spy = spy_events();
    
    // Transfer 5 tokens from token holder to third party
    let transfer_amount: u256 = 5000000000000000000; // 5e18
    start_cheat_caller_address(contract_address, token_holder);
    erc20.transfer(third_party, transfer_amount);
    stop_cheat_caller_address(contract_address);
    
    // Verify Transfer event was emitted with correct parameters
    // Note: The exact event structure will depend on your ERC20 implementation
    // This assumes the standard ERC20 Transfer event structure
    spy.assert_emitted(
        @array![
            (
                contract_address,
                ERC20Component::Event::Transfer(
                    ERC20Component::Transfer {
                        from: token_holder,
                        to: third_party,
                        value: transfer_amount
                    }
                )
            )
        ]
    );
}

#[test]
fn test_transfer_from() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };
    
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Initial setup - mint 70 tokens to token holder (70e18)
    let initial_balance: u256 = 70000000000000000000; // 70 tokens with 18 decimals
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(token_holder, initial_balance);
    stop_cheat_caller_address(contract_address);
    
    // Approve third party to spend tokens
    let transfer_amount: u256 = 9000000000000000000; // 9 tokens with 18 decimals (9e18)
    start_cheat_caller_address(contract_address, token_holder);
    erc20.approve(third_party, transfer_amount);
    stop_cheat_caller_address(contract_address);
    
    // Setup event spy for transfer
    let mut spy = spy_events();
    
    // Execute transferFrom
    start_cheat_caller_address(contract_address, third_party);
    erc20.transfer_from(token_holder, third_party, transfer_amount);
    stop_cheat_caller_address(contract_address);
    
    // Verify balances after transfer
    assert(
        erc20.balance_of(token_holder) == initial_balance - transfer_amount,
        'Wrong holder balance'
    );
    assert(
        erc20.balance_of(third_party) == transfer_amount,
        'Wrong recipient balance'
    );
    
    // Verify Transfer event was emitted with correct parameters
    spy.assert_emitted(
        @array![
            (
                contract_address,
                ERC20Component::Event::Transfer(
                    ERC20Component::Transfer {
                        from: token_holder,
                        to: third_party,
                        value: transfer_amount
                    }
                )
            )
        ]
    );
}

#[test]
fn test_approve() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let erc20 = ERC20ABIDispatcher { contract_address };
    
    // Set allowance amount (equivalent to 888e18)
    let allowance: u256 = 888000000000000000000; // 888 tokens with 18 decimals
    
    // Setup event spy
    let mut spy = spy_events();
    
    // Execute approve
    start_cheat_caller_address(contract_address, token_holder);
    erc20.approve(third_party, allowance);
    stop_cheat_caller_address(contract_address);
    
    // Verify allowance amount
    assert(
        erc20.allowance(token_holder, third_party) == allowance,
        'Wrong allowance amount'
    );
    
    // Verify Approval event was emitted with correct parameters
    spy.assert_emitted(
        @array![
            (
                contract_address,
                ERC20Component::Event::Approval(
                    ERC20Component::Approval {
                        owner: token_holder,
                        spender: third_party,
                        value: allowance
                    }
                )
            )
        ]
    );
}

#[test]
fn test_burn_event_emission() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    let zero_address = contract_address_const::<0>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add minter and mint tokens
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    let initial_amount: u256 = 1000000000000000000; // 1 token
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(token_holder, initial_amount);
    stop_cheat_caller_address(contract_address);
    
    // Setup event spy
    let mut spy = spy_events();
    
    // Burn tokens
    let burn_amount: u256 = 500000000000000000; // 0.5 token
    start_cheat_caller_address(contract_address, token_holder);
    l2tbtc.burn(burn_amount);
    stop_cheat_caller_address(contract_address);
    
    // Verify Transfer event was emitted (burn is a transfer to zero address)
    spy.assert_emitted(
        @array![
            (
                contract_address,
                ERC20Component::Event::Transfer(
                    ERC20Component::Transfer {
                        from: token_holder,
                        to: zero_address,
                        value: burn_amount
                    }
                )
            )
        ]
    );
}

#[test]
#[should_panic]
fn test_burn_insufficient_balance() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add minter and mint tokens
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    let initial_amount: u256 = 1000000000000000000; // 1 token
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(token_holder, initial_amount);
    stop_cheat_caller_address(contract_address);
    
    // Attempt to burn more than balance
    let burn_amount: u256 = 2000000000000000000; // 2 tokens
    start_cheat_caller_address(contract_address, token_holder);
    l2tbtc.burn(burn_amount); // Should panic with underflow
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_burn_zero_tokens() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };
    
    // Add minter and mint tokens
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    let initial_amount: u256 = 1000000000000000000; // 1 token
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(token_holder, initial_amount);
    stop_cheat_caller_address(contract_address);
    
    // Burn zero tokens
    start_cheat_caller_address(contract_address, token_holder);
    l2tbtc.burn(0);
    stop_cheat_caller_address(contract_address);
    
    // Verify balance hasn't changed
    assert(erc20.balance_of(token_holder) == initial_amount, 'Balance should not change');
    
}

#[test]
#[should_panic]
fn test_unauthorized_burn_attempt() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    let attacker = contract_address_const::<'ATTACKER'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add minter and mint tokens to token_holder
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    let initial_amount: u256 = 1000000000000000000; // 1 token
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(token_holder, initial_amount);
    stop_cheat_caller_address(contract_address);
    
    // Attempt to burn token_holder's tokens from attacker account
    start_cheat_caller_address(contract_address, attacker);
    l2tbtc.burn(initial_amount); // Should panic due to insufficient balance
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_burn_entire_balance() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };
    
    // Add minter and mint tokens
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    let initial_amount: u256 = 1000000000000000000; // 1 token
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(token_holder, initial_amount);
    stop_cheat_caller_address(contract_address);
    
    // Burn entire balance
    start_cheat_caller_address(contract_address, token_holder);
    l2tbtc.burn(initial_amount);
    stop_cheat_caller_address(contract_address);
    
    // Verify balance is zero
    assert(erc20.balance_of(token_holder) == 0, 'Balance should be zero');
    
    // Verify total supply is zero
    assert(erc20.total_supply() == 0, 'Supply should be zero');
}

#[test]
fn test_burn_from() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>();
    let zero_address = contract_address_const::<0>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };
    
    // Add minter and mint initial tokens (18 tokens)
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    let initial_balance: u256 = 18000000000000000000; // 18e18
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(token_holder, initial_balance);
    stop_cheat_caller_address(contract_address);
    
    // Approve third party to burn tokens (9 tokens)
    let burn_amount: u256 = 9000000000000000000; // 9e18
    start_cheat_caller_address(contract_address, token_holder);
    erc20.approve(third_party, burn_amount);
    stop_cheat_caller_address(contract_address);
    
    // Setup event spy
    let mut spy = spy_events();
    
    // Execute burnFrom
    start_cheat_caller_address(contract_address, third_party);
    l2tbtc.burnFrom(token_holder, burn_amount);
    stop_cheat_caller_address(contract_address);
    
    // Verify balance was decremented correctly
    let expected_balance = initial_balance - burn_amount;
    assert(erc20.balance_of(token_holder) == expected_balance, 'Wrong final balance');
    
    // Verify allowance was decremented to zero
    assert(erc20.allowance(token_holder, third_party) == 0, 'Allowance should be zero');
    
    // Verify Transfer event was emitted correctly
    spy.assert_emitted(
        @array![
            (
                contract_address,
                ERC20Component::Event::Transfer(
                    ERC20Component::Transfer {
                        from: token_holder,
                        to: zero_address,
                        value: burn_amount
                    }
                )
            )
        ]
    );
}

#[test]
#[should_panic(expected: ('ERC20: insufficient allowance',))]
fn test_burn_from_without_approval() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Add minter and mint tokens
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    let initial_balance: u256 = 18000000000000000000; // 18e18
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(token_holder, initial_balance);
    stop_cheat_caller_address(contract_address);
    
    // Attempt to burnFrom without approval
    let burn_amount: u256 = 9000000000000000000; // 9e18
    start_cheat_caller_address(contract_address, third_party);
    l2tbtc.burnFrom(token_holder, burn_amount); // Should panic
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic]
fn test_burn_from_insufficient_balance() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };
    
    // Add minter and mint small amount of tokens
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    let initial_balance: u256 = 5000000000000000000; // 5e18
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(token_holder, initial_balance);
    stop_cheat_caller_address(contract_address);
    
    // Approve large amount
    let burn_amount: u256 = 9000000000000000000; // 9e18
    start_cheat_caller_address(contract_address, token_holder);
    erc20.approve(third_party, burn_amount);
    stop_cheat_caller_address(contract_address);
    
    // Attempt to burn more than balance
    start_cheat_caller_address(contract_address, third_party);
    l2tbtc.burnFrom(token_holder, burn_amount); // Should panic
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_permit() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let minter = contract_address_const::<'MINTER'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>();
    let permitting_holder = contract_address_const::<'PERMITTING_HOLDER'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    let erc20 = ERC20ABIDispatcher { contract_address };
    
    // Add minter and mint initial tokens (70 tokens)
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    stop_cheat_caller_address(contract_address);
    
    let initial_balance: u256 = 70000000000000000000; // 70e18
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.mint(permitting_holder, initial_balance);
    stop_cheat_caller_address(contract_address);

    // Setup event spy BEFORE the approval
    let mut spy = spy_events();

    // Do the approve
    start_cheat_caller_address(contract_address, permitting_holder);
    erc20.approve(third_party, initial_balance);
    stop_cheat_caller_address(contract_address);
    
    // Verify allowance was set correctly
    assert(
        erc20.allowance(permitting_holder, third_party) == initial_balance,
        'Wrong allowance amount'
    );
    
    // Verify Approval event was emitted
    // Note: We need to use the correct event type from the ERC20Component
    spy.assert_emitted(
        @array![
            (
                contract_address,
                ERC20Component::Event::Approval(
                    ERC20Component::Approval {
                        owner: permitting_holder,
                        spender: third_party,
                        value: initial_balance
                    }
                )
            )
        ]
    );
}