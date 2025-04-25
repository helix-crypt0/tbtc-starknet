use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, 
    start_cheat_caller_address, stop_cheat_caller_address,
    spy_events, EventSpyAssertionsTrait };

use starknet::{ContractAddress, contract_address_const};
// Import openzeppelin traits for the components used in L2TBTC
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

use openzeppelin::token::erc20::ERC20Component;
use openzeppelin::token::erc721::interface::{IERC721, IERC721Dispatcher};
use openzeppelin::token::erc721::interface::{ERC721ABIDispatcher, ERC721ABIDispatcherTrait};
use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin::security::pausable::PausableComponent::{PausableImpl};
use l2tbtc::contracts::L2TBTC::{L2TBTC, IL2TBTCDispatcher, IL2TBTCDispatcherTrait};


fn OWNER() -> ContractAddress {
    contract_address_const::<'OWNER'>()
}

fn token_deploy_args(
    owner: ContractAddress,
) -> Array<felt252> {
    let mut calldata = ArrayTrait::new();
    let _name_ignore: felt252 = 0;
    let _symbol_ignore: felt252 = 0;
    let _decimals_ignore: u8 = 0;
    let _initial_supply_ignore: u256 = 0;
    let _initial_recipient_ignore: ContractAddress = contract_address_const::<'INITIAL_RECIPIENT'>();
    let _initial_minter_ignore: ContractAddress = contract_address_const::<'INITIAL_MINTER'>();
    let _upgrade_delay_ignore: u64 = 0;
    Serde::serialize(@_name_ignore, ref calldata);
    Serde::serialize(@_symbol_ignore, ref calldata);
    Serde::serialize(@_decimals_ignore, ref calldata);
    Serde::serialize(@_initial_supply_ignore, ref calldata);
    Serde::serialize(@_initial_recipient_ignore, ref calldata);
    Serde::serialize(@_initial_minter_ignore, ref calldata);
    Serde::serialize(@owner, ref calldata);
    Serde::serialize(@_upgrade_delay_ignore, ref calldata);

    calldata
}

fn setup() -> (ERC20ABIDispatcher, IL2TBTCDispatcher, ContractAddress, ContractAddress) {
    // Setup
    let owner = OWNER();
    
    // Deploy contract
    let contract = declare("L2TBTC").unwrap().contract_class();
    let constructor_args = token_deploy_args(owner);
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    let erc20 = ERC20ABIDispatcher { contract_address };
    let l2tbtc = IL2TBTCDispatcher { contract_address };
    return (erc20, l2tbtc, contract_address, owner);
}

fn ERC20_MOCK() -> ERC20ABIDispatcher {
    let token_contract = declare("TestERC20").unwrap().contract_class();
    let mut constructor_calldata = array![];
    let name: ByteArray = "Wrapped Ethereum";
    let symbol: ByteArray = "WETH";
    let initial_supply: u256 = 2000000000000000000000000;
    let recipient: ContractAddress = OWNER();

    name.serialize(ref constructor_calldata);
    symbol.serialize(ref constructor_calldata);
    initial_supply.serialize(ref constructor_calldata);
    recipient.serialize(ref constructor_calldata);

    let (contract_address, _) = token_contract.deploy(@constructor_calldata).unwrap();
    let erc20 = ERC20ABIDispatcher { contract_address };
    return erc20;
}

fn ERC721_MOCK() -> (ERC721ABIDispatcher, ContractAddress) {
    let token_contract = declare("TestERC721").unwrap().contract_class();
    let recipient = contract_address_const::<'RECIPIENT'>();
    let mut constructor_calldata = array![];
    recipient.serialize(ref constructor_calldata);

    let (contract_address, _) = token_contract.deploy(@constructor_calldata).unwrap();
    let erc721 = ERC721ABIDispatcher { contract_address };
    return (erc721, contract_address);
}


