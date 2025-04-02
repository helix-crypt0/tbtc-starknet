// src/tests/mocks/RecipientMock.cairo (or similar path)
#[starknet::contract]
mod RecipientMock {
    use starknet::ContractAddress;
    use openzeppelin::token::erc721::interface::IERC721Receiver;

    #[storage]
    struct Storage {}

    #[external(v0)]
    impl ERC721ReceiverImpl of IERC721Receiver<ContractState> {
        fn on_erc721_received(
            self: @ContractState,
            operator: ContractAddress,
            from: ContractAddress,
            token_id: u256,
            data: Span<felt252>
        ) -> felt252 {
            // Simply return the magic value to indicate successful receipt
            // You could add storage vars here to track received tokens for more complex tests
            let result =IERC721Receiver::on_erc721_received(self, operator, from, token_id, data);
            result
        }
    }
}
