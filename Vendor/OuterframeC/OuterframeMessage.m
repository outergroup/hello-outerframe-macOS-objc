#import "OuterframeMessage.h"

#include <stdlib.h>
#include <string.h>

typedef struct {
    const uint8_t *bytes;
    size_t length;
    size_t offset;
} OFCursor;

typedef struct {
    uint8_t *bytes;
    size_t length;
    size_t capacity;
} OFByteWriter;

static bool OFReadBytes(OFCursor *cursor, size_t length, const uint8_t **bytes) {
    if (cursor->offset + length > cursor->length) {
        return false;
    }
    *bytes = cursor->bytes + cursor->offset;
    cursor->offset += length;
    return true;
}

static bool OFReadU8(OFCursor *cursor, uint8_t *value) {
    const uint8_t *bytes = NULL;
    if (!OFReadBytes(cursor, 1, &bytes)) return false;
    *value = bytes[0];
    return true;
}

static bool OFReadU16(OFCursor *cursor, uint16_t *value) {
    const uint8_t *bytes = NULL;
    if (!OFReadBytes(cursor, 2, &bytes)) return false;
    *value = OFReadUInt16LE(bytes);
    return true;
}

static bool OFReadU32(OFCursor *cursor, uint32_t *value) {
    const uint8_t *bytes = NULL;
    if (!OFReadBytes(cursor, 4, &bytes)) return false;
    *value = OFReadUInt32LE(bytes);
    return true;
}

static bool OFReadU64(OFCursor *cursor, uint64_t *value) {
    const uint8_t *bytes = NULL;
    if (!OFReadBytes(cursor, 8, &bytes)) return false;
    *value = ((uint64_t)bytes[0]) |
             ((uint64_t)bytes[1] << 8) |
             ((uint64_t)bytes[2] << 16) |
             ((uint64_t)bytes[3] << 24) |
             ((uint64_t)bytes[4] << 32) |
             ((uint64_t)bytes[5] << 40) |
             ((uint64_t)bytes[6] << 48) |
             ((uint64_t)bytes[7] << 56);
    return true;
}

static bool OFReadF32(OFCursor *cursor, float *value) {
    uint32_t bits = 0;
    if (!OFReadU32(cursor, &bits)) return false;
    memcpy(value, &bits, sizeof(*value));
    return true;
}

static bool OFReadF64(OFCursor *cursor, double *value) {
    uint64_t bits = 0;
    if (!OFReadU64(cursor, &bits)) return false;
    memcpy(value, &bits, sizeof(*value));
    return true;
}

static bool OFReadData32(OFCursor *cursor, OFDataView *view) {
    uint32_t length = 0;
    const uint8_t *bytes = NULL;
    if (!OFReadU32(cursor, &length) || !OFReadBytes(cursor, length, &bytes)) return false;
    view->bytes = bytes;
    view->length = length;
    return true;
}

static bool OFReadString32(OFCursor *cursor, OFStringView *view) {
    OFDataView data = {0};
    if (!OFReadData32(cursor, &data)) return false;
    view->bytes = (const char *)data.bytes;
    view->length = data.length;
    return true;
}

static bool OFReadUUID(OFCursor *cursor, OFUUID *uuid) {
    const uint8_t *bytes = NULL;
    if (!OFReadBytes(cursor, sizeof(uuid->bytes), &bytes)) return false;
    memcpy(uuid->bytes, bytes, sizeof(uuid->bytes));
    return true;
}

static bool OFWriterReserve(OFByteWriter *writer, size_t additional) {
    if (additional > SIZE_MAX - writer->length) return false;
    size_t needed = writer->length + additional;
    if (needed <= writer->capacity) return true;
    size_t capacity = writer->capacity ? writer->capacity : 64;
    while (capacity < needed) {
        if (capacity > SIZE_MAX / 2) {
            capacity = needed;
            break;
        }
        capacity *= 2;
    }
    uint8_t *bytes = realloc(writer->bytes, capacity);
    if (!bytes) return false;
    writer->bytes = bytes;
    writer->capacity = capacity;
    return true;
}