#[test]
fn test_deployment() {
    // Define test owner address
    let (erc20_dispatcher, _, contract_address, owner) = setup();   
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
    
    let user1 = contract_address_const::<'USER1'>();
    let user2 = contract_address_const::<'USER2'>();
    let minter = contract_address_const::<'MINTER'>();
    
    // Deploy contract
    let (erc20, l2tbtc, contract_address, owner) = setup();
    
    // Test initial balances
    assert(erc20.balance_of(user1) == 0, 'Initial balance should be 0');
    
    // Add minter role
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Mint tokens to user1 (from minter)
    let mint_amount: u256 = 1000;
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(user1, mint_amount);
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
    let minter = contract_address_const::<'MINTER'>();
    let user1 = contract_address_const::<'USER1'>();
    
    // Deploy contract
    let (erc20, l2tbtc, contract_address, owner) = setup();
    
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Test initial state
    assert(erc20.total_supply() == 0, 'Initial supply should be 0');
    assert(erc20.balance_of(user1) == 0, 'Initial balance should be 0');
    
    // Test minting (only minters can mint)
    let mint_amount: u256 = 1000;
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(user1, mint_amount);
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
    let (_, l2tbtc, contract_address, _) = setup();
    let user1 = contract_address_const::<'USER1'>();
    let user2 = contract_address_const::<'USER2'>(); // Unauthorized user
    
    // Try to mint tokens as unauthorized user (should fail)
    let mint_amount: u256 = 1000;
    start_cheat_caller_address(contract_address, user2);
    l2tbtc.permissioned_mint(user1, mint_amount);
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_unauthorized_add_minter() {
    // Setup
    let user1 = contract_address_const::<'USER1'>();
    let user2 = contract_address_const::<'USER2'>();
    let (_, l2tbtc, contract_address, _) = setup();
    
    // Try to add a minter as unauthorized user (should fail)
    start_cheat_caller_address(contract_address, user1);
    l2tbtc.add_minter(user2); // This should panic with 'Ownable: caller is not the owner'
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_minter_cannot_add_minter() {
    // Setup
    let (_, l2tbtc, contract_address, owner) = setup();
    let user1 = contract_address_const::<'USER1'>();
    let user2 = contract_address_const::<'USER2'>();
    
    // Add user1 as minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(user1);
    stop_cheat_caller_address(contract_address);
    
    // Test that a minter cannot add another minter
    start_cheat_caller_address(contract_address, user1);
    l2tbtc.add_minter(user2); // This should panic with 'Caller is not the owner'
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_add_minter() {
    // Setup
    let (erc20, l2tbtc, contract_address, owner) = setup();
    let user1 = contract_address_const::<'USER1'>();
    
    // Add user1 as minter (only owner can add minters)
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(user1);
    stop_cheat_caller_address(contract_address);
    
    // Test initial balance
    assert(erc20.balance_of(user1) == 0, 'Initial balance should be 0');
    
    // Have user1 mint tokens to itself
    let mint_amount: u256 = 1000;
    start_cheat_caller_address(contract_address, user1);
    l2tbtc.permissioned_mint(user1, mint_amount);
    stop_cheat_caller_address(contract_address);
    
    // Verify mint results
    assert(erc20.total_supply() == mint_amount, 'Total supply after mint');
    assert(erc20.balance_of(user1) == mint_amount, 'User balance after mint');
}

#[test]
#[should_panic(expected: ('Already a minter',))]
fn test_add_duplicate_minter() {
    // Setup
    let (_, l2tbtc, contract_address, owner) = setup();
    let user1 = contract_address_const::<'USER1'>();
    
    // Add user1 as minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(user1);
    
    // Try to add the same user as minter again (should fail)
    l2tbtc.add_minter(user1);
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_minter_added_event() {
    // Setup
    let user1 = contract_address_const::<'USER1'>();
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Capture events using spy_events approach
    let mut spy = spy_events();
    
    // Add user1 as minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(user1);
    stop_cheat_caller_address(contract_address);
    
    // Assert the emitted event using the local event definition
    spy.assert_emitted(
        @array![
            (
                contract_address,
                L2TBTC::Event::MinterAdded(
                    L2TBTC::MinterAdded { minter: user1 }
                )
            )
        ]
    );
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_unauthorized_remove_minter() {
    // Setup
    let user1 = contract_address_const::<'USER1'>();
    let user2 = contract_address_const::<'USER2'>(); // Unauthorized user
    
    // Deploy contract
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Add user1 as minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(user1);
    stop_cheat_caller_address(contract_address);
    
    // Try to remove a minter as unauthorized user (should fail)
    start_cheat_caller_address(contract_address, user2);
    l2tbtc.remove_minter(user1); // This should panic with 'Caller is not the owner'
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_minter_cannot_remove_minter() {
    // Setup
    let user1 = contract_address_const::<'USER1'>();
    let user2 = contract_address_const::<'USER2'>();
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Add user1 and user2 as minters
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(user1);
    l2tbtc.add_minter(user2);
    stop_cheat_caller_address(contract_address);
    
    // Test that a minter cannot remove another minter
    start_cheat_caller_address(contract_address, user1);
    l2tbtc.remove_minter(user2); // This should panic with 'Caller is not the owner'
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_guardian_cannot_remove_minter() {
    // Setup
    let guardian = contract_address_const::<'GUARDIAN'>();
    let minter = contract_address_const::<'MINTER'>();
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Add guardian and minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_guardian(guardian);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Test that a guardian cannot remove a minter
    start_cheat_caller_address(contract_address, guardian);
    l2tbtc.remove_minter(minter); // This should panic with 'Caller is not the owner'
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Not a guardian',))]
fn test_unauthorized_pause() {
    // Setup
    let user1 = contract_address_const::<'USER1'>(); // Unauthorized user
    let (_, l2tbtc, contract_address, _) = setup();
    
    // Try to pause as unauthorized user (should fail)
    start_cheat_caller_address(contract_address, user1);
    l2tbtc.pause(); // This should panic with 'Caller is not a guardian'
    stop_cheat_caller_address(contract_address);
}


#[test]
fn test_owner_can_remove_minter() {
    // Setup
    let minter = contract_address_const::<'MINTER'>();
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Capture events using spy_events
    let mut spy = spy_events();
    
    // Remove minter as owner
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    l2tbtc.remove_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Assert the emitted event
    spy.assert_emitted(
        @array![
            (
                contract_address,
                L2TBTC::Event::MinterRemoved(
                    L2TBTC::MinterRemoved { minter }
                )
            )
        ]
    );
}

#[test]
fn test_remove_minter_updates_list_correctly() {
    // Setup
    let minter1 = contract_address_const::<'MINTER1'>();
    let minter2 = contract_address_const::<'MINTER2'>();
    let minter3 = contract_address_const::<'MINTER3'>();
    let (_, l2tbtc, contract_address, owner) = setup();

    // Add multiple minters
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter1);
    l2tbtc.add_minter(minter2); 
    l2tbtc.add_minter(minter3);

    // Initial minters list should contain all three
    let initial_minters = l2tbtc.get_minters();
    assert(initial_minters.len() == 3, 'Wrong initial minters count');
    assert(*initial_minters.at(0) == minter1, 'Wrong minter at index 0');
    assert(*initial_minters.at(1) == minter2, 'Wrong minter at index 1');
    assert(*initial_minters.at(2) == minter3, 'Wrong minter at index 2');

    // Remove middle minter (minter2)
    l2tbtc.remove_minter(minter2);

    // Check updated list - should have minter1 and minter3, with minter3 moved to minter2's position
    let updated_minters = l2tbtc.get_minters();
    assert(updated_minters.len() == 2, 'Wrong final minters count');
    assert(*updated_minters.at(0) == minter1, 'Wrong 1st minter after remove');
    assert(*updated_minters.at(1) == minter3, 'Wrong 2nd minter after remove');

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_is_minter() {
    // Setup
    let minter = contract_address_const::<'MINTER'>();
    let non_minter = contract_address_const::<'NON_MINTER'>();
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Check initial state
    assert(!l2tbtc.is_minter(minter), 'Should not be minter initially');
    assert(!l2tbtc.is_minter(non_minter), 'Should not be minter initially');
    
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Verify minter status
    assert(l2tbtc.is_minter(minter), 'Should be minter after adding');
    assert(!l2tbtc.is_minter(non_minter), 'Should still not be minter');
    
    // Remove minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.remove_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Verify minter status after removal
    assert(!l2tbtc.is_minter(minter), 'Not a minter after removal');
}

#[test]
fn test_multiple_minters_addition() {
    // Setup
    let minter1 = contract_address_const::<'MINTER1'>();
    let minter2 = contract_address_const::<'MINTER2'>();
    let minter3 = contract_address_const::<'MINTER3'>();
    
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Verify initial empty state
    let initial_minters = l2tbtc.get_minters();
    assert(initial_minters.len() == 0, 'Should start with no minters');
    
    // Add multiple minters
    start_cheat_caller_address(contract_address, owner);
    
    // Add first minter and verify
    l2tbtc.add_minter(minter1);
    assert(l2tbtc.is_minter(minter1), 'Minter1 should be minter');
    let minters_after_first = l2tbtc.get_minters();
    assert(minters_after_first.len() == 1, 'Should have one minter');
    assert(*minters_after_first.at(0) == minter1, 'First minter wrong');
    
    // Add second minter and verify
    l2tbtc.add_minter(minter2);
    assert(l2tbtc.is_minter(minter2), 'Minter2 should be minter');
    let minters_after_second = l2tbtc.get_minters();
    assert(minters_after_second.len() == 2, 'Should have two minters');
    assert(*minters_after_second.at(0) == minter1, 'First minter changed');
    assert(*minters_after_second.at(1) == minter2, 'Second minter wrong');
    
    // Add third minter and verify
    l2tbtc.add_minter(minter3);
    assert(l2tbtc.is_minter(minter3), 'Minter3 should be minter');
    let final_minters = l2tbtc.get_minters();
    assert(final_minters.len() == 3, 'Should have three minters');
    assert(*final_minters.at(0) == minter1, 'First minter changed');
    assert(*final_minters.at(1) == minter2, 'Second minter changed');
    assert(*final_minters.at(2) == minter3, 'Third minter wrong');
    
    // Verify all minters are still valid
    assert(l2tbtc.is_minter(minter1), 'Minter1 should still be minter');
    assert(l2tbtc.is_minter(minter2), 'Minter2 should still be minter');
    assert(l2tbtc.is_minter(minter3), 'Minter3 should still be minter');
    
    stop_cheat_caller_address(contract_address);
}


#[test]
#[should_panic(expected: ('Not a minter',))]
fn test_remove_non_minter() {
    // Setup
    let non_minter = contract_address_const::<'NON_MINTER'>();
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Try to remove a non-minter address
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.remove_minter(non_minter); // Should panic with 'Not a minter'
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_remove_first_minter() {
    // Setup
    let minter1 = contract_address_const::<'MINTER1'>();
    let minter2 = contract_address_const::<'MINTER2'>();
    let minter3 = contract_address_const::<'MINTER3'>();
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Add three minters
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter1);
    l2tbtc.add_minter(minter2);
    l2tbtc.add_minter(minter3);
    
    // Verify initial state
    let initial_minters = l2tbtc.get_minters();
    assert(initial_minters.len() == 3, 'Should have three minters');
    assert(*initial_minters.at(0) == minter1, 'First minter wrong');
    assert(*initial_minters.at(1) == minter2, 'Second minter wrong');
    assert(*initial_minters.at(2) == minter3, 'Third minter wrong');
    
    // Remove first minter
    let mut spy = spy_events();
    l2tbtc.remove_minter(minter1);
    
    // Verify event was emitted
    spy.assert_emitted(
        @array![
            (
                contract_address,
                L2TBTC::Event::MinterRemoved(
                    L2TBTC::MinterRemoved { minter: minter1 }
                )
            )
        ]
    );
    
    // Verify minter was removed
    assert(!l2tbtc.is_minter(minter1), 'Minter1 should not be minter');
    
    // Verify remaining minters
    let final_minters = l2tbtc.get_minters();
    assert(final_minters.len() == 2, 'Should have two minters');
    assert(*final_minters.at(0) == minter3, 'First minter wrong'); // Last minter moved to first position
    assert(*final_minters.at(1) == minter2, 'Second minter wrong');
    
    // Verify remaining minters are still valid
    assert(l2tbtc.is_minter(minter2), 'Minter2 should still be minter');
    assert(l2tbtc.is_minter(minter3), 'Minter3 should still be minter');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_remove_last_minter() {
    // Setup
    let minter1 = contract_address_const::<'MINTER1'>();
    let minter2 = contract_address_const::<'MINTER2'>();
    let minter3 = contract_address_const::<'MINTER3'>();
    
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Add multiple minters
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter1);
    l2tbtc.add_minter(minter2);
    l2tbtc.add_minter(minter3);
    
    // Verify initial state
    let initial_minters = l2tbtc.get_minters();
    assert(initial_minters.len() == 3, 'Should have three minters');
    assert(*initial_minters.at(0) == minter1, 'First minter wrong');
    assert(*initial_minters.at(1) == minter2, 'Second minter wrong');
    assert(*initial_minters.at(2) == minter3, 'Last minter wrong');
    
    // Remove the last minter
    let mut spy = spy_events();
    l2tbtc.remove_minter(minter3);
    
    // Verify event was emitted
    spy.assert_emitted(
        @array![
            (
                contract_address,
                L2TBTC::Event::MinterRemoved(
                    L2TBTC::MinterRemoved { minter: minter3 }
                )
            )
        ]
    );
    
    // Verify last minter was removed
    assert(!l2tbtc.is_minter(minter3), 'Last minter should be removed');
    
    // Verify remaining minters array
    let final_minters = l2tbtc.get_minters();
    assert(final_minters.len() == 2, 'Should have two minters');
    assert(*final_minters.at(0) == minter1, 'First minter wrong');
    assert(*final_minters.at(1) == minter2, 'Second minter wrong');
    
    // Verify other minters still exist
    assert(l2tbtc.is_minter(minter1), 'First minter should remain');
    assert(l2tbtc.is_minter(minter2), 'Second minter should remain');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_unauthorized_add_guardian() {
    let unauthorized = contract_address_const::<'UNAUTHORIZED'>();
    let (_, l2tbtc, contract_address, _) = setup();
    
    // Try to add a guardian as unauthorized user (should fail)
    start_cheat_caller_address(contract_address, unauthorized);
    l2tbtc.add_guardian(unauthorized); // This should panic with 'Caller is not the owner'
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_owner_can_add_guardian() {
    // Setup
    let guardian = contract_address_const::<'GUARDIAN'>();
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Add guardian as owner
    let mut spy = spy_events();
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_guardian(guardian);
    stop_cheat_caller_address(contract_address);
    
    // Verify guardian was added
    assert(l2tbtc.is_guardian(guardian), 'Should be guardian');
    
    // Verify event was emitted
    spy.assert_emitted(
        @array![
            (
                contract_address,
                L2TBTC::Event::GuardianAdded(
                    L2TBTC::GuardianAdded { guardian }
                )
            )
        ]
    );
}

#[test]
#[should_panic(expected: ('Already a guardian',))]
fn test_add_duplicate_guardian() {
    let guardian = contract_address_const::<'GUARDIAN'>();
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Add guardian first time
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_guardian(guardian);
    
    // Try to add same guardian again (should fail)
    l2tbtc.add_guardian(guardian);
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_multiple_guardians() {
    // Setup
    let guardian1 = contract_address_const::<'GUARDIAN1'>();
    let guardian2 = contract_address_const::<'GUARDIAN2'>();
    let guardian3 = contract_address_const::<'GUARDIAN3'>();
    
    // Deploy contract
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Add multiple guardians
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_guardian(guardian1);
    l2tbtc.add_guardian(guardian2);
    l2tbtc.add_guardian(guardian3);
    stop_cheat_caller_address(contract_address);
    
    // Get guardians list
    let guardians = l2tbtc.get_guardians();
    
    // Verify guardians list
    assert(guardians.len() == 3, 'Should have three guardians');
    assert(*guardians.at(0) == guardian1, 'First guardian wrong');
    assert(*guardians.at(1) == guardian2, 'Second guardian wrong');
    assert(*guardians.at(2) == guardian3, 'Third guardian wrong');
    
    // Verify each guardian status
    assert(l2tbtc.is_guardian(guardian1), 'Guardian1 should be guardian');
    assert(l2tbtc.is_guardian(guardian2), 'Guardian2 should be guardian');
    assert(l2tbtc.is_guardian(guardian3), 'Guardian3 should be guardian');
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_unauthorized_remove_guardian() {
    // Setup
    let guardian = contract_address_const::<'GUARDIAN'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>(); // Unauthorized user
    
    // Deploy contract
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Add guardian as owner
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_guardian(guardian);
    stop_cheat_caller_address(contract_address);
    
    // Try to remove guardian as unauthorized user (should fail)
    start_cheat_caller_address(contract_address, third_party);
    l2tbtc.remove_guardian(guardian); // This should panic with 'Caller is not the owner'
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Not a guardian',))]
fn test_remove_non_guardian() {
    // Setup
    let non_guardian = contract_address_const::<'NON_GUARDIAN'>();
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Try to remove a non-guardian address (should fail)
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.remove_guardian(non_guardian); // Should panic with 'Not a guardian'
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_guardian_cannot_remove_guardian() {
    // Setup
    let guardian1 = contract_address_const::<'GUARDIAN1'>();
    let guardian2 = contract_address_const::<'GUARDIAN2'>();
    
    // Deploy contract
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Add guardian1 and guardian2
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_guardian(guardian1);
    l2tbtc.add_guardian(guardian2);
    stop_cheat_caller_address(contract_address);
    
    // Test that a guardian cannot remove another guardian
    start_cheat_caller_address(contract_address, guardian1);
    l2tbtc.remove_guardian(guardian2); // This should panic with 'Caller is not the owner'
    stop_cheat_caller_address(contract_address);
}

fn test_remove_guardian_success() {
    // Setup
    let guardian = contract_address_const::<'GUARDIAN'>();
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Add guardian first
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_guardian(guardian);
    
    // Verify guardian was added
    assert(l2tbtc.is_guardian(guardian), 'Should be guardian initially');
    assert(l2tbtc.get_guardians().len() == 1, 'Should have one guardian');
    
    // Capture events for removal
    let mut spy = spy_events();
    
    // Remove guardian
    l2tbtc.remove_guardian(guardian);
    stop_cheat_caller_address(contract_address);
    
    // Verify guardian was removed
    assert(!l2tbtc.is_guardian(guardian), 'Should not be guardian after');
    assert(l2tbtc.get_guardians().len() == 0, 'Should have no guardians');
    
    // Verify event was emitted
    spy.assert_emitted(
        @array![
            (
                contract_address,
                L2TBTC::Event::GuardianRemoved(
                    L2TBTC::GuardianRemoved { guardian }
                )
            )
        ]
    );
}

#[test]
fn test_remove_guardian_updates_list_correctly() {
    // Setup
    let guardian1 = contract_address_const::<'GUARDIAN1'>();
    let guardian2 = contract_address_const::<'GUARDIAN2'>();
    let guardian3 = contract_address_const::<'GUARDIAN3'>();
    let guardian4 = contract_address_const::<'GUARDIAN4'>();
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Add multiple guardians
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_guardian(guardian1);
    l2tbtc.add_guardian(guardian2);
    l2tbtc.add_guardian(guardian3);
    l2tbtc.add_guardian(guardian4);
    
    // Verify initial state
    let initial_guardians = l2tbtc.get_guardians();
    assert(initial_guardians.len() == 4, 'Should have four guardians');
    assert(*initial_guardians.at(0) == guardian1, 'Wrong 1st guardian');
    assert(*initial_guardians.at(1) == guardian2, 'Wrong 2nd guardian');
    assert(*initial_guardians.at(2) == guardian3, 'Wrong 3rd guardian');
    assert(*initial_guardians.at(3) == guardian4, 'Wrong 4th guardian');
    
    // Test removing first guardian
    l2tbtc.remove_guardian(guardian1);
    let guardians_after_first = l2tbtc.get_guardians();
    assert(guardians_after_first.len() == 3, 'Should have three guardians');
    assert(*guardians_after_first.at(0) == guardian4, 'Wrong 1st after remove');
    assert(*guardians_after_first.at(1) == guardian2, 'Wrong 2nd after remove');
    assert(*guardians_after_first.at(2) == guardian3, 'Wrong 3rd after remove');
    
    // Test removing last guardian
    l2tbtc.remove_guardian(guardian3);
    let guardians_after_last = l2tbtc.get_guardians();
    assert(guardians_after_last.len() == 2, 'Should have two guardians');
    assert(*guardians_after_last.at(0) == guardian4, 'Wrong 1st after last');
    assert(*guardians_after_last.at(1) == guardian2, 'Wrong 2nd after last');
    
    // Test removing from middle
    l2tbtc.remove_guardian(guardian2);
    let final_guardians = l2tbtc.get_guardians();
    assert(final_guardians.len() == 1, 'Should have one guardian');
    assert(*final_guardians.at(0) == guardian4, 'Wrong final guardian');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Not a guardian',))]
fn test_remove_non_existent_guardian() {
    let non_existent = contract_address_const::<'NON_EXISTENT'>();
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Try to remove a non-existent guardian
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.remove_guardian(non_existent); // Should panic with 'Not a guardian'
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_single_guardian_removal() {
    let guardian = contract_address_const::<'GUARDIAN'>();
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Add guardian
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_guardian(guardian);
    
    // Verify initial state
    assert(l2tbtc.is_guardian(guardian), 'Should be guardian initially');
    let initial_guardians = l2tbtc.get_guardians();
    assert(initial_guardians.len() == 1, 'Should have one guardian');
    assert(*initial_guardians.at(0) == guardian, 'Wrong guardian in list');
    
    // Setup event spy
    let mut spy = spy_events();
    
    // Remove guardian
    l2tbtc.remove_guardian(guardian);
    stop_cheat_caller_address(contract_address);
    
    // Verify guardian was removed
    assert(!l2tbtc.is_guardian(guardian), 'Should not be guardian after');
    let final_guardians = l2tbtc.get_guardians();
    assert(final_guardians.len() == 0, 'Should have no guardians');
    
    // Verify event was emitted
    spy.assert_emitted(
        @array![
            (
                contract_address,
                L2TBTC::Event::GuardianRemoved(
                    L2TBTC::GuardianRemoved { guardian }
                )
            )
        ]
    );
}

#[test]
fn test_guardian_removal_and_readd() {
    let guardian = contract_address_const::<'GUARDIAN'>();
    let (_, l2tbtc, contract_address, owner) = setup();
    
    start_cheat_caller_address(contract_address, owner);
    
    // Add guardian
    l2tbtc.add_guardian(guardian);
    assert(l2tbtc.is_guardian(guardian), 'Should be guardian after add');
    
    // Remove guardian
    l2tbtc.remove_guardian(guardian);
    assert(!l2tbtc.is_guardian(guardian), 'Not a guardian after remove');
    
    // Re-add guardian
    l2tbtc.add_guardian(guardian);
    assert(l2tbtc.is_guardian(guardian), 'Should be guardian after readd');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_guardian_state_after_removal() {
    let guardian = contract_address_const::<'GUARDIAN'>();
    let (_, l2tbtc, contract_address, owner) = setup();
    
    start_cheat_caller_address(contract_address, owner);
    
    // Add and remove guardian
    l2tbtc.add_guardian(guardian);
    l2tbtc.remove_guardian(guardian);
    
    // Verify final state
    assert(!l2tbtc.is_guardian(guardian), 'Should not be guardian');
    let guardians = l2tbtc.get_guardians();
    assert(guardians.len() == 0, 'Should have empty guardian list');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_guardian_removal_events_sequence() {
    // Setup
    let guardian = contract_address_const::<'GUARDIAN'>();
    let (_, l2tbtc, contract_address, owner) = setup();
    
    // Setup event spy
    let mut spy = spy_events();
    
    start_cheat_caller_address(contract_address, owner);
    
    // Add guardian
    l2tbtc.add_guardian(guardian);
    
    // Remove guardian
    l2tbtc.remove_guardian(guardian);
    
    stop_cheat_caller_address(contract_address);
    
    // Verify both events were emitted in correct sequence
    spy.assert_emitted(
        @array![
            (
                contract_address,
                L2TBTC::Event::GuardianAdded(
                    L2TBTC::GuardianAdded { guardian }
                )
            ),
            (
                contract_address,
                L2TBTC::Event::GuardianRemoved(
                    L2TBTC::GuardianRemoved { guardian }
                )
            )
        ]
    );
}

#[test]
fn test_multiple_guardian_removal() {
    // Setup with multiple guardians
    let guardian1 = contract_address_const::<'GUARDIAN1'>();
    let guardian2 = contract_address_const::<'GUARDIAN2'>();
    let guardian3 = contract_address_const::<'GUARDIAN3'>();
    let guardian4 = contract_address_const::<'GUARDIAN4'>();
    
    let (_, l2tbtc, contract_address, owner) = setup();
    
    start_cheat_caller_address(contract_address, owner);
    
    // Add multiple guardians
    l2tbtc.add_guardian(guardian1);
    l2tbtc.add_guardian(guardian2);
    l2tbtc.add_guardian(guardian3);
    l2tbtc.add_guardian(guardian4);
    
    // Verify initial state
    let initial_guardians = l2tbtc.get_guardians();
    assert(initial_guardians.len() == 4, 'Should have four guardians');
    assert(*initial_guardians.at(0) == guardian1, 'Wrong 1st guardian');
    assert(*initial_guardians.at(1) == guardian2, 'Wrong 2nd guardian');
    assert(*initial_guardians.at(2) == guardian3, 'Wrong 3rd guardian');
    assert(*initial_guardians.at(3) == guardian4, 'Wrong 4th guardian');
    
    // Remove guardians in different order
    l2tbtc.remove_guardian(guardian2); // Remove from middle
    l2tbtc.remove_guardian(guardian4); // Remove from end
    l2tbtc.remove_guardian(guardian1); // Remove from beginning
    
    // Verify final state
    let final_guardians = l2tbtc.get_guardians();
    assert(final_guardians.len() == 1, 'Should have one guardian');
    assert(*final_guardians.at(0) == guardian3, 'Wrong remaining guardian');
    
    // Verify removed guardians status
    assert(!l2tbtc.is_guardian(guardian1), 'Guardian1 should be removed');
    assert(!l2tbtc.is_guardian(guardian2), 'Guardian2 should be removed');
    assert(l2tbtc.is_guardian(guardian3), 'Guardian3 should remain');
    assert(!l2tbtc.is_guardian(guardian4), 'Guardian4 should be removed');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_remove_first_guardian() {
    // Setup
    let guardian1 = contract_address_const::<'GUARDIAN1'>();
    let guardian2 = contract_address_const::<'GUARDIAN2'>();
    let guardian3 = contract_address_const::<'GUARDIAN3'>();
    
    let (_, l2tbtc, contract_address, owner) = setup();
    
    start_cheat_caller_address(contract_address, owner);
    
    // Add guardians
    l2tbtc.add_guardian(guardian1);
    l2tbtc.add_guardian(guardian2);
    l2tbtc.add_guardian(guardian3);
    
    // Remove first guardian
    let mut spy = spy_events();
    l2tbtc.remove_guardian(guardian1);
    
    // Verify event emission
    spy.assert_emitted(
        @array![
            (
                contract_address,
                L2TBTC::Event::GuardianRemoved(
                    L2TBTC::GuardianRemoved { guardian: guardian1 }
                )
            )
        ]
    );
    
    // Verify list update
    let guardians = l2tbtc.get_guardians();
    assert(guardians.len() == 2, 'Should have two guardians');
    assert(*guardians.at(0) == guardian3, 'Wrong first guardian'); // Last guardian moved to first position
    assert(*guardians.at(1) == guardian2, 'Wrong second guardian');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_remove_middle_guardian() {
    // Setup
    let guardian1 = contract_address_const::<'GUARDIAN1'>();
    let guardian2 = contract_address_const::<'GUARDIAN2'>();
    let guardian3 = contract_address_const::<'GUARDIAN3'>();
    
    let (_, l2tbtc, contract_address, owner) = setup();
    
    start_cheat_caller_address(contract_address, owner);
    
    // Add guardians
    l2tbtc.add_guardian(guardian1);
    l2tbtc.add_guardian(guardian2);
    l2tbtc.add_guardian(guardian3);
    
    // Remove middle guardian
    let mut spy = spy_events();
    l2tbtc.remove_guardian(guardian2);
    
    // Verify event emission
    spy.assert_emitted(
        @array![
            (
                contract_address,
                L2TBTC::Event::GuardianRemoved(
                    L2TBTC::GuardianRemoved { guardian: guardian2 }
                )
            )
        ]
    );
    
    // Verify list update
    let guardians = l2tbtc.get_guardians();
    assert(guardians.len() == 2, 'Should have two guardians');
    assert(*guardians.at(0) == guardian1, 'Wrong first guardian');
    assert(*guardians.at(1) == guardian3, 'Wrong second guardian');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_remove_last_guardian() {
    // Setup
    let guardian1 = contract_address_const::<'GUARDIAN1'>();
    let guardian2 = contract_address_const::<'GUARDIAN2'>();
    let guardian3 = contract_address_const::<'GUARDIAN3'>();
    
    let (_, l2tbtc, contract_address, owner) = setup();
    
    start_cheat_caller_address(contract_address, owner);
    
    // Add guardians
    l2tbtc.add_guardian(guardian1);
    l2tbtc.add_guardian(guardian2);
    l2tbtc.add_guardian(guardian3);
    
    // Remove last guardian
    let mut spy = spy_events();
    l2tbtc.remove_guardian(guardian3);
    
    // Verify event emission
    spy.assert_emitted(
        @array![
            (
                contract_address,
                L2TBTC::Event::GuardianRemoved(
                    L2TBTC::GuardianRemoved { guardian: guardian3 }
                )
            )
        ]
    );
    
    // Verify list update
    let guardians = l2tbtc.get_guardians();
    assert(guardians.len() == 2, 'Should have two guardians');
    assert(*guardians.at(0) == guardian1, 'Wrong first guardian');
    assert(*guardians.at(1) == guardian2, 'Wrong second guardian');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_unauthorized_recover_erc20() {
    let (_, l2tbtc, contract_address, _) = setup();
    let third_party = contract_address_const::<'THIRD_PARTY'>(); // Unauthorized user
    let recipient = contract_address_const::<'RECIPIENT'>();

    // Deploy another L2TBTC as the token to recover
    let erc20_mock = ERC20_MOCK();

    // Send tokens TO the L2TBTC contract address FROM the OWNER of the mock tokens.
    // Cheat the caller for the erc20_mock contract to be OWNER().
    start_cheat_caller_address(erc20_mock.contract_address, OWNER()); // Corrected: Target erc20_mock, set caller to OWNER()
    erc20_mock.transfer(contract_address, 1000); // This transfer is now initiated by OWNER()
    stop_cheat_caller_address(erc20_mock.contract_address); // Corrected: Stop cheating erc20_mock

    // Confirm the L2TBTC contract now has 1000 tokens
    assert(erc20_mock.balance_of(contract_address) == 1000, 'Wrong initial balance');

    // Attempt to recover tokens as unauthorized user (triggering NOT the owner check on L2TBTC):
    start_cheat_caller_address(contract_address, third_party); // Correct: Cheat calls to L2TBTC to be from third_party
    l2tbtc.recover_ERC20(erc20_mock.contract_address, recipient, 999); // This should now panic with the expected owner error
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_owner_recover_erc20() {
    // Setup: Deploy L2TBTC and get owner address
    let (_, l2tbtc, contract_address, owner) = setup();
    let recipient = contract_address_const::<'RECIPIENT'>();
    let amount: u256 = 1000; // Define the amount to transfer and recover

    // Deploy a mock ERC20 token. Assume ERC20_MOCK() deploys and mints to OWNER() by default.
    let erc20_mock = ERC20_MOCK();

    // Transfer some mock ERC20 tokens *to* the L2TBTC contract address first.
    // We need to cheat the caller to be the owner of the mock tokens (assumed OWNER() here).
    start_cheat_caller_address(erc20_mock.contract_address, OWNER());
    erc20_mock.transfer(contract_address, amount);
    stop_cheat_caller_address(erc20_mock.contract_address);

    // Verify initial balance of the L2TBTC contract and recipient *after* the transfer
    assert(erc20_mock.balance_of(contract_address) == amount, 'L2TBTC balance incorrect');
    assert(erc20_mock.balance_of(recipient) == 0, 'Recipient should have 0');

    // Recover tokens *as the owner* of the L2TBTC contract
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.recover_ERC20(erc20_mock.contract_address, recipient, amount);
    stop_cheat_caller_address(contract_address);

    // Verify balances after recovery
    assert(erc20_mock.balance_of(contract_address) == 0, 'Contract should have 0');
    assert(erc20_mock.balance_of(recipient) == amount, 'Tokens not transferred');
}

#[test]
fn test_recover_partial_erc20_amount() {
    // Setup using the helper function
    let (_, l2tbtc, contract_address, owner) = setup();
    let recipient = contract_address_const::<'RECIPIENT'>();
    
    // Deploy the mock ERC20 token
    let erc20_mock = ERC20_MOCK(); // Assumes this mints initial supply to OWNER()
    
    // Define amounts
    let total_amount: u256 = 725_000_000_000_000_000_000; // 725 tokens with 18 decimals
    let partial_amount: u256 = total_amount / 2;
    
    // Transfer mock tokens *to* the L2TBTC contract address
    // Cheat caller to be the owner of the mock tokens (OWNER())
    start_cheat_caller_address(erc20_mock.contract_address, OWNER());
    erc20_mock.transfer(contract_address, total_amount);
    stop_cheat_caller_address(erc20_mock.contract_address);
    
    // Verify initial balance of the L2TBTC contract
    assert(erc20_mock.balance_of(contract_address) == total_amount, 'Wrong initial balance');
    assert(erc20_mock.balance_of(recipient) == 0, 'Recipient should have 0');
    
    // Recover only half of the tokens as the L2TBTC owner
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.recover_ERC20(erc20_mock.contract_address, recipient, partial_amount);
    stop_cheat_caller_address(contract_address);
    
    // Verify balances after partial recovery
    assert(erc20_mock.balance_of(contract_address) == partial_amount, 'Wrong contract balance');
    assert(erc20_mock.balance_of(recipient) == partial_amount, 'Wrong recipient balance');
}

#[test]
fn test_owner_recover_erc721() {
    // 1. Deploy the L2TBTC contract
    let (_, l2tbtc, contract_address, owner) = setup();

    // 2. Deploy and initialize a mock ERC721, which mints token #1 to RECIPIENT by default
    let (erc721, erc721_contract) = ERC721_MOCK();
    let nft_owner = contract_address_const::<'RECIPIENT'>();
    // Use the owner address from setup instead of a const address
    let new_recipient = owner; 
    let token_id: u256 = 1;

    // Confirm that the initial (constructor) owner of token #1 is RECIPIENT
    assert(erc721.owner_of(token_id) == nft_owner, 'Owner should be RECIPIENT');
    // 3. Transfer token #1 from RECIPIENT to L2TBTC contract
    //    This simulates an NFT accidentally sent to the L2TBTC contract
    start_cheat_caller_address(erc721_contract, nft_owner);
    // Convert the array to a span before passing it
    erc721.transfer_from(nft_owner, contract_address, token_id);
    stop_cheat_caller_address(erc721_contract);

    // Confirm that L2TBTC contract now owns token #1
    assert(erc721.owner_of(token_id) == contract_address, 'NFT should be owned by L2TBTC');

    // 4. Have the owner of L2TBTC recover the NFT to new_recipient (now owner)
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.recover_ERC721(erc721_contract, new_recipient, token_id, array![]);
    stop_cheat_caller_address(contract_address);

    // 5. Check that new_recipient (owner) is now the owner of token #1
    assert(erc721.owner_of(token_id) == new_recipient, 'NFT not correctly recovered');
}

#[test]
fn test_guardian_can_pause() {
    // Setup using the helper function
    let (_, l2tbtc, contract_address, owner) = setup();
    let guardian = contract_address_const::<'GUARDIAN'>();
    // Add guardian
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_guardian(guardian);
    stop_cheat_caller_address(contract_address);
    
    // Guardian pauses the contract
    start_cheat_caller_address(contract_address, guardian);
    l2tbtc.pause();
    stop_cheat_caller_address(contract_address);
    
    // Verify contract is paused
    assert(l2tbtc.is_paused(), 'Contract should be paused');
}

#[test]
#[should_panic(expected: ('Not a guardian',))]
fn test_non_guardian_cannot_pause() {
    // Setup using helper function
    let (_, l2tbtc, contract_address, _) = setup();
    let non_guardian = contract_address_const::<'NON_GUARDIAN'>();
    
    // Non-guardian attempts to pause (should fail)
    start_cheat_caller_address(contract_address, non_guardian);
    l2tbtc.pause();
    stop_cheat_caller_address(contract_address);
}


#[test]
#[should_panic(expected: ('Pausable: paused',))]
fn test_cannot_mint_when_paused() {
    // Setup using helper function
    let (_, l2tbtc, contract_address, owner) = setup();
    let guardian = contract_address_const::<'GUARDIAN'>();
    let minter = contract_address_const::<'MINTER'>();
    let recipient = contract_address_const::<'RECIPIENT'>();
    
    // Add guardian and minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_guardian(guardian);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Guardian pauses the contract
    start_cheat_caller_address(contract_address, guardian);
    l2tbtc.pause();
    stop_cheat_caller_address(contract_address);
    
    // Attempt to mint while paused (should fail)
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(recipient, 1000);
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: ('Pausable: paused',))]
fn test_cannot_burn_when_paused() {
    // Setup using helper function
    let (_, l2tbtc, contract_address, owner) = setup();
    let guardian = contract_address_const::<'GUARDIAN'>();
    let minter = contract_address_const::<'MINTER'>();
    let holder = contract_address_const::<'HOLDER'>();
    
    // Add guardian and minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_guardian(guardian);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Mint tokens to holder
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(holder, 1000);
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
fn test_can_transfer_when_paused() {
    // Setup using helper function
    let guardian = contract_address_const::<'GUARDIAN'>();
    let minter = contract_address_const::<'MINTER'>();
    let sender = contract_address_const::<'SENDER'>();
    let recipient = contract_address_const::<'RECIPIENT'>();
    let (erc20, l2tbtc, contract_address, owner) = setup();
    
    // Add guardian and minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_guardian(guardian);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Mint tokens to sender
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(sender, 1000);
    stop_cheat_caller_address(contract_address);
    
    // Guardian pauses the contract
    start_cheat_caller_address(contract_address, guardian);
    l2tbtc.pause();
    stop_cheat_caller_address(contract_address);
    
    // Transfer should succeed even when paused
    assert(erc20.balance_of(sender) == 1000, 'Wrong sender balance');
    assert(erc20.balance_of(recipient) == 0, 'Wrong recipient balance');
    start_cheat_caller_address(contract_address, sender);
    erc20.transfer(recipient, 500);
    stop_cheat_caller_address(contract_address);
    
    // Verify the transfer was successful
    assert(erc20.balance_of(sender) == 500, 'Wrong sender balance');
    assert(erc20.balance_of(recipient) == 500, 'Wrong recipient balance');
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_unauthorized_unpause() {
    // Setup using helper function
    let (_, l2tbtc, contract_address, owner) = setup();
    let guardian = contract_address_const::<'GUARDIAN'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>();
    
    // Add guardian and pause the contract
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_guardian(guardian);
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
    // Setup using helper function
    let (_, l2tbtc, contract_address, owner) = setup();
    let guardian = contract_address_const::<'GUARDIAN'>();
    
    // Add guardian and pause the contract
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_guardian(guardian);
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
    // Setup using helper function
    let (_, l2tbtc, contract_address, owner) = setup();
    let guardian = contract_address_const::<'GUARDIAN'>();
    
    // Add guardian and pause the contract
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_guardian(guardian);
    stop_cheat_caller_address(contract_address);
    
    start_cheat_caller_address(contract_address, guardian);
    l2tbtc.pause();
    stop_cheat_caller_address(contract_address);
    
    assert(l2tbtc.is_paused(), 'Contract should be paused');
     
    // Owner unpauses the contract
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.unpause();
    stop_cheat_caller_address(contract_address);
    
    // Verify contract is unpaused
    assert(!l2tbtc.is_paused(), 'Contract should be unpaused');
}

#[test]
fn test_functionality_after_unpause() {
    // Setup
    let (erc20, l2tbtc, contract_address, owner) = setup();
    let guardian = contract_address_const::<'GUARDIAN'>();
    let minter = contract_address_const::<'MINTER'>();
    let holder = contract_address_const::<'HOLDER'>();
    let recipient = contract_address_const::<'RECIPIENT'>();
    
    // Add guardian and minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_guardian(guardian);
    l2tbtc.add_minter(minter);
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
    l2tbtc.permissioned_mint(holder, mint_amount);
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
    // Setup using helper function
    let (erc20, l2tbtc, contract_address, owner) = setup();
    let minter = contract_address_const::<'MINTER'>();
    let recipient1 = contract_address_const::<'RECIPIENT1'>();
    let recipient2 = contract_address_const::<'RECIPIENT2'>();
    
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    // First mint to recipient1
    let amount1: u256 = 1000;
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(recipient1, amount1);
    
    // Second mint to recipient1 (same recipient)
    let amount2: u256 = 500;
    l2tbtc.permissioned_mint(recipient1, amount2);
    
    // Third mint to recipient2 (different recipient)
    let amount3: u256 = 750;
    l2tbtc.permissioned_mint(recipient2, amount3);
    stop_cheat_caller_address(contract_address);
    
    // Verify balances
    assert(erc20.balance_of(recipient1) == amount1 + amount2, 'Wrong recipient1 balance');
    assert(erc20.balance_of(recipient2) == amount3, 'Wrong recipient2 balance');
    
    // Verify total supply
    assert(erc20.total_supply() == amount1 + amount2 + amount3, 'Wrong total supply');
}

#[test]
fn test_mint_zero_tokens() {
    // Setup using helper function
    let (erc20, l2tbtc, contract_address, owner) = setup();
    let minter = contract_address_const::<'MINTER'>();
    let recipient = contract_address_const::<'RECIPIENT'>();
    
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Mint zero tokens
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(recipient, 0);
    stop_cheat_caller_address(contract_address);
    
    // Verify balance and total supply remain zero
    assert(erc20.balance_of(recipient) == 0, 'Balance should be zero');
    assert(erc20.total_supply() == 0, 'Supply should be zero');
}

#[test]
fn test_mint_to_self() {
    // Setup using helper function
    let (erc20, l2tbtc, contract_address, owner) = setup();
    let minter = contract_address_const::<'MINTER'>();
    
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Minter mints tokens to itself
    let amount: u256 = 1000;
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(minter, amount);
    stop_cheat_caller_address(contract_address);
    
    // Verify balance and total supply
    assert(erc20.balance_of(minter) == amount, 'Wrong minter balance');
    assert(erc20.total_supply() == amount, 'Wrong total supply');
}

#[test]
fn test_mint_large_amounts() {
    // Setup
    // Setup using helper function
    let (erc20, l2tbtc, contract_address, owner) = setup();
    let minter = contract_address_const::<'MINTER'>();
    let recipient = contract_address_const::<'RECIPIENT'>();
    
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Mint a very large amount (close to u256 max but not exceeding it)
    let large_amount: u256 = 
        340282366920938463463374607431768211455_u256; // 2^128 - 1, half of u256 max
    
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(recipient, large_amount);
    stop_cheat_caller_address(contract_address);
    
    // Verify balance and total supply
    assert(erc20.balance_of(recipient) == large_amount, 'Wrong recipient balance');
    assert(erc20.total_supply() == large_amount, 'Wrong total supply');
    
    // Mint another large amount to test accumulation
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(recipient, large_amount);
    stop_cheat_caller_address(contract_address);
    
    // Verify updated balance and total supply
    assert(erc20.balance_of(recipient) == large_amount * 2, 'Wrong final balance');
    assert(erc20.total_supply() == large_amount * 2, 'Wrong final supply');
}

#[test]
fn test_total_supply_after_multiple_mints() {
    // Setup using helper function
    let (erc20, l2tbtc, contract_address, owner) = setup();
    let minter = contract_address_const::<'MINTER'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    
    // Add minter (equivalent to add_minter in the original test)
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Mint 1 token to third party (equivalent to mint(thirdParty.address, to1e18(1)))
    let one_token: u256 = 1000000000000000000; // 1 token with 18 decimals (1e18)
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(third_party, one_token);
    
    // Mint 3 tokens to token holder (equivalent to mint(tokenHolder.address, to1e18(3)))
    let three_tokens: u256 = 3000000000000000000; // 3 tokens with 18 decimals (3e18)
    l2tbtc.permissioned_mint(token_holder, three_tokens);
    stop_cheat_caller_address(contract_address);
    
    // Check total supply (should be 4 tokens = 4e18)
    let expected_total: u256 = 4000000000000000000; // 4 tokens with 18 decimals
    assert(erc20.total_supply() == expected_total, 'Wrong total supply');
}

#[test]
fn test_balance_of() {
    // Setup using helper function
    let (erc20, l2tbtc, contract_address, owner) = setup();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Mint 7 tokens to token holder (equivalent to 7e18)
    let balance: u256 = 7000000000000000000; // 7 tokens with 18 decimals
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(token_holder, balance);
    stop_cheat_caller_address(contract_address);
    
    // Verify balance
    assert(erc20.balance_of(token_holder) == balance, 'Wrong token balance');
}

#[test]
fn test_transfer() {
    // Setup using helper function
    let (erc20, l2tbtc, contract_address, owner) = setup();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>();
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Initial setup - mint 70 tokens to token holder (70e18)
    let initial_balance: u256 = 70000000000000000000; // 70 tokens with 18 decimals
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(token_holder, initial_balance);
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
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>();
    
    // Deploy contract using setup helper
    let (erc20, l2tbtc, contract_address, owner) = setup();
    
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Initial setup - mint 70 tokens to token holder
    let initial_balance: u256 = 70000000000000000000; // 70e18
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(token_holder, initial_balance);
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
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>();
    
    // Deploy contract using setup helper
    let (erc20, l2tbtc, contract_address, owner) = setup();
    
    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    // Initial setup - mint 70 tokens to token holder (70e18)
    let initial_balance: u256 = 70000000000000000000; // 70 tokens with 18 decimals
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(token_holder, initial_balance);
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
    // Setup using helper function
    let (erc20, _, contract_address, _) = setup();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>();
    
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
    // Setup using helper function
    let (_, l2tbtc, contract_address, owner) = setup();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    let zero_address = contract_address_const::<0>();
    
    // Add minter and mint tokens
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    let initial_amount: u256 = 1000000000000000000; // 1 token
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(token_holder, initial_amount);
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
    // Setup using helper function
    let (_, l2tbtc, contract_address, owner) = setup();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    
    // Add minter and mint tokens
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    let initial_amount: u256 = 1000000000000000000; // 1 token
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(token_holder, initial_amount);
    stop_cheat_caller_address(contract_address);
    
    // Attempt to burn more than balance
    let burn_amount: u256 = 2000000000000000000; // 2 tokens
    start_cheat_caller_address(contract_address, token_holder);
    l2tbtc.burn(burn_amount); // Should panic with underflow
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_burn_zero_tokens() {
    // Setup using helper function
    let (erc20, l2tbtc, contract_address, owner) = setup();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    
    // Add minter and mint tokens
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    let initial_amount: u256 = 1000000000000000000; // 1 token
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(token_holder, initial_amount);
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
    // Setup using helper function
    let (_, l2tbtc, contract_address, owner) = setup();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    let attacker = contract_address_const::<'ATTACKER'>();
    
    // Add minter and mint tokens to token_holder
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    let initial_amount: u256 = 1000000000000000000; // 1 token
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(token_holder, initial_amount);
    stop_cheat_caller_address(contract_address);
    
    // Attempt to burn token_holder's tokens from attacker account
    start_cheat_caller_address(contract_address, attacker);
    l2tbtc.burn(initial_amount); // Should panic due to insufficient balance
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_burn_entire_balance() {
    // Setup using helper function
    let (erc20, l2tbtc, contract_address, owner) = setup();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    
    // Add minter and mint tokens
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    let initial_amount: u256 = 1000000000000000000; // 1 token
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(token_holder, initial_amount);
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
    // Setup using helper function
    let (erc20, l2tbtc, contract_address, owner) = setup();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>();
    let zero_address = contract_address_const::<0>();
    
    // Add minter and mint initial tokens (18 tokens)
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    let initial_balance: u256 = 18000000000000000000; // 18e18
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(token_holder, initial_balance);
    stop_cheat_caller_address(contract_address);
    
    // Approve third party to burn tokens (9 tokens)
    let burn_amount: u256 = 9000000000000000000; // 9e18
    start_cheat_caller_address(contract_address, token_holder);
    erc20.approve(third_party, burn_amount);
    stop_cheat_caller_address(contract_address);
    
    // Setup event spy
    let mut spy = spy_events();
    
    // Execute burn_from
    start_cheat_caller_address(contract_address, third_party);
    l2tbtc.burn_from(token_holder, burn_amount);
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
    // Setup using helper function
    let (_, l2tbtc, contract_address, owner) = setup();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>();
    
    // Add minter and mint tokens
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    let initial_balance: u256 = 18000000000000000000; // 18e18
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(token_holder, initial_balance);
    stop_cheat_caller_address(contract_address);
    
    // Attempt to burn_from without approval
    let burn_amount: u256 = 9000000000000000000; // 9e18
    start_cheat_caller_address(contract_address, third_party);
    l2tbtc.burn_from(token_holder, burn_amount); // Should panic
    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic]
fn test_burn_from_insufficient_balance() {
    // Setup using helper function
    let (erc20, l2tbtc, contract_address, owner) = setup();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    let third_party = contract_address_const::<'THIRD_PARTY'>();
    
    // Add minter and mint small amount of tokens
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);
    
    let initial_balance: u256 = 5000000000000000000; // 5e18
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(token_holder, initial_balance);
    stop_cheat_caller_address(contract_address);
    
    // Approve large amount
    let burn_amount: u256 = 9000000000000000000; // 9e18
    start_cheat_caller_address(contract_address, token_holder);
    erc20.approve(third_party, burn_amount);
    stop_cheat_caller_address(contract_address);
    
    // Attempt to burn more than balance
    start_cheat_caller_address(contract_address, third_party);
    l2tbtc.burn_from(token_holder, burn_amount); // Should panic
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_permissioned_burn() {
    // Setup
    let (erc20, l2tbtc, contract_address, owner) = setup();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    let zero_address = contract_address_const::<0>();

    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);

    // Mint initial tokens to token_holder
    let initial_amount: u256 = 1000;
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(token_holder, initial_amount);
    stop_cheat_caller_address(contract_address);

    // Verify initial state
    assert(erc20.balance_of(token_holder) == initial_amount, 'Initial balance wrong');
    assert(erc20.total_supply() == initial_amount, 'Initial supply wrong');

    // Setup event spy
    let mut spy = spy_events();

    // Burn tokens from token_holder using minter's permission
    let burn_amount: u256 = 400;
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_burn(token_holder, burn_amount);
    stop_cheat_caller_address(contract_address);

    // Verify final state
    let expected_balance = initial_amount - burn_amount;
    assert(erc20.balance_of(token_holder) == expected_balance, 'Final balance wrong');
    assert(erc20.total_supply() == expected_balance, 'Final supply wrong');

    // Verify Transfer event emission (burn is transfer to zero address)
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
#[should_panic(expected: ('Not a minter',))]
fn test_unauthorized_permissioned_burn() {
    // Setup
    let (_, l2tbtc, contract_address, owner) = setup();
    let minter = contract_address_const::<'MINTER'>();
    let token_holder = contract_address_const::<'TOKEN_HOLDER'>();
    let unauthorized = contract_address_const::<'UNAUTHORIZED'>();

    // Add minter
    start_cheat_caller_address(contract_address, owner);
    l2tbtc.add_minter(minter);
    stop_cheat_caller_address(contract_address);

    // Mint initial tokens to token_holder
    let initial_amount: u256 = 1000;
    start_cheat_caller_address(contract_address, minter);
    l2tbtc.permissioned_mint(token_holder, initial_amount);
    stop_cheat_caller_address(contract_address);

    // Attempt permissioned burn from unauthorized account (should fail)
    start_cheat_caller_address(contract_address, unauthorized);
    l2tbtc.permissioned_burn(token_holder, 500);
    stop_cheat_caller_address(contract_address);
}
