use ethers::prelude::*;
use std::time::{SystemTime, UNIX_EPOCH};

/// Generates a cryptograhic signature providng ownership of the session.
/// This runs on the AGENT 

pub async fn sign_request(
    privat_key: &str,
    session_id: &str,
) -> Result<(String, u64), Box<dyn std::error::Error>> {

    // Init the agent wallet
    let wallet: LocalWallet = private_key.parse()?;

    // time bound payload to prevent replay attacks
    let timestamp = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs();

    // Construct the message
    let message = format!("{}:{}", session_id, timestamp);

    // sign the message
    let signature = wallet.sign_message(message).await?;

    // return the string of the signature and timestamp used
    Ok((signature.to_string(), timestamp))
}
