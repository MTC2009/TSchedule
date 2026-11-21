use crate::{AppState, auth::Session, domain::school_today};
use axum::{
    extract::{FromRequestParts, Request, State},
    http::{HeaderValue, Method, StatusCode, header},
    middleware::Next,
    response::{IntoResponse, Response},
};
use hmac::{Hmac, Mac};
use sha2::Sha256;

pub(crate) async fn conditional(
    State(state): State<AppState>,
    request: Request,
    next: Next,
) -> Response {
    if request.method() != Method::GET {
        return next.run(request).await;
    }
    let (mut parts, body) = request.into_parts();
    let session = match Session::from_request_parts(&mut parts, &state).await {
        Ok(session) => session,
        Err(error) => return error.into_response(),
    };
    let Some(revision) = state.provider.cache_revision(&session.subject) else {
        parts.extensions.insert(session);
        return next.run(Request::from_parts(parts, body)).await;
    };
    // An exact tag can only have been issued after a successful read of this query.
    let mut hash =
        Hmac::<Sha256>::new_from_slice(state.validator_key.as_bytes()).expect("HMAC key");
    let day = match parts.uri.path() {
        "/api/v1/schedule" | "/api/v1/calendar" => school_today().to_string(),
        _ => String::new(),
    };
    for field in [
        revision,
        &session.subject,
        &day,
        parts.uri.path_and_query().map_or("/", |p| p.as_str()),
    ] {
        hash.update(&(field.len() as u64).to_be_bytes());
        hash.update(field.as_bytes());
    }
    let opaque = format!("\"{:x}\"", hash.finalize().into_bytes());
    let mut matched = false;
    let mut wildcard = false;
    for value in parts
        .headers
        .get_all(header::IF_NONE_MATCH)
        .iter()
        .filter_map(|v| v.to_str().ok())
    {
        for candidate in value.split(',').map(str::trim) {
            matched |= candidate.strip_prefix("W/").unwrap_or(candidate) == opaque;
            wildcard |= candidate == "*";
        }
    }
    let ttl = if parts.uri.path() == "/api/v1/courses" {
        "private, max-age=86400"
    } else {
        "private, max-age=300"
    };
    let mut response = if matched {
        StatusCode::NOT_MODIFIED.into_response()
    } else {
        parts.extensions.insert(session);
        let response = next.run(Request::from_parts(parts, body)).await;
        if response.status() != StatusCode::OK {
            return response;
        }
        if wildcard {
            StatusCode::NOT_MODIFIED.into_response()
        } else {
            response
        }
    };
    response.headers_mut().insert(
        header::ETAG,
        HeaderValue::from_str(&format!("W/{opaque}")).expect("hex ETag"),
    );
    response
        .headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static(ttl));
    response
        .headers_mut()
        .append(header::VARY, HeaderValue::from_static("Authorization"));
    response
}
