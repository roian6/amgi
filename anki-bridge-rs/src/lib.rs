//! C ABI bridge for the Anki Rust backend.
//!
//! Exposes functions matching the pattern used by AnkiDroid's JNI bridge,
//! adapted for C ABI (Swift interop via XCFramework).

use std::os::raw::c_int;
use std::slice;

use anki::backend::{init_backend, Backend};

mod aux;

/// Create a new Anki backend instance.
///
/// # Safety
/// - `init_data` must point to a valid buffer of `init_len` bytes containing
///   a serialized `BackendInit` protobuf message (or be null for defaults).
/// - `out_ptr` must point to writable memory for a single i64.
///
/// Returns 0 on success, -1 on error.
#[no_mangle]
pub unsafe extern "C" fn anki_open_backend(
    init_data: *const u8,
    init_len: usize,
    out_ptr: *mut i64,
) -> c_int {
    let init_bytes: &[u8] = if init_data.is_null() || init_len == 0 {
        // Empty init → default BackendInit (empty preferred_langs, server=false)
        b""
    } else {
        unsafe { slice::from_raw_parts(init_data, init_len) }
    };

    // If empty bytes, encode a default BackendInit
    let effective_bytes: Vec<u8>;
    let bytes_to_use = if init_bytes.is_empty() {
        use prost::Message;
        let default_init = anki_proto::backend::BackendInit::default();
        effective_bytes = default_init.encode_to_vec();
        &effective_bytes
    } else {
        init_bytes
    };

    match init_backend(bytes_to_use) {
        Ok(backend) => {
            let boxed = Box::new(backend);
            let ptr = Box::into_raw(boxed) as i64;
            unsafe { *out_ptr = ptr };
            0
        }
        Err(_e) => -1,
    }
}

/// Execute a backend RPC method via protobuf.
///
/// # Safety
/// - `backend_ptr` must be a valid pointer returned by `anki_open_backend`.
/// - `input_data`/`input_len` must describe a valid protobuf request.
/// - `out_data`/`out_len` receive the response (caller frees with `anki_free_response`).
///
/// Returns 0 on success (out_data has the response protobuf),
///         1 on backend error (out_data has the error protobuf),
///        -1 on FFI error.
#[no_mangle]
pub unsafe extern "C" fn anki_run_method(
    backend_ptr: i64,
    service: u32,
    method: u32,
    input_data: *const u8,
    input_len: usize,
    out_data: *mut *mut u8,
    out_len: *mut usize,
) -> c_int {
    let backend = unsafe { &*(backend_ptr as *const Backend) };

    let input = if input_data.is_null() || input_len == 0 {
        &[]
    } else {
        unsafe { slice::from_raw_parts(input_data, input_len) }
    };

    if service == aux::SERVICE {
        return match aux::dispatch(backend, method, input) {
            Ok(output) => {
                set_output(output, out_data, out_len);
                0
            }
            Err(err_bytes) => {
                set_output(err_bytes, out_data, out_len);
                1
            }
        };
    }

    match backend.run_service_method(service, method, input) {
        Ok(output) => {
            set_output(output, out_data, out_len);
            0 // success
        }
        Err(err_bytes) => {
            set_output(err_bytes, out_data, out_len);
            1 // backend error (response contains error protobuf)
        }
    }
}

/// Free a response buffer allocated by `anki_run_method`.
#[no_mangle]
pub unsafe extern "C" fn anki_free_response(data: *mut u8, len: usize) {
    if !data.is_null() && len > 0 {
        let _ = unsafe { Vec::from_raw_parts(data, len, len) };
    }
}

/// Close and destroy the backend instance.
#[no_mangle]
pub unsafe extern "C" fn anki_close_backend(backend_ptr: i64) {
    if backend_ptr != 0 {
        let _ = unsafe { Box::from_raw(backend_ptr as *mut Backend) };
    }
}

/// Complete a watchOS URLSession request without re-entering the backend RPC.
///
/// # Safety
/// Each non-null pointer must describe a readable buffer of its matching
/// length for the duration of this call. Null is valid only for absent or
/// empty buffers.
#[cfg(target_os = "watchos")]
#[no_mangle]
pub unsafe extern "C" fn anki_http_complete(
    request_id: u64,
    status_code: u16,
    original_size: i64,
    location_data: *const u8,
    location_len: usize,
    body_data: *const u8,
    body_len: usize,
    error_data: *const u8,
    error_len: usize,
) -> c_int {
    let location = match optional_ffi_bytes(location_data, location_len) {
        Ok(bytes) => bytes,
        Err(()) => return -1,
    };
    let body = match ffi_bytes(body_data, body_len) {
        Ok(bytes) => bytes.to_vec(),
        Err(()) => return -1,
    };
    let native_error = match optional_ffi_bytes(error_data, error_len) {
        Ok(bytes) => bytes,
        Err(()) => return -1,
    };
    i32::from(anki::sync::http_client::complete_request(
        request_id,
        status_code,
        original_size,
        location,
        body,
        native_error,
    ))
}

// -- Helpers --

unsafe fn set_output(data: Vec<u8>, out_data: *mut *mut u8, out_len: *mut usize) {
    let len = data.len();
    if len > 0 {
        let mut boxed = data.into_boxed_slice();
        let ptr = boxed.as_mut_ptr();
        std::mem::forget(boxed);
        unsafe {
            *out_data = ptr;
            *out_len = len;
        }
    } else {
        unsafe {
            *out_data = std::ptr::null_mut();
            *out_len = 0;
        }
    }
}

#[cfg(target_os = "watchos")]
fn ffi_bytes<'a>(data: *const u8, len: usize) -> Result<&'a [u8], ()> {
    if len == 0 {
        return Ok(&[]);
    }
    if data.is_null() {
        return Err(());
    }
    // SAFETY: Category 8 (FFI boundary). The exported function's contract
    // requires a readable buffer of exactly `len` bytes, and null was rejected.
    Ok(unsafe { slice::from_raw_parts(data, len) })
}

#[cfg(target_os = "watchos")]
fn optional_ffi_bytes<'a>(data: *const u8, len: usize) -> Result<Option<&'a [u8]>, ()> {
    if data.is_null() {
        return if len == 0 { Ok(None) } else { Err(()) };
    }
    ffi_bytes(data, len).map(Some)
}
