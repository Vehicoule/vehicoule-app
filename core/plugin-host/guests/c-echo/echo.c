// Mirrors `get` of the Rust `probe` guest (../probe/src/lib.rs): GET the query URL and return
// the HTTP status as the title of the only track found. Proof that a non-Rust
// language binds the same WIT world (task 4, contract WIT 1.0).
#include "test_search.h"
#include <stdio.h>
#include <stdlib.h>

bool exports_vehicoule_music_search_search(
    exports_vehicoule_music_search_search_request_t *req,
    exports_vehicoule_music_search_search_results_t *ret,
    exports_vehicoule_music_search_error_t *err) {
  vehicoule_host_http_request_t http_req = {
      .method = VEHICOULE_HOST_HTTP_METHOD_GET,
      .url = req->query,
      .headers = {.ptr = NULL, .len = 0},
      .body = {.is_some = false},
  };
  vehicoule_host_http_response_t resp;
  vehicoule_host_http_http_error_t http_err;
  if (!vehicoule_host_http_send(&http_req, &resp, &http_err)) {
    // Keep it minimal: every http-error case becomes `internal`, same as the brief
    // allows. The core only needs a typed error to move on to the next plugin.
    err->tag = VEHICOULE_MUSIC_TYPES_ERROR_INTERNAL;
    test_search_string_dup(&err->val.internal, "http error");
    return false;
  }

  char status[8];
  snprintf(status, sizeof(status), "%u", (unsigned)resp.status);

  exports_vehicoule_music_search_track_t *track = calloc(1, sizeof(*track));
  test_search_string_dup(&track->id, "");
  test_search_string_dup(&track->title, status);
  // artists, album, duration_ms, isrc, explicit_, artwork: zeroed by calloc, i.e.
  // empty/None/false, same as the Rust guests' shared `found()` helper.

  ret->tracks = (exports_vehicoule_music_search_list_track_t){.ptr = track, .len = 1};
  ret->albums = (exports_vehicoule_music_search_list_album_t){.ptr = NULL, .len = 0};
  ret->artists = (exports_vehicoule_music_search_list_artist_t){.ptr = NULL, .len = 0};
  ret->playlists = (exports_vehicoule_music_search_list_playlist_t){.ptr = NULL, .len = 0};
  ret->next = (test_search_option_string_t){.is_some = false};
  return true;
}