static bool OFWriteBytes(OFByteWriter *writer, const void *bytes, size_t length) {
    if (!OFWriterReserve(writer, length)) return false;
    memcpy(writer->bytes + writer->length, bytes, length);
    writer->length += length;
    return true;
}

static bool OFWriteU8(OFByteWriter *writer, uint8_t value) {
    return OFWriteBytes(writer, &value, sizeof(value));
}

static bool OFWriteU16(OFByteWriter *writer, uint16_t value) {
    uint8_t bytes[2] = { (uint8_t)(value & 0xff), (uint8_t)((value >> 8) & 0xff) };
    return OFWriteBytes(writer, bytes, sizeof(bytes));
}

static bool OFWriteU32(OFByteWriter *writer, uint32_t value) {
    uint8_t bytes[4] = {
        (uint8_t)(value & 0xff),
        (uint8_t)((value >> 8) & 0xff),
        (uint8_t)((value >> 16) & 0xff),
        (uint8_t)((value >> 24) & 0xff),
    };
    return OFWriteBytes(writer, bytes, sizeof(bytes));
}

static bool OFWriteF32(OFByteWriter *writer, float value) {
    uint32_t bits = 0;
    memcpy(&bits, &value, sizeof(bits));
    return OFWriteU32(writer, bits);
}

static bool OFWriteData32(OFByteWriter *writer, const uint8_t *bytes, size_t length) {
    if (length > UINT32_MAX) return false;
    return OFWriteU32(writer, (uint32_t)length) && OFWriteBytes(writer, bytes, length);
}

static bool OFWriteCString32(OFByteWriter *writer, const char *string) {
    return OFWriteData32(writer, (const uint8_t *)string, string ? strlen(string) : 0);
}

static bool OFWriteStringView32(OFByteWriter *writer, OFStringView string) {
    return OFWriteData32(writer, (const uint8_t *)string.bytes, string.length);
}

static bool OFWriteUUID(OFByteWriter *writer, OFUUID uuid) {
    return OFWriteBytes(writer, uuid.bytes, sizeof(uuid.bytes));
}

static OFBuffer OFWriterTakeBuffer(OFByteWriter *writer) {
    OFBuffer buffer = { writer->bytes, writer->length };
    writer->bytes = NULL;
    writer->length = 0;
    writer->capacity = 0;
    return buffer;
}

static void OFWriterFree(OFByteWriter *writer) {
    free(writer->bytes);
    writer->bytes = NULL;
    writer->length = 0;
    writer->capacity = 0;
}

static bool OFDecodeInitialize(OFCursor *cursor, OFInitializeContent *initialize) {
    uint16_t arg_count = 0;
    if (!OFReadU16(cursor, &arg_count)) return false;

    OFStringView proxy_username = {0};
    OFStringView proxy_password = {0};
    bool has_proxy_username = false;
    bool has_proxy_password = false;

    for (uint16_t i = 0; i < arg_count; i++) {
        uint8_t kind = 0;
        OFDataView arg_data = {0};
        if (!OFReadU8(cursor, &kind) || !OFReadData32(cursor, &arg_data)) return false;

        OFCursor arg = { arg_data.bytes, arg_data.length, 0 };
        switch (kind) {
            case OFInitArgKindData:
                initialize->has_data = OFReadData32(&arg, &initialize->data);
                if (!initialize->has_data) return false;
                break;
            case OFInitArgKindContentSize:
                if (!OFReadF64(&arg, &initialize->content_width) || !OFReadF64(&arg, &initialize->content_height)) return false;
                initialize->has_content_size = true;
                break;
            case OFInitArgKindAppearance:
                if (!OFReadData32(&arg, &initialize->appearance_archive)) return false;
                initialize->has_appearance_archive = true;
                break;
            case OFInitArgKindProxy:
                if (!OFReadString32(&arg, &initialize->proxy.host) || !OFReadU16(&arg, &initialize->proxy.port)) return false;
                initialize->proxy.present = true;
                initialize->proxy.has_username = has_proxy_username;
                initialize->proxy.username = proxy_username;
                initialize->proxy.has_password = has_proxy_password;
                initialize->proxy.password = proxy_password;
                break;
            case OFInitArgKindProxyAuth: {
                uint8_t has = 0;
                if (!OFReadU8(&arg, &has)) return false;
                has_proxy_username = has != 0;
                if (has_proxy_username && !OFReadString32(&arg, &proxy_username)) return false;
                if (!OFReadU8(&arg, &has)) return false;
                has_proxy_password = has != 0;
                if (has_proxy_password && !OFReadString32(&arg, &proxy_password)) return false;
                initialize->proxy.has_username = has_proxy_username;
                initialize->proxy.username = proxy_username;
                initialize->proxy.has_password = has_proxy_password;
                initialize->proxy.password = proxy_password;
                break;
            }
            case OFInitArgKindURL:
                if (!OFReadString32(&arg, &initialize->url)) return false;
                initialize->has_url = true;
                break;
            case OFInitArgKindBundleURL:
                if (!OFReadString32(&arg, &initialize->bundle_url)) return false;
                initialize->has_bundle_url = true;
                break;
            case OFInitArgKindWindowIsActive: {
                uint8_t raw = 0;
                if (!OFReadU8(&arg, &raw)) return false;
                initialize->window_is_active = raw != 0;
                initialize->has_window_is_active = true;
                break;
            }
            default:
                break;
        }
    }
    return true;
}

static bool OFDecodePasteboardItems(OFCursor *cursor, OFPasteboardItemView **items, size_t *count) {
    uint16_t raw_count = 0;
    if (!OFReadU16(cursor, &raw_count)) return false;
    OFPasteboardItemView *parsed = NULL;
    if (raw_count > 0) {
        parsed = calloc(raw_count, sizeof(*parsed));
        if (!parsed) return false;
    }
    for (uint16_t i = 0; i < raw_count; i++) {
        if (!OFReadString32(cursor, &parsed[i].type_identifier) || !OFReadData32(cursor, &parsed[i].data)) {
            free(parsed);
            return false;
        }
    }
    *items = parsed;
    *count = raw_count;
    return true;
}

bool OFBrowserMessageDecode(uint16_t type, const uint8_t *payload, size_t payload_length, OFBrowserMessage *out_message) {
    if (!out_message) return false;
    memset(out_message, 0, sizeof(*out_message));
    out_message->kind = type;
    OFCursor cursor = { payload, payload_length, 0 };

    switch (type) {
        case OFBrowserMessageInitializeContent:
            return OFDecodeInitialize(&cursor, &out_message->as.initialize);
        case OFBrowserMessageDisplayLinkFired:
            return OFReadU64(&cursor, &out_message->as.display_link_fired.frame_number) &&
                   OFReadF64(&cursor, &out_message->as.display_link_fired.target_timestamp);
        case OFBrowserMessageDisplayLinkCallbackRegistered:
            return OFReadUUID(&cursor, &out_message->as.display_link_callback_registered.callback_id) &&
                   OFReadUUID(&cursor, &out_message->as.display_link_callback_registered.browser_callback_id);
        case OFBrowserMessageResizeContent:
            return OFReadF64(&cursor, &out_message->as.resize.width) &&
                   OFReadF64(&cursor, &out_message->as.resize.height);
        case OFBrowserMessageMouseEvent:
            return OFReadU8(&cursor, &out_message->as.mouse.kind) &&
                   OFReadF32(&cursor, &out_message->as.mouse.x) &&
                   OFReadF32(&cursor, &out_message->as.mouse.y) &&
                   OFReadU64(&cursor, &out_message->as.mouse.modifier_flags) &&
                   OFReadU32(&cursor, &out_message->as.mouse.click_count);
        case OFBrowserMessageScrollWheelEvent: {
            uint8_t is_momentum = 0;
            uint8_t is_precise = 0;
            bool ok = OFReadF32(&cursor, &out_message->as.scroll.x) &&
                      OFReadF32(&cursor, &out_message->as.scroll.y) &&
                      OFReadF32(&cursor, &out_message->as.scroll.delta_x) &&
                      OFReadF32(&cursor, &out_message->as.scroll.delta_y) &&
                      OFReadU64(&cursor, &out_message->as.scroll.modifier_flags) &&
                      OFReadU32(&cursor, &out_message->as.scroll.phase) &&
                      OFReadU32(&cursor, &out_message->as.scroll.momentum_phase) &&
                      OFReadU8(&cursor, &is_momentum) &&
                      OFReadU8(&cursor, &is_precise);
            out_message->as.scroll.is_momentum = is_momentum != 0;
            out_message->as.scroll.is_precise = is_precise != 0;
            return ok;
        }
        case OFBrowserMessageKeyDown:
        case OFBrowserMessageKeyUp: {
            uint8_t repeat = 0;
            bool ok = OFReadU16(&cursor, &out_message->as.key.key_code) &&
                      OFReadString32(&cursor, &out_message->as.key.characters) &&
                      OFReadString32(&cursor, &out_message->as.key.characters_ignoring_modifiers) &&
                      OFReadU64(&cursor, &out_message->as.key.modifier_flags) &&
                      OFReadU8(&cursor, &repeat);
            out_message->as.key.is_repeat = repeat != 0;
            return ok;
        }
        case OFBrowserMessageMagnification:
        case OFBrowserMessageMagnificationEnded:
            return OFReadU32(&cursor, &out_message->as.magnification.surface_id) &&
                   OFReadF32(&cursor, &out_message->as.magnification.magnification) &&
                   OFReadF32(&cursor, &out_message->as.magnification.x) &&
                   OFReadF32(&cursor, &out_message->as.magnification.y) &&
                   OFReadF32(&cursor, &out_message->as.magnification.scroll_x) &&
                   OFReadF32(&cursor, &out_message->as.magnification.scroll_y);
        case OFBrowserMessageQuickLook:
            return OFReadF32(&cursor, &out_message->as.point.x) &&
                   OFReadF32(&cursor, &out_message->as.point.y);
        case OFBrowserMessageImageWithSystemSymbolName: {
            uint8_t success = 0, has_image = 0, has_error = 0;
            if (!OFReadUUID(&cursor, &out_message->as.image_response.request_id) ||
                !OFReadU32(&cursor, &out_message->as.image_response.width) ||
                !OFReadU32(&cursor, &out_message->as.image_response.height) ||
                !OFReadU8(&cursor, &success) ||
                !OFReadU8(&cursor, &has_image)) return false;
            out_message->as.image_response.success = success != 0;
            out_message->as.image_response.has_image_data = has_image != 0;
            if (has_image && !OFReadData32(&cursor, &out_message->as.image_response.image_data)) return false;
            if (!OFReadU8(&cursor, &has_error)) return false;
            out_message->as.image_response.has_error_message = has_error != 0;
            return !has_error || OFReadString32(&cursor, &out_message->as.image_response.error_message);
        }
        case OFBrowserMessageTextInput: {
            uint8_t has_range = 0;
            bool ok = OFReadString32(&cursor, &out_message->as.text_input.text) &&
                      OFReadU8(&cursor, &has_range) &&
                      OFReadU64(&cursor, &out_message->as.text_input.replacement_location) &&
                      OFReadU64(&cursor, &out_message->as.text_input.replacement_length);
            out_message->as.text_input.has_replacement_range = has_range != 0;
            return ok;
        }
        case OFBrowserMessageSetMarkedText: {
            uint8_t has_range = 0;
            bool ok = OFReadString32(&cursor, &out_message->as.marked_text.text) &&
                      OFReadU64(&cursor, &out_message->as.marked_text.selected_location) &&
                      OFReadU64(&cursor, &out_message->as.marked_text.selected_length) &&
                      OFReadU8(&cursor, &has_range) &&
                      OFReadU64(&cursor, &out_message->as.marked_text.replacement_location) &&
                      OFReadU64(&cursor, &out_message->as.marked_text.replacement_length);
            out_message->as.marked_text.has_replacement_range = has_range != 0;
            return ok;
        }
        case OFBrowserMessageUnmarkText:
        case OFBrowserMessageShutdown:
            return true;
        case OFBrowserMessageTextInputFocus: {
            uint8_t has_focus = 0;
            bool ok = OFReadString32(&cursor, &out_message->as.text_focus.field_id) && OFReadU8(&cursor, &has_focus);
            out_message->as.text_focus.has_focus = has_focus != 0;
            return ok;
        }
        case OFBrowserMessageTextCommand:
            return OFReadString32(&cursor, &out_message->as.text_command.command);
        case OFBrowserMessageSetCursorPosition: {
            uint8_t modify = 0;
            bool ok = OFReadString32(&cursor, &out_message->as.cursor_position.field_id) &&
                      OFReadU64(&cursor, &out_message->as.cursor_position.position) &&
                      OFReadU8(&cursor, &modify);
            out_message->as.cursor_position.modify_selection = modify != 0;
            return ok;
        }
        case OFBrowserMessageSystemAppearanceUpdate:
            return OFReadData32(&cursor, &out_message->as.appearance.appearance_archive);
        case OFBrowserMessageWindowActiveUpdate:
        case OFBrowserMessageViewFocusChanged: {
            uint8_t raw = 0;
            bool ok = OFReadU8(&cursor, &raw);
            out_message->as.boolean_update.value = raw != 0;
            return ok;
        }
        case OFBrowserMessageCopySelectedPasteboardRequest:
        case OFBrowserMessageAccessibilitySnapshotRequest:
            return OFReadUUID(&cursor, &out_message->as.request.request_id);
        case OFBrowserMessagePasteboardContentDelivered:
            return OFDecodePasteboardItems(&cursor, &out_message->as.pasteboard.items, &out_message->as.pasteboard.count);
        default:
            return false;
    }
}

void OFBrowserMessageFree(OFBrowserMessage *message) {
    if (!message) return;
    if (message->kind == OFBrowserMessagePasteboardContentDelivered) {
        free(message->as.pasteboard.items);
    }
    memset(message, 0, sizeof(*message));
}

bool OFEncodeFrame(uint16_t type, OFDataView payload, OFBuffer *out_frame) {
    if (payload.length > UINT32_MAX) return false;
    OFByteWriter writer = {0};
    bool ok = OFWriteU16(&writer, type) &&
              OFWriteU32(&writer, (uint32_t)payload.length) &&
              OFWriteBytes(&writer, payload.bytes, payload.length);
    if (!ok) {
        OFWriterFree(&writer);
        return false;
    }
    *out_frame = OFWriterTakeBuffer(&writer);
    return true;
}

static bool OFFinishPayload(uint16_t type, OFByteWriter *payload, OFBuffer *out_frame) {
    OFDataView view = { payload->bytes, payload->length };
    bool ok = OFEncodeFrame(type, view, out_frame);
    OFWriterFree(payload);
    return ok;
}

bool OFEncodeCursorUpdate(OFCursorType cursor_type, OFBuffer *out_frame) {
    OFByteWriter payload = {0};
    if (!OFWriteU8(&payload, cursor_type)) return false;
    return OFFinishPayload(OFContentMessageCursorUpdate, &payload, out_frame);
}

