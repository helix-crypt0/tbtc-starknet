use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, 
    start_cheat_caller_address, stop_cheat_caller_address};

use starknet::{ContractAddress, contract_address_const};

// Import openzeppelin traits for the components used in L2TBTC
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin::security::pausable::PausableComponent::{PausableImpl};



#[starknet::interface]
trait IL2TBTC<TContractState> {
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
    fn burn(ref self: TContractState, value: u256);
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
    fn add_minter(ref self: TContractState, minter: ContractAddress);
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
    l2tbtc.add_minter(user1);
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



