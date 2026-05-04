#ifndef OUTERFRAME_MESSAGE_H
#define OUTERFRAME_MESSAGE_H

#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum { OFContentSocketHeaderLength = sizeof(uint16_t) + sizeof(uint32_t) };

typedef struct {
    const uint8_t *bytes;
    size_t length;
} OFDataView;

typedef struct {
    const char *bytes;
    size_t length;
} OFStringView;

typedef struct {
    uint8_t bytes[16];
} OFUUID;

typedef struct {
    uint8_t *bytes;
    size_t length;
} OFBuffer;

static inline uint16_t OFReadUInt16LE(const uint8_t *bytes) {
    return (uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8);
}

static inline uint32_t OFReadUInt32LE(const uint8_t *bytes) {
    return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) | ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

typedef uint8_t OFInitArgKind;
enum {
    OFInitArgKindData = 1,
    OFInitArgKindContentSize = 2,
    OFInitArgKindAppearance = 3,
    OFInitArgKindProxy = 4,
    OFInitArgKindProxyAuth = 5,
    OFInitArgKindURL = 6,
    OFInitArgKindBundleURL = 7,
    OFInitArgKindWindowIsActive = 8,
};

typedef uint16_t OFBrowserMessageKind;
enum {
    OFBrowserMessageInitializeContent = 50,
    OFBrowserMessageDisplayLinkFired = 2,
    OFBrowserMessageDisplayLinkCallbackRegistered = 15,
    OFBrowserMessageResizeContent = 7,
    OFBrowserMessageMouseEvent = 8,
    OFBrowserMessageScrollWheelEvent = 47,
    OFBrowserMessageKeyDown = 9,
    OFBrowserMessageKeyUp = 10,
    OFBrowserMessageMagnification = 12,
    OFBrowserMessageMagnificationEnded = 13,
    OFBrowserMessageQuickLook = 20,
    OFBrowserMessageImageWithSystemSymbolName = 21,
    OFBrowserMessageTextInput = 22,
    OFBrowserMessageSetMarkedText = 23,
    OFBrowserMessageUnmarkText = 24,
    OFBrowserMessageTextInputFocus = 25,
    OFBrowserMessageTextCommand = 26,
    OFBrowserMessageSetCursorPosition = 27,
    OFBrowserMessageSystemAppearanceUpdate = 38,
    OFBrowserMessageWindowActiveUpdate = 39,
    OFBrowserMessageViewFocusChanged = 49,
    OFBrowserMessageCopySelectedPasteboardRequest = 40,
    OFBrowserMessagePasteboardContentDelivered = 45,
    OFBrowserMessageAccessibilitySnapshotRequest = 46,
    OFBrowserMessageShutdown = 51,
};

typedef uint16_t OFContentMessageKind;
enum {
    OFContentMessageStartDisplayLink = 17,
    OFContentMessageStopDisplayLink = 18,
    OFContentMessageCursorUpdate = 28,
    OFContentMessageInputModeUpdate = 29,
    OFContentMessageShowContextMenu = 34,
    OFContentMessageShowDefinition = 35,
    OFContentMessageGetImageWithSystemSymbolName = 36,
    OFContentMessageTextCursorUpdate = 37,
    OFContentMessagePageMetadataUpdate = 38,
    OFContentMessageStartPageMetadataUpdate = 39,
    OFContentMessageCopySelectedPasteboardResponse = 40,
    OFContentMessageOpenNewWindow = 41,
    OFContentMessageEditingCapabilitiesUpdate = 44,
    OFContentMessageAccessibilitySnapshotResponse = 45,
    OFContentMessageAccessibilityTreeChanged = 46,
    OFContentMessageHapticFeedback = 48,
};

typedef uint8_t OFMouseEventKind;
enum {
    OFMouseEventKindMouseDown = 1,
    OFMouseEventKindMouseDragged = 2,
    OFMouseEventKindMouseUp = 3,
    OFMouseEventKindMouseMoved = 4,
    OFMouseEventKindRightMouseDown = 5,
    OFMouseEventKindRightMouseUp = 6,
};

typedef uint8_t OFCursorType;
enum {
    OFCursorTypeArrow = 0,
    OFCursorTypeIBeam = 1,
    OFCursorTypeCrosshair = 2,
    OFCursorTypeOpenHand = 3,
    OFCursorTypeClosedHand = 4,
    OFCursorTypePointingHand = 5,
    OFCursorTypeResizeLeft = 6,
    OFCursorTypeResizeRight = 7,
    OFCursorTypeResizeLeftRight = 8,
    OFCursorTypeResizeUp = 9,
    OFCursorTypeResizeDown = 10,
    OFCursorTypeResizeUpDown = 11,
};

typedef uint8_t OFContentInputMode;
enum {
    OFContentInputModeNone = 0,
    OFContentInputModeTextInput = 1 << 0,
    OFContentInputModeRawKeys = 1 << 1,
};

typedef uint8_t OFHapticFeedbackStyle;
enum {
    OFHapticFeedbackStyleGeneric = 0,
    OFHapticFeedbackStyleAlignment = 1,
    OFHapticFeedbackStyleLevelChange = 2,
};

typedef struct {
    bool present;
    OFStringView host;
    uint16_t port;
    bool has_username;
    OFStringView username;
    bool has_password;
    OFStringView password;
} OFInitializeContentProxy;

