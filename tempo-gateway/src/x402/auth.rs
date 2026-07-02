use ethers::prelude::*;
use std::str::FromStr;

pub fn recover_signer(
    session_id: &str,
    timestamp: u64,
    signature_hex: &str,
) -> Result<Address, Box<dyn std::error::Error>> {

    // reconstruct the exact message the agent signed
    let message = format!("{}:{}", session_id, timestamp);

    // Parse the signature from hex
    let signature = Signature::from_str(signature_hex)?;

    // Recover the public address that signed this message
    let recovered_address = signature.recover(message)?;

    Ok(recovered_address)
}

/// verifies that recoverd address matches the session owner and 
pub fn verify_payment_auth(
    session_id: &str,
    timestamp: u64,
    signature_hex: &str,
    expected_user_address: Address, 
) -> bool {

    // Check for replay attacks
    let current_time = std::time::SystemTime::now()
    .duration_since(std::time::UNIX_EPOCH)
    .unwrap()
    .as_secs();

    if current_time > timestamp + 60 {
        println!("Verification failed: Signature expired.");
        return false;
    }

    // Recover the address
    let recovered_address = match recover_signer(session_id, timestamp, signature_hex) {
        Ok(addr) => addr,
        Err(_) => return false,
    };

    // verify it matches the owner of the funded session
    recovered_address == expected_user_address
}