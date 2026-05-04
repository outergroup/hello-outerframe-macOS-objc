#import "OuterframeHost.h"
#import "OuterframeSocket.h"

#include <stdlib.h>
#include <string.h>
#include <uuid/uuid.h>

typedef struct {
    OFUUID callback_id;
    OFUUID browser_callback_id;
    bool registered;
    OFHostDisplayLinkCallback callback;
    void *context;
} OFDisplayLinkEntry;

typedef struct {
    OFUUID request_id;
    OFHostImageCallback callback;
    void *context;
} OFImageRequestEntry;

struct OFHost {
    OFContentSocket *socket;
    OFHostCallbacks callbacks;
    void *context;
    char *url;
    char *bundle_url;
    OFDisplayLinkEntry *display_links;
    size_t display_link_count;
    size_t display_link_capacity;
    OFImageRequestEntry *image_requests;
    size_t image_request_count;
    size_t image_request_capacity;
};

static bool OFUUIDEqual(OFUUID a, OFUUID b) {
    return memcmp(a.bytes, b.bytes, sizeof(a.bytes)) == 0;
}

static OFUUID OFUUIDCreate(void) {
    OFUUID uuid = {0};
    uuid_generate_random(uuid.bytes);
    return uuid;
}

static char *OFStringViewCopyCString(OFStringView view) {
    char *copy = calloc(view.length + 1, 1);
    if (!copy) return NULL;
    if (view.length > 0 && view.bytes) {
        memcpy(copy, view.bytes, view.length);
    }
    return copy;
}

static bool OFHostReserveDisplayLinks(OFHost *host, size_t additional) {
    if (additional > SIZE_MAX - host->display_link_count) return false;
    size_t needed = host->display_link_count + additional;
    if (needed <= host->display_link_capacity) return true;
    size_t capacity = host->display_link_capacity ? host->display_link_capacity * 2 : 4;
    if (capacity < needed) capacity = needed;
    OFDisplayLinkEntry *entries = realloc(host->display_links, capacity * sizeof(*entries));
    if (!entries) return false;
    host->display_links = entries;
    host->display_link_capacity = capacity;
    return true;
}

static bool OFHostReserveImageRequests(OFHost *host, size_t additional) {
    if (additional > SIZE_MAX - host->image_request_count) return false;
    size_t needed = host->image_request_count + additional;
    if (needed <= host->image_request_capacity) return true;
    size_t capacity = host->image_request_capacity ? host->image_request_capacity * 2 : 4;
    if (capacity < needed) capacity = needed;
    OFImageRequestEntry *entries = realloc(host->image_requests, capacity * sizeof(*entries));
    if (!entries) return false;
    host->image_requests = entries;
    host->image_request_capacity = capacity;
    return true;
}

static OFDisplayLinkEntry *OFHostFindDisplayLink(OFHost *host, OFUUID callback_id) {
    for (size_t i = 0; i < host->display_link_count; i++) {
        if (OFUUIDEqual(host->display_links[i].callback_id, callback_id)) {
            return &host->display_links[i];
        }
    }
    return NULL;
}

static void OFHostRemoveDisplayLinkAtIndex(OFHost *host, size_t index) {
    if (index >= host->display_link_count) return;
    if (index + 1 < host->display_link_count) {
        memmove(&host->display_links[index], &host->display_links[index + 1], (host->display_link_count - index - 1) * sizeof(host->display_links[0]));
    }
    host->display_link_count--;
}

static void OFHostRemoveImageRequestAtIndex(OFHost *host, size_t index) {
    if (index >= host->image_request_count) return;
    if (index + 1 < host->image_request_count) {
        memmove(&host->image_requests[index], &host->image_requests[index + 1], (host->image_request_count - index - 1) * sizeof(host->image_requests[0]));
    }
    host->image_request_count--;
}

static void OFHostSendBuffer(OFHost *host, OFBuffer *buffer) {
    if (!host || !host->socket || !buffer || !buffer->bytes) return;
    OFContentSocketSend(host->socket, buffer->bytes, buffer->length);
    OFBufferFree(buffer);
}

static void OFHostHandleDisplayLinkRegistered(OFHost *host, OFUUID callback_id, OFUUID browser_callback_id) {
    OFDisplayLinkEntry *entry = OFHostFindDisplayLink(host, callback_id);
    if (!entry) return;
    entry->browser_callback_id = browser_callback_id;
    entry->registered = true;
}

static void OFHostHandleDisplayLinkFired(OFHost *host, double target_timestamp) {
    for (size_t i = 0; i < host->display_link_count; i++) {
        OFDisplayLinkEntry *entry = &host->display_links[i];
        if (entry->registered && entry->callback) {
            entry->callback(host, target_timestamp, entry->context);
        }
    }
}

static void OFHostHandleImageResponse(OFHost *host, const OFBrowserMessage *message) {
    OFUUID request_id = message->as.image_response.request_id;
    for (size_t i = 0; i < host->image_request_count; i++) {
        OFImageRequestEntry entry = host->image_requests[i];
        if (!OFUUIDEqual(entry.request_id, request_id)) continue;

        OFHostRemoveImageRequestAtIndex(host, i);
        if (entry.callback) {
            OFDataView image = message->as.image_response.has_image_data ? message->as.image_response.image_data : (OFDataView){0};
            entry.callback(host, image, message->as.image_response.width, message->as.image_response.height, entry.context);
        }
        return;
    }
}

static void OFHostHandleAccessibilitySnapshotRequest(OFHost *host, OFUUID request_id) {
    OFBuffer snapshot = {0};
    bool has_snapshot = false;
    if (host->callbacks.accessibility_snapshot) {
        has_snapshot = host->callbacks.accessibility_snapshot(host, &snapshot, host->context);
    }
    if (!has_snapshot) {
        has_snapshot = OFAccessibilityNotImplementedSnapshot("Accessibility not implemented", &snapshot);
    }

    OFBuffer frame = {0};
    if (OFEncodeAccessibilitySnapshotResponse(request_id, snapshot.bytes, snapshot.length, &frame)) {
        OFHostSendBuffer(host, &frame);
    }
    OFBufferFree(&snapshot);
}

static void OFHostSocketMessage(OFContentSocket *socket, uint16_t type, const uint8_t *payload, size_t payload_length, void *context) {
    (void)socket;
    OFHost *host = context;
    OFBrowserMessage message;
    if (!OFBrowserMessageDecode(type, payload, payload_length, &message)) {
        return;
    }

    switch (message.kind) {
        case OFBrowserMessageDisplayLinkFired:
            OFHostHandleDisplayLinkFired(host, message.as.display_link_fired.target_timestamp);
            break;
        case OFBrowserMessageDisplayLinkCallbackRegistered:
            OFHostHandleDisplayLinkRegistered(host, message.as.display_link_callback_registered.callback_id, message.as.display_link_callback_registered.browser_callback_id);
            break;
        case OFBrowserMessageImageWithSystemSymbolName:
            OFHostHandleImageResponse(host, &message);
            break;
        case OFBrowserMessageAccessibilitySnapshotRequest:
            OFHostHandleAccessibilitySnapshotRequest(host, message.as.request.request_id);
            break;
        default:
            if (host->callbacks.message) {
                host->callbacks.message(host, &message, host->context);
            }
            break;
    }

    OFBrowserMessageFree(&message);
}

static void OFHostSocketClosed(OFContentSocket *socket, void *context) {
    (void)socket;
    OFHost *host = context;
    if (host->callbacks.disconnected) {
        host->callbacks.disconnected(host, host->context);
    }
}

OFHost *OFHostCreate(int32_t socket_fd, OFHostCallbacks callbacks, void *context) {
    OFHost *host = calloc(1, sizeof(*host));
    if (!host) return NULL;

    host->callbacks = callbacks;
    host->context = context;
    OFContentSocketCallbacks socket_callbacks = {
        .message = OFHostSocketMessage,
        .closed = OFHostSocketClosed,
    };
    host->socket = OFContentSocketCreate(socket_fd, socket_callbacks, host);
    if (!host->socket) {
        OFHostDestroy(host);
        return NULL;
    }
    return host;
}

void OFHostDestroy(OFHost *host) {
    if (!host) return;
    if (host->socket) {
        OFContentSocketDestroy(host->socket);
        host->socket = NULL;
    }
    free(host->url);
    free(host->bundle_url);
    free(host->display_links);
    free(host->image_requests);
    free(host);
}

void OFHostConfigureFromInitialize(OFHost *host, const OFInitializeContent *initialize) {
    if (!host || !initialize) return;
    free(host->url);
    free(host->bundle_url);
    host->url = initialize->has_url ? OFStringViewCopyCString(initialize->url) : NULL;
    host->bundle_url = initialize->has_bundle_url ? OFStringViewCopyCString(initialize->bundle_url) : NULL;
}

const char *OFHostURL(OFHost *host) {
    return host ? host->url : NULL;
}

const char *OFHostBundleURL(OFHost *host) {
    return host ? host->bundle_url : NULL;
}

void OFHostSetCursor(OFHost *host, OFCursorType cursor_type) {
    if (!host) return;
    OFBuffer frame = {0};
    if (OFEncodeCursorUpdate(cursor_type, &frame)) {
        OFHostSendBuffer(host, &frame);
    }
}

