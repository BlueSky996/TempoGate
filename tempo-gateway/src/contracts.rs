use ethers::prelude::*;
use std::sync::Arc;
use std::convert::TryFrom;

// Generate type safe rust binding for the escrow contract
abigen!(
    Escrow,
    r#"[
        function sessions(bytes32) external view returns (address user, address provider, uint256 allocatedAmount, uint256 spentAmount, bool isActive)
        function settle(bytes32 _sessionId, uint256 _amount) external
    ]"#

);

// define a custom type for our authenticated client
pub type EscrowClient = Escrow<SignerMiddleware<Provider<Http>, LocalWallet>>;

// init the contract instance with a signing wallet
pub async fn init_escrow_client(
    rpc_url: &str,
    private_key: &str,
    contract_address: &str,
    chain_id: u64
) -> EscrowClient {
    // steup the http provider
    let provider = Provider::<Http>::try_from(rpc_url).expect("invalid rpc url");

    // setup the wallet for signing transactions 
    let wallet: LocalWallet = private_key.parse::<LocalWallet>()
        .expect("Invalid private key")
        .with_chain_id(chain_id);

        // combine them into a signerMiddleware
        let client = Arc::new(SignerMiddleware::new(provider, wallet));

        // Prase the contract Address
        let address = contract_address.parse::<Address>().expect("Invalid Contract Address");

        // return the executable contract instance
        Escrow::new(address, client)
}

