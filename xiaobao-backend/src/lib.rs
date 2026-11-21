mod api;
mod attendance;
mod auth;
mod cache;
mod devices;
pub mod domain;
pub mod grade_sync;
pub mod offline;
pub mod provider;
mod work;

use axum::{
    Router,
    extract::DefaultBodyLimit,
    http::{HeaderValue, StatusCode, header},
    routing::{delete, get, post},
};
use provider::SchoolProvider;
use std::{sync::Arc, time::Duration};
use tower_http::set_header::SetResponseHeaderLayer;

#[derive(Clone)]
pub struct AppState {
    provider: Arc<dyn SchoolProvider>,
    sessions: Arc<auth::Sessions>,
    devices: devices::Devices,
    validator_key: uuid::Uuid,
}

impl AppState {
    pub fn new(provider: Arc<dyn SchoolProvider>) -> Self {
        Self::with_devices(provider, devices::Devices::memory())
    }
    pub fn with_session_db(
        provider: Arc<dyn SchoolProvider>,
        path: &std::path::Path,
    ) -> Result<Self, Box<dyn std::error::Error>> {
        let devices = devices::Devices::open(path, provider.source())?;
        Ok(Self::with_devices(provider, devices))
    }
    fn with_devices(provider: Arc<dyn SchoolProvider>, devices: devices::Devices) -> Self {
        Self {
            provider,
            devices,
            validator_key: uuid::Uuid::new_v4(),
            sessions: Arc::new(auth::Sessions::new(Duration::from_secs(8 * 3600), 128)),
        }
    }
}

pub fn app(state: AppState) -> Router {
    let reads = Router::new()
        .route("/api/v1/courses", get(api::courses))
        .route("/api/v1/schedule", get(api::schedule))
        .route("/api/v1/calendar", get(api::calendar))
        .route("/api/v1/grades", get(api::grades))
        .route("/api/v1/attendance", get(attendance::read))
        .route("/api/v1/work", get(work::list))
        .route("/api/v1/work/{id}", get(work::detail))
        .route("/api/v1/work-statistics", get(work::statistics))
        .route("/api/v1/resources", get(api::resources))
        .route("/api/v1/resources/{id}", get(api::resource_detail))
        .route_layer(axum::middleware::from_fn_with_state(
            state.clone(),
            cache::conditional,
        ));
    reads
        .route(
            "/health",
            get(|| async { axum::Json(serde_json::json!({"status":"ok"})) }),
        )
        .route("/api/v1/demo/profiles", get(api::profiles))
        .route("/api/v1/demo/sessions", post(api::create_session))
        .route("/api/v1/session", delete(api::logout))
        .route("/api/v1/session/refresh", post(api::refresh_session))
        .route("/api/v1/me", get(api::me))
        .route("/api/v1/offline/versions", get(offline::versions))
        .route("/api/v1/offline/data", post(offline::download))
        .route("/api/v1/grades/sync", post(api::sync_grades))
        .route("/api/v1/grades/project-score", post(api::project_score))
        .fallback(|| async { api::ApiError::not_found() })
        .method_not_allowed_fallback(|| async {
            api::ApiError::new(
                StatusCode::METHOD_NOT_ALLOWED,
                "method_not_allowed",
                "Method not allowed",
            )
        })
        .layer(DefaultBodyLimit::max(8 * 1024))
        .layer(SetResponseHeaderLayer::if_not_present(
            header::CACHE_CONTROL,
            HeaderValue::from_static("no-store"),
        ))
        .with_state(state)
}