bool OFEncodeInputModeUpdate(OFContentInputMode input_mode, OFBuffer *out_frame) {
    OFByteWriter payload = {0};
    if (!OFWriteU8(&payload, input_mode)) return false;
    return OFFinishPayload(OFContentMessageInputModeUpdate, &payload, out_frame);
}

static bool OFEncodeAttributedTextAction(uint16_t type, OFDataView attributed_text_rtf, float location_x, float location_y, OFBuffer *out_frame) {
    OFByteWriter payload = {0};
    bool ok = OFWriteF32(&payload, location_x) &&
              OFWriteF32(&payload, location_y) &&
              OFWriteData32(&payload, attributed_text_rtf.bytes, attributed_text_rtf.length);
    if (!ok) {
        OFWriterFree(&payload);
        return false;
    }
    return OFFinishPayload(type, &payload, out_frame);
}

bool OFEncodeShowContextMenu(OFDataView attributed_text_rtf, float location_x, float location_y, OFBuffer *out_frame) {
    return OFEncodeAttributedTextAction(OFContentMessageShowContextMenu, attributed_text_rtf, location_x, location_y, out_frame);
}

bool OFEncodeShowDefinition(OFDataView attributed_text_rtf, float location_x, float location_y, OFBuffer *out_frame) {
    return OFEncodeAttributedTextAction(OFContentMessageShowDefinition, attributed_text_rtf, location_x, location_y, out_frame);
}

