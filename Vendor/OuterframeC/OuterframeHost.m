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
    OFHostMessageCallback message_callback;
    void *message_context;
    OFHostDisconnectCallback disconnected_callback;
    void *disconnected_context;
    char *url;
    char *bundle_url;
    OFUUID current_history_entry_id;
    uint32_t history_length;
    bool can_go_back;
    bool can_go_forward;
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

static void OFHostSetURLFromStringView(OFHost *host, OFStringView url) {
    if (!host) return;
    free(host->url);
    host->url = OFStringViewCopyCString(url);
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
            OFDataView alpha_mask = message->as.image_response.has_alpha_mask_data ? message->as.image_response.alpha_mask_data : (OFDataView){0};
            entry.callback(host, alpha_mask, message->as.image_response.width, message->as.image_response.height, message->as.image_response.bytes_per_row, entry.context);
        }
        return;
    }
}

static void OFHostSocketMessage(OFContentSocket *socket, const uint8_t *message_data, size_t message_length, void *context) {
    (void)socket;
    OFHost *host = context;
    OFBrowserMessage message;
    if (!OFBrowserMessageDecode(message_data, message_length, &message)) {
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
        case OFBrowserMessageHistoryEntryAccepted:
        case OFBrowserMessageHistoryTraversal:
            host->current_history_entry_id = message.as.history.entry_id;
            OFHostSetURLFromStringView(host, message.as.history.url);
            if (host->message_callback) {
                host->message_callback(host, &message, host->message_context);
            }
            break;
        case OFBrowserMessageHistoryContextUpdate:
            host->current_history_entry_id = message.as.history.entry_id;
            OFHostSetURLFromStringView(host, message.as.history.url);
            host->history_length = message.as.history.length;
            host->can_go_back = message.as.history.can_go_back;
            host->can_go_forward = message.as.history.can_go_forward;
            if (host->message_callback) {
                host->message_callback(host, &message, host->message_context);
            }
            break;
        default:
            if (host->message_callback) {
                host->message_callback(host, &message, host->message_context);
            }
            break;
    }

    OFBrowserMessageFree(&message);
}

static void OFHostSocketClosed(OFContentSocket *socket, void *context) {
    (void)socket;
    OFHost *host = context;
    if (host->disconnected_callback) {
        host->disconnected_callback(host, host->disconnected_context);
    }
}

