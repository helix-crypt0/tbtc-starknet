use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, 
    start_cheat_caller_address, stop_cheat_caller_address,
    spy_events, EventSpyAssertionsTrait};

use starknet::{ContractAddress, contract_address_const};

// Import openzeppelin traits for the components used in L2TBTC
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
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

// Define event enum for testing
#[derive(Drop, starknet::Event)]
enum Event {
    MinterAdded: MinterAdded,
    MinterRemoved: MinterRemoved,
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
}

#[test]
fn test_deployment() {
    // Define test owner address
    let owner = contract_address_const::<'OWNER'>();
    
    // Declare and deploy L2TBTC contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
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
    assert(name == "L2TBTC", 'Name should be L2TBTC');
    assert(symbol == "TBTC", 'Symbol should be TBTC');
    assert(contract_owner == owner, 'Owner not set correctly');
    assert(total_supply == 0, 'Initial supply should be 0');
}

#[test]
fn test_erc20_basic_operations() {
    // Setup
    let owner = contract_address_const::<'OWNER'>();
    let user1 = contract_address_const::<'USER1'>();
    let user2 = contract_address_const::<'USER2'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let erc20 = ERC20ABIDispatcher { contract_address };
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Test initial balances
    assert(erc20.balance_of(user1) == 0, 'Initial balance should be 0');
    
    // Mint tokens to user1 (from owner)
    let mint_amount: u256 = 1000;
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.mint(user1, mint_amount);
    
    // Test balance after mint
    assert(erc20.balance_of(user1) == mint_amount, 'Balance after mint incorrect');
    stop_cheat_caller_address(contract_address);
    // // Test transfer
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
    let user1 = contract_address_const::<'USER1'>();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let erc20 = ERC20ABIDispatcher { contract_address };
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    
    // Test initial state
    assert(erc20.total_supply() == 0, 'Initial supply should be 0');
    assert(erc20.balance_of(user1) == 0, 'Initial balance should be 0');
    
    // Test minting (only owner can mint)
    let mint_amount: u256 = 1000;
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.mint(user1, mint_amount);
    stop_cheat_caller_address(contract_address);
    
    // Verify mint results
    assert(erc20.total_supply() == mint_amount, 'Total supply after mint');
    assert(erc20.balance_of(user1) == mint_amount, 'User balance after mint');
    
    // Test burning (only owner can burn)
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
#[should_panic(expected: ('not owner or minter',))]
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
    
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.addMinter(minter);
    
    // Capture events using spy_events
    let mut spy = spy_events();
    
    // Remove minter as owner
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