bool OFEncodeGetImageWithSystemSymbolName(OFUUID request_id, const char *symbol_name, float point_size, const char *weight, float scale, float tint_red, float tint_green, float tint_blue, float tint_alpha, OFBuffer *out_frame) {
    OFByteWriter payload = {0};
    bool ok = OFWriteUUID(&payload, request_id) &&
              OFWriteCString32(&payload, symbol_name) &&
              OFWriteF32(&payload, point_size) &&
              OFWriteCString32(&payload, weight) &&
              OFWriteF32(&payload, scale) &&
              OFWriteF32(&payload, tint_red) &&
              OFWriteF32(&payload, tint_green) &&
              OFWriteF32(&payload, tint_blue) &&
              OFWriteF32(&payload, tint_alpha);
    if (!ok) {
        OFWriterFree(&payload);
        return false;
    }
    return OFFinishPayload(OFContentMessageGetImageWithSystemSymbolName, &payload, out_frame);
}

bool OFEncodePageMetadata(bool start_page, const char *title_or_null, const uint8_t *icon_png_or_null, size_t icon_png_length, uint32_t icon_width, uint32_t icon_height, OFBuffer *out_frame) {
    OFByteWriter payload = {0};
    bool ok = true;
    if (title_or_null) {
        ok = ok && OFWriteU8(&payload, 1) && OFWriteCString32(&payload, title_or_null);
    } else {
        ok = ok && OFWriteU8(&payload, 0);
    }
    if (icon_png_or_null) {
        ok = ok && OFWriteU8(&payload, 1) &&
             OFWriteU32(&payload, icon_width) &&
             OFWriteU32(&payload, icon_height) &&
             OFWriteData32(&payload, icon_png_or_null, icon_png_length);
    } else {
        ok = ok && OFWriteU8(&payload, 0);
    }
    if (!ok) {
        OFWriterFree(&payload);
        return false;
    }
    return OFFinishPayload(start_page ? OFContentMessageStartPageMetadataUpdate : OFContentMessagePageMetadataUpdate, &payload, out_frame);
}

bool OFEncodeAccessibilitySnapshotResponse(OFUUID request_id, const uint8_t *snapshot_or_null, size_t snapshot_length, OFBuffer *out_frame) {
    OFByteWriter payload = {0};
    bool ok = OFWriteUUID(&payload, request_id);
    if (snapshot_or_null) {
        ok = ok && OFWriteU8(&payload, 1) && OFWriteData32(&payload, snapshot_or_null, snapshot_length);
    } else {
        ok = ok && OFWriteU8(&payload, 0);
    }
    if (!ok) {
        OFWriterFree(&payload);
        return false;
    }
    return OFFinishPayload(OFContentMessageAccessibilitySnapshotResponse, &payload, out_frame);
}

bool OFEncodeAccessibilityTreeChanged(uint8_t notification_mask, OFBuffer *out_frame) {
    OFByteWriter payload = {0};
    if (!OFWriteU8(&payload, notification_mask)) return false;
    return OFFinishPayload(OFContentMessageAccessibilityTreeChanged, &payload, out_frame);
}

bool OFEncodeHapticFeedback(OFHapticFeedbackStyle style, OFBuffer *out_frame) {
    OFByteWriter payload = {0};
    if (!OFWriteU8(&payload, style)) return false;
    return OFFinishPayload(OFContentMessageHapticFeedback, &payload, out_frame);
}

bool OFEncodeStartDisplayLink(OFUUID callback_id, OFBuffer *out_frame) {
    OFByteWriter payload = {0};
    if (!OFWriteUUID(&payload, callback_id)) return false;
    return OFFinishPayload(OFContentMessageStartDisplayLink, &payload, out_frame);
}

