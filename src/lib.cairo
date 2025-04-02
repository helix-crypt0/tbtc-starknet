mod contracts {
    pub mod L2TBTC;
}

mod tests {
    mod unit {
        #[cfg(test)]
        mod test_l2tbtc;

    }
    mod mocks {
        mod erc721_mock;
        pub mod erc20_mock;
        mod recipient_mock;
    }
}