typedef struct {
    bool has_data;
    OFDataView data;
    bool has_content_size;
    double content_width;
    double content_height;
    bool has_appearance_archive;
    OFDataView appearance_archive;
    OFInitializeContentProxy proxy;
    bool has_url;
    OFStringView url;
    bool has_bundle_url;
    OFStringView bundle_url;
    bool has_window_is_active;
    bool window_is_active;
} OFInitializeContent;

typedef struct {
    OFStringView type_identifier;
    OFDataView data;
} OFPasteboardItemView;

typedef struct {
    OFStringView field_id;
    CGRect rect;
    bool visible;
} OFTextCursorSnapshot;

typedef struct {
    uint16_t key_code;
    OFStringView characters;
    OFStringView characters_ignoring_modifiers;
    uint64_t modifier_flags;
    bool is_repeat;
} OFKeyEvent;

typedef struct {
    OFBrowserMessageKind kind;
    union {
        OFInitializeContent initialize;
        struct { uint64_t frame_number; double target_timestamp; } display_link_fired;
        struct { OFUUID callback_id; OFUUID browser_callback_id; } display_link_callback_registered;
        struct { double width; double height; } resize;
        struct { OFMouseEventKind kind; float x; float y; uint64_t modifier_flags; uint32_t click_count; } mouse;
        struct { float x; float y; float delta_x; float delta_y; uint64_t modifier_flags; uint32_t phase; uint32_t momentum_phase; bool is_momentum; bool is_precise; } scroll;
        OFKeyEvent key;
        struct { uint32_t surface_id; float magnification; float x; float y; float scroll_x; float scroll_y; } magnification;
        struct { float x; float y; } point;
        struct { OFUUID request_id; OFDataView image_data; bool has_image_data; uint32_t width; uint32_t height; bool success; OFStringView error_message; bool has_error_message; } image_response;
        struct { OFStringView text; bool has_replacement_range; uint64_t replacement_location; uint64_t replacement_length; } text_input;
        struct { OFStringView text; uint64_t selected_location; uint64_t selected_length; bool has_replacement_range; uint64_t replacement_location; uint64_t replacement_length; } marked_text;
        struct { OFStringView field_id; bool has_focus; } text_focus;
        struct { OFStringView command; } text_command;
        struct { OFStringView field_id; uint64_t position; bool modify_selection; } cursor_position;
        struct { OFDataView appearance_archive; } appearance;
        struct { bool value; } boolean_update;
        struct { OFUUID request_id; } request;
        struct { OFPasteboardItemView *items; size_t count; } pasteboard;
    } as;
} OFBrowserMessage;

bool OFBrowserMessageDecode(uint16_t type, const uint8_t *payload, size_t payload_length, OFBrowserMessage *out_message);
void OFBrowserMessageFree(OFBrowserMessage *message);

bool OFEncodeFrame(uint16_t type, OFDataView payload, OFBuffer *out_frame);
bool OFEncodeCursorUpdate(OFCursorType cursor_type, OFBuffer *out_frame);
bool OFEncodeInputModeUpdate(OFContentInputMode input_mode, OFBuffer *out_frame);
bool OFEncodeShowContextMenu(OFDataView attributed_text_rtf, float location_x, float location_y, OFBuffer *out_frame);
bool OFEncodeShowDefinition(OFDataView attributed_text_rtf, float location_x, float location_y, OFBuffer *out_frame);
bool OFEncodeGetImageWithSystemSymbolName(OFUUID request_id, const char *symbol_name, float point_size, const char *weight, float scale, float tint_red, float tint_green, float tint_blue, float tint_alpha, OFBuffer *out_frame);
bool OFEncodePageMetadata(bool start_page, const char *title_or_null, const uint8_t *icon_png_or_null, size_t icon_png_length, uint32_t icon_width, uint32_t icon_height, OFBuffer *out_frame);
bool OFEncodeAccessibilitySnapshotResponse(OFUUID request_id, const uint8_t *snapshot_or_null, size_t snapshot_length, OFBuffer *out_frame);
bool OFEncodeAccessibilityTreeChanged(uint8_t notification_mask, OFBuffer *out_frame);
bool OFEncodeHapticFeedback(OFHapticFeedbackStyle style, OFBuffer *out_frame);
bool OFEncodeStartDisplayLink(OFUUID callback_id, OFBuffer *out_frame);
bool OFEncodeStopDisplayLink(OFUUID browser_callback_id, OFBuffer *out_frame);
bool OFEncodeCopySelectedPasteboardResponse(OFUUID request_id, const OFPasteboardItemView *items, size_t item_count, OFBuffer *out_frame);
bool OFEncodePasteboardCapabilities(bool can_copy, bool can_cut, const OFStringView *pasteboard_types, size_t type_count, OFBuffer *out_frame);
bool OFEncodeTextCursorUpdate(const OFTextCursorSnapshot *cursors, size_t cursor_count, OFBuffer *out_frame);
bool OFEncodeOpenNewWindow(const char *url, const char *display_string_or_null, bool has_preferred_size, float preferred_width, float preferred_height, OFBuffer *out_frame);
void OFBufferFree(OFBuffer *buffer);

#ifdef __cplusplus
}
#endif

#endif
