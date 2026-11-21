use axum::http::{HeaderValue, Method, header};
use std::{net::SocketAddr, sync::Arc};
use tower_http::cors::CorsLayer;
use xiaobao_backend::{AppState, app, domain::school_today, provider::DemoProvider};

// One async runtime thread: no worker pool or background polling for this prototype.
#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let address: SocketAddr = std::env::var("XIAOBAO_ADDR")
        .unwrap_or_else(|_| "127.0.0.1:3001".into())
        .parse()?;
    let database = std::env::var_os("XIAOBAO_SESSION_DB")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| ".xiaobao/sessions.sqlite3".into());
    let mut router = app(AppState::with_session_db(
        Arc::new(DemoProvider::with_hs_calendar(school_today())?),
        &database,
    )?);
    if let Ok(origin) = std::env::var("XIAOBAO_WEB_ORIGIN") {
        router = router.layer(
            CorsLayer::new()
                .allow_origin(origin.parse::<HeaderValue>()?)
                .allow_methods([Method::GET, Method::POST, Method::DELETE])
                .allow_headers([
                    header::AUTHORIZATION,
                    header::CONTENT_TYPE,
                    header::IF_NONE_MATCH,
                ])
                .expose_headers([header::ETAG, header::CACHE_CONTROL]),
        );
    }
    let listener = tokio::net::TcpListener::bind(address).await?;
    eprintln!(
        "Xiaobao demo API: http://{} (synthetic student data)",
        listener.local_addr()?
    );
    axum::serve(listener, router)
        .with_graceful_shutdown(shutdown())
        .await?;
    Ok(())
}

async fn shutdown() {
    #[cfg(unix)]
    {
        match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
            Ok(mut terminate) => {
                tokio::select! { _ = tokio::signal::ctrl_c() => {}, _ = terminate.recv() => {} }
            }
            Err(_) => {
                let _ = tokio::signal::ctrl_c().await;
            }
        }
    }
    #[cfg(not(unix))]
    {
        let _ = tokio::signal::ctrl_c().await;
    }
}