OFHost *OFHostCreate(int32_t socket_fd, OFHostCallbacks callbacks, void *context) {
    OFHost *host = calloc(1, sizeof(*host));
    if (!host) return NULL;

    host->message_callback = callbacks.message;
    host->message_context = context;
    host->disconnected_callback = callbacks.disconnected;
    host->disconnected_context = context;
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

void OFHostSetMessageCallback(OFHost *host, OFHostMessageCallback callback, void *context) {
    if (!host) return;
    host->message_callback = callback;
    host->message_context = context;
}

void OFHostConfigureFromInitialize(OFHost *host, const OFInitializeContent *initialize) {
    if (!host || !initialize) return;
    free(host->url);
    free(host->bundle_url);
    host->url = initialize->has_url ? OFStringViewCopyCString(initialize->url) : NULL;
    host->bundle_url = initialize->has_bundle_url ? OFStringViewCopyCString(initialize->bundle_url) : NULL;
    host->current_history_entry_id = initialize->has_history_entry_id ? initialize->history_entry_id : (OFUUID){0};
}

const char *OFHostURL(OFHost *host) {
    return host ? host->url : NULL;
}

const char *OFHostBundleURL(OFHost *host) {
    return host ? host->bundle_url : NULL;
}

OFUUID OFHostCurrentHistoryEntryID(OFHost *host) {
    return host ? host->current_history_entry_id : (OFUUID){0};
}

uint32_t OFHostHistoryLength(OFHost *host) {
    return host ? host->history_length : 0;
}

bool OFHostCanGoBackInHistory(OFHost *host) {
    return host ? host->can_go_back : false;
}

bool OFHostCanGoForwardInHistory(OFHost *host) {
    return host ? host->can_go_forward : false;
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

void OFHostShowContextMenu(OFHost *host, OFDataView attributed_text_rtf, double location_x, double location_y) {
    if (!host) return;
    OFBuffer frame = {0};
    if (OFEncodeShowContextMenu(attributed_text_rtf, location_x, location_y, &frame)) {
        OFHostSendBuffer(host, &frame);
    }
}

void OFHostShowDefinition(OFHost *host, OFDataView attributed_text_rtf, double location_x, double location_y) {
    if (!host) return;
    OFBuffer frame = {0};
    if (OFEncodeShowDefinition(attributed_text_rtf, location_x, location_y, &frame)) {
        OFHostSendBuffer(host, &frame);
    }
}

void OFHostSetPasteboardCapabilities(OFHost *host, bool can_copy, bool can_cut, const char *const *pasteboard_types, size_t type_count) {
    if (!host) return;
    OFStringView *views = NULL;
    if (type_count > 0) {
        views = calloc(type_count, sizeof(*views));
        if (!views) return;
        for (size_t i = 0; i < type_count; i++) {
            const char *type = pasteboard_types[i] ?: "";
            views[i] = (OFStringView){ .bytes = type, .length = strlen(type) };
        }
    }

    OFBuffer frame = {0};
    if (OFEncodePasteboardCapabilities(can_copy, can_cut, views, type_count, &frame)) {
        OFHostSendBuffer(host, &frame);
    }
    free(views);
}

void OFHostSendCopySelectedPasteboardResponse(OFHost *host, OFUUID request_id, const OFPasteboardItemView *items, size_t item_count) {
    if (!host) return;
    OFBuffer frame = {0};
    if (OFEncodeCopySelectedPasteboardResponse(request_id, items, item_count, &frame)) {
        OFHostSendBuffer(host, &frame);
    }
}

void OFHostSendAccessibilitySnapshotResponse(OFHost *host, OFUUID request_id, const uint8_t *snapshot_or_null, size_t snapshot_length) {
    if (!host) return;
    OFBuffer frame = {0};
    if (OFEncodeAccessibilitySnapshotResponse(request_id, snapshot_or_null, snapshot_length, &frame)) {
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

OFUUID OFHostPushHistoryEntry(OFHost *host, const char *url_or_null) {
    OFUUID entry_id = {0};
    if (!host) return entry_id;
    entry_id = OFUUIDCreate();
    OFBuffer frame = {0};
    if (OFEncodeHistoryEntry(OFContentMessageHistoryPushEntry, entry_id, url_or_null, &frame)) {
        OFHostSendBuffer(host, &frame);
    }
    return entry_id;
}

OFUUID OFHostReplaceHistoryEntry(OFHost *host, const char *url_or_null) {
    OFUUID entry_id = {0};
    if (!host) return entry_id;
    entry_id = OFUUIDCreate();
    OFBuffer frame = {0};
    if (OFEncodeHistoryEntry(OFContentMessageHistoryReplaceEntry, entry_id, url_or_null, &frame)) {
        OFHostSendBuffer(host, &frame);
    }
    return entry_id;
}

void OFHostGoInHistory(OFHost *host, int32_t delta) {
    if (!host) return;
    OFBuffer frame = {0};
    if (OFEncodeHistoryGo(delta, &frame)) {
        OFHostSendBuffer(host, &frame);
    }
}

void OFHostGoBackInHistory(OFHost *host) {
    OFHostGoInHistory(host, -1);
}

void OFHostGoForwardInHistory(OFHost *host) {
    OFHostGoInHistory(host, 1);
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

OFUUID OFHostRequestSystemSymbolImage(OFHost *host, const char *symbol_name, double point_size, double weight, double scale, OFHostImageCallback callback, void *context) {
    OFUUID request_id = {0};
    if (!host || !symbol_name || !callback || !OFHostReserveImageRequests(host, 1)) return request_id;

    request_id = OFUUIDCreate();
    host->image_requests[host->image_request_count++] = (OFImageRequestEntry){
        .request_id = request_id,
        .callback = callback,
        .context = context,
    };

    OFBuffer frame = {0};
    if (OFEncodeGetImageWithSystemSymbolName(request_id, symbol_name, point_size, weight, scale, &frame)) {
        OFHostSendBuffer(host, &frame);
    }
    return request_id;
}