bool OFEncodeStopDisplayLink(OFUUID browser_callback_id, OFBuffer *out_frame) {
    OFByteWriter payload = {0};
    if (!OFWriteUUID(&payload, browser_callback_id)) return false;
    return OFFinishPayload(OFContentMessageStopDisplayLink, &payload, out_frame);
}

bool OFEncodeCopySelectedPasteboardResponse(OFUUID request_id, const OFPasteboardItemView *items, size_t item_count, OFBuffer *out_frame) {
    if (item_count > UINT16_MAX) item_count = UINT16_MAX;
    OFByteWriter payload = {0};
    bool ok = OFWriteUUID(&payload, request_id) && OFWriteU16(&payload, (uint16_t)item_count);
    for (size_t i = 0; ok && i < item_count; i++) {
        ok = OFWriteStringView32(&payload, items[i].type_identifier) &&
             OFWriteData32(&payload, items[i].data.bytes, items[i].data.length);
    }
    if (!ok) {
        OFWriterFree(&payload);
        return false;
    }
    return OFFinishPayload(OFContentMessageCopySelectedPasteboardResponse, &payload, out_frame);
}

bool OFEncodePasteboardCapabilities(bool can_copy, bool can_cut, const OFStringView *pasteboard_types, size_t type_count, OFBuffer *out_frame) {
    if (type_count > UINT16_MAX) type_count = UINT16_MAX;
    OFByteWriter payload = {0};
    bool ok = OFWriteU8(&payload, can_copy ? 1 : 0) &&
              OFWriteU8(&payload, can_cut ? 1 : 0) &&
              OFWriteU16(&payload, (uint16_t)type_count);
    for (size_t i = 0; ok && i < type_count; i++) {
        ok = OFWriteStringView32(&payload, pasteboard_types[i]);
    }
    if (!ok) {
        OFWriterFree(&payload);
        return false;
    }
    return OFFinishPayload(OFContentMessageEditingCapabilitiesUpdate, &payload, out_frame);
}

bool OFEncodeTextCursorUpdate(const OFTextCursorSnapshot *cursors, size_t cursor_count, OFBuffer *out_frame) {
    if (cursor_count > UINT32_MAX) cursor_count = UINT32_MAX;
    OFByteWriter payload = {0};
    bool ok = OFWriteU32(&payload, (uint32_t)cursor_count);
    for (size_t i = 0; ok && i < cursor_count; i++) {
        ok = OFWriteStringView32(&payload, cursors[i].field_id) &&
             OFWriteF32(&payload, (float)cursors[i].rect.origin.x) &&
             OFWriteF32(&payload, (float)cursors[i].rect.origin.y) &&
             OFWriteF32(&payload, (float)cursors[i].rect.size.width) &&
             OFWriteF32(&payload, (float)cursors[i].rect.size.height) &&
             OFWriteU8(&payload, cursors[i].visible ? 1 : 0);
    }
    if (!ok) {
        OFWriterFree(&payload);
        return false;
    }
    return OFFinishPayload(OFContentMessageTextCursorUpdate, &payload, out_frame);
}

bool OFEncodeOpenNewWindow(const char *url, const char *display_string_or_null, bool has_preferred_size, float preferred_width, float preferred_height, OFBuffer *out_frame) {
    OFByteWriter payload = {0};
    bool ok = OFWriteCString32(&payload, url);
    if (display_string_or_null) {
        ok = ok && OFWriteU8(&payload, 1) && OFWriteCString32(&payload, display_string_or_null);
    } else {
        ok = ok && OFWriteU8(&payload, 0);
    }
    if (has_preferred_size) {
        ok = ok && OFWriteU8(&payload, 1) && OFWriteF32(&payload, preferred_width) && OFWriteF32(&payload, preferred_height);
    } else {
        ok = ok && OFWriteU8(&payload, 0);
    }
    if (!ok) {
        OFWriterFree(&payload);
        return false;
    }
    return OFFinishPayload(OFContentMessageOpenNewWindow, &payload, out_frame);
}

void OFBufferFree(OFBuffer *buffer) {
    if (!buffer) return;
    free(buffer->bytes);
    buffer->bytes = NULL;
    buffer->length = 0;
}
