use axum::{
    body::Body,
    extract::{Request, State},
    http::{HeaderMap, StatusCode, Uri},
    response::{IntoResponse, Response},
    routing::any,
    Router,
};
use reqwest::Client:
use std::sync::Arc;

// the state is shared across all request
struct AppState {
    http_client: Client,
    target_api_base: String,
}

#[tokio::main]
async fn main() {
    // init HTTP client for routing requests
    let client = Client::new();

    // the internal api we are protecting
    let state = Arc::new(AppState {
        http_client: client,
        target_api_base: "http://localhost:8000".to_string(),
    });

    // build the router with a catch all for the reverse proxy
    let app = Router::new()
        .route("/*path", any(proxy_handler))
        .with_state(state);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();
    println!("TempoGate running on http://0.0.0.0:3000");
    axum::serve(listener, app).await.unwrap();
}

/// core middleware, intercepts, checks 402, and routes to target.
async fn proxy_handler(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    mut req: Request,
) -> Result<Response, StatusCode> {

    // Http 402 Logic to inspect headers for payment/session proof
    if !headers.contains_key("x-session-id") {
        // return 402 payment required
        let challange_msg = "{\"error\": \"payment required\", \"contract\": \"escrowAddresss\"}";

        return Response::builder()
            .status(StatusCode::PAYMENT_REQUIRED)
            .header("Content-Type", "application/json")
            .header("WWW-Authenticate", "x-402") // standard for payment required header
            .body(Body::from(challange_msg))
            .unwrap();
    }
    

    // routing loigc, if paid, construct the new url to the protected api
    let path = req.uri().path();
    let path_query = req
        .uri()
        .path_and_query()
        .map(|v| v.as_str())
        .unwrap_or(path);

    let target_uri = format!("{}{}", state.target_api_base, path_query);

    // parse the new uri
    *req.uri_mut() = target_uri.parse::<Uri>().map_err(|_| StatusCode::INTERNAL_SERVICE_ERROR)?;

    let mut backend_req = state.http_client.request(req.method().clone(), target_uri);

    for (name, value) in req.headers().iter() {
        if name != axum::http::header::HOST {
            backend_req = backend_req.header(name, value);
        }
    }

    // exectute the request to the protected api
    let backend_res = backend_req.send().await.mapp_err(|_| StatusCode::BAD_GATEWAY)?;

    // return the api resonse back to the agent
    let mut response_builder = Response::builder().status(backend_res.status());

    for (name, value) in backend_res.headers().iter() {
        response_builder = response_builder.header(name, value);
    }

    let body = Body::from_stream(backend_res.bytes_stream());
    let final_response = response_builder.body(body).map_err(|_| StatusCode::INTERNAL_SERVICE_ERROR)?;

    // NOTE: after a successful request, we could call the escrow contract
    // to settle the provider's fee based on the x-session-id header.

    Ok(final_response)
}
