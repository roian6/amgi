#ifndef ANKI_BRIDGE_H
#define ANKI_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

/**
 * Create a new Anki backend instance.
 *
 * @param init_data  Pointer to serialized BackendInit protobuf bytes (may be NULL for defaults).
 * @param init_len   Length of init_data in bytes.
 * @param out_ptr    On success, receives an opaque backend pointer (as int64_t).
 * @return 0 on success, -1 on error.
 */
int anki_open_backend(const uint8_t *init_data, size_t init_len, int64_t *out_ptr);

/**
 * Execute a backend RPC method.
 *
 * @param backend_ptr  Opaque pointer from anki_open_backend.
 * @param service      Protobuf service ID.
 * @param method       Protobuf method ID within the service.
 * @param input_data   Serialized protobuf request bytes.
 * @param input_len    Length of input_data.
 * @param out_data     On success, receives a pointer to the response bytes (heap-allocated).
 * @param out_len      On success, receives the length of out_data.
 * @return 0 on success, -1 on error.
 */
int anki_run_method(
    int64_t backend_ptr,
    uint32_t service,
    uint32_t method,
    const uint8_t *input_data,
    size_t input_len,
    uint8_t **out_data,
    size_t *out_len
);

/**
 * Free a response buffer returned by anki_run_method.
 *
 * @param data  Pointer from out_data (may be NULL).
 * @param len   Length from out_len.
 */
void anki_free_response(uint8_t *data, size_t len);

/**
 * Close and destroy the backend instance.
 *
 * @param backend_ptr  Opaque pointer from anki_open_backend. Invalid after this call.
 */
void anki_close_backend(int64_t backend_ptr);

/**
 * Complete a watchOS URLSession request started by the Rust sync transport.
 * Returns 1 when delivered, 0 when the request was already cancelled or
 * completed, and -1 when a pointer/length pair is invalid.
 */
int anki_http_complete(
    uint64_t request_id,
    uint16_t status_code,
    int64_t original_size,
    const uint8_t *location_data,
    size_t location_len,
    const uint8_t *body_data,
    size_t body_len,
    const uint8_t *error_data,
    size_t error_len
);

#endif /* ANKI_BRIDGE_H */