void OFHostSetInputMode(OFHost *host, OFContentInputMode input_mode) {
    if (!host) return;
    OFBuffer frame = {0};
    if (OFEncodeInputModeUpdate(input_mode, &frame)) {
        OFHostSendBuffer(host, &frame);
    }
}

void OFHostUpdatePageMetadata(OFHost *host, const char *title_or_null, const uint8_t *icon_png_or_null, size_t icon_png_length, uint32_t icon_width, uint32_t icon_height) {
    if (!host) return;
    OFBuffer frame = {0};
    if (OFEncodePageMetadata(false, title_or_null, icon_png_or_null, icon_png_length, icon_width, icon_height, &frame)) {
        OFHostSendBuffer(host, &frame);
    }
}

void OFHostUpdateStartPageMetadata(OFHost *host, const char *title_or_null, const uint8_t *icon_png_or_null, size_t icon_png_length, uint32_t icon_width, uint32_t icon_height) {
    if (!host) return;
    OFBuffer frame = {0};
    if (OFEncodePageMetadata(true, title_or_null, icon_png_or_null, icon_png_length, icon_width, icon_height, &frame)) {
        OFHostSendBuffer(host, &frame);
    }
}

void OFHostShowContextMenu(OFHost *host, OFDataView attributed_text_rtf, float location_x, float location_y) {
    if (!host) return;
    OFBuffer frame = {0};
    if (OFEncodeShowContextMenu(attributed_text_rtf, location_x, location_y, &frame)) {
        OFHostSendBuffer(host, &frame);
    }
}

void OFHostShowDefinition(OFHost *host, OFDataView attributed_text_rtf, float location_x, float location_y) {
    if (!host) return;
    OFBuffer frame = {0};
    if (OFEncodeShowDefinition(attributed_text_rtf, location_x, location_y, &frame)) {
        OFHostSendBuffer(host, &frame);
    }
}

void OFHostSendAccessibilityTreeChanged(OFHost *host, OFAccessibilityNotification notification_mask) {
    if (!host) return;
    OFBuffer frame = {0};
    if (OFEncodeAccessibilityTreeChanged(notification_mask, &frame)) {
        OFHostSendBuffer(host, &frame);
    }
}

void OFHostPerformHapticFeedback(OFHost *host, OFHapticFeedbackStyle style) {
    if (!host) return;
    OFBuffer frame = {0};
    if (OFEncodeHapticFeedback(style, &frame)) {
        OFHostSendBuffer(host, &frame);
    }
}

OFUUID OFHostRegisterDisplayLinkCallback(OFHost *host, OFHostDisplayLinkCallback callback, void *context) {
    OFUUID callback_id = {0};
    if (!host || !callback || !OFHostReserveDisplayLinks(host, 1)) return callback_id;

    callback_id = OFUUIDCreate();
    host->display_links[host->display_link_count++] = (OFDisplayLinkEntry){
        .callback_id = callback_id,
        .callback = callback,
        .context = context,
    };

    OFBuffer frame = {0};
    if (OFEncodeStartDisplayLink(callback_id, &frame)) {
        OFHostSendBuffer(host, &frame);
    }
    return callback_id;
}

void OFHostStopDisplayLinkCallback(OFHost *host, OFUUID callback_id) {
    if (!host) return;

    for (size_t i = 0; i < host->display_link_count; i++) {
        OFDisplayLinkEntry entry = host->display_links[i];
        if (!OFUUIDEqual(entry.callback_id, callback_id)) continue;

        if (entry.registered) {
            OFBuffer frame = {0};
            if (OFEncodeStopDisplayLink(entry.browser_callback_id, &frame)) {
                OFHostSendBuffer(host, &frame);
            }
        }
        OFHostRemoveDisplayLinkAtIndex(host, i);
        return;
    }
}

OFUUID OFHostRequestSystemSymbolImage(OFHost *host, const char *symbol_name, float point_size, const char *weight, float scale, float tint_red, float tint_green, float tint_blue, float tint_alpha, OFHostImageCallback callback, void *context) {
    OFUUID request_id = {0};
    if (!host || !symbol_name || !weight || !callback || !OFHostReserveImageRequests(host, 1)) return request_id;

    request_id = OFUUIDCreate();
    host->image_requests[host->image_request_count++] = (OFImageRequestEntry){
        .request_id = request_id,
        .callback = callback,
        .context = context,
    };

    OFBuffer frame = {0};
    if (OFEncodeGetImageWithSystemSymbolName(request_id, symbol_name, point_size, weight, scale, tint_red, tint_green, tint_blue, tint_alpha, &frame)) {
        OFHostSendBuffer(host, &frame);
    }
    return request_id;
}
