#ifndef OUTERFRAME_MESSAGE_H
#define OUTERFRAME_MESSAGE_H

#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    OFContentSocketHeaderLength = sizeof(uint32_t),
    OFContentSocketMessageTypeLength = sizeof(uint16_t)
};

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
    OFInitArgKindHistoryEntryID = 9,
};

typedef uint16_t OFBrowserMessageKind;
enum {
    OFBrowserMessageInitializeContent = 1000,
    OFBrowserMessageResizeContent = 1001,
    OFBrowserMessageShutdown = 1002,
    OFBrowserMessageDisplayLinkFired = 1003,
    OFBrowserMessageDisplayLinkCallbackRegistered = 1004,
    OFBrowserMessageSystemAppearanceUpdate = 1005,
    OFBrowserMessageWindowActiveUpdate = 1006,
    OFBrowserMessageViewFocusChanged = 1007,
    OFBrowserMessageMouseDown = 1008,
    OFBrowserMessageMouseDragged = 1009,
    OFBrowserMessageMouseUp = 1010,
    OFBrowserMessageMouseMoved = 1011,
    OFBrowserMessageRightMouseDown = 1012,
    OFBrowserMessageRightMouseUp = 1013,
    OFBrowserMessageScrollWheelEvent = 1014,
    OFBrowserMessageKeyDown = 1015,
    OFBrowserMessageKeyUp = 1016,
    OFBrowserMessageMagnification = 1017,
    OFBrowserMessageMagnificationEnded = 1018,
    OFBrowserMessageQuickLook = 1019,
    OFBrowserMessageTextInput = 1020,
    OFBrowserMessageSetMarkedText = 1021,
    OFBrowserMessageUnmarkText = 1022,
    OFBrowserMessageTextInputFocus = 1023,
    OFBrowserMessageTextCommand = 1024,
    OFBrowserMessageSetCursorPosition = 1025,
    OFBrowserMessageImageWithSystemSymbolName = 1026,
    OFBrowserMessageCopySelectedPasteboardRequest = 1027,
    OFBrowserMessagePasteboardContentDelivered = 1028,
    OFBrowserMessageAccessibilitySnapshotRequest = 1029,
    OFBrowserMessageHistoryEntryAccepted = 1030,
    OFBrowserMessageHistoryEntryRejected = 1031,
    OFBrowserMessageHistoryTraversal = 1032,
    OFBrowserMessageHistoryContextUpdate = 1033,
};

typedef uint16_t OFContentMessageKind;
enum {
    OFContentMessageStartDisplayLink = 2000,
    OFContentMessageStopDisplayLink = 2001,
    OFContentMessageCursorUpdate = 2002,
    OFContentMessageInputModeUpdate = 2003,
    OFContentMessageTextCursorUpdate = 2004,
    OFContentMessageShowContextMenu = 2005,
    OFContentMessageShowDefinition = 2006,
    OFContentMessageGetImageWithSystemSymbolName = 2007,
    OFContentMessageHapticFeedback = 2008,
    OFContentMessageCopySelectedPasteboardResponse = 2009,
    OFContentMessageEditingCapabilitiesUpdate = 2010,
    OFContentMessageAccessibilitySnapshotResponse = 2011,
    OFContentMessageAccessibilityTreeChanged = 2012,
    OFContentMessageOpenNewWindow = 2013,
    OFContentMessageHistoryPushEntry = 2014,
    OFContentMessageHistoryReplaceEntry = 2015,
    OFContentMessageHistoryGo = 2016,
    OFContentMessagePageMetadataUpdate = 2017,
    OFContentMessageStartPageMetadataUpdate = 2018,
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
    CGSize content_size;
    bool has_appearance_archive;
    OFDataView appearance_archive;
    OFInitializeContentProxy proxy;
    bool has_url;
    OFStringView url;
    bool has_bundle_url;
    OFStringView bundle_url;
    bool has_window_is_active;
    bool window_is_active;
    bool has_history_entry_id;
    OFUUID history_entry_id;
} OFInitializeContent;

typedef struct {
    OFStringView type_identifier;
    OFDataView data;
} OFPasteboardItemView;

typedef struct {
    OFUUID field_id;
    CGRect rect;
    bool visible;
} OFTextCursorSnapshot;

typedef struct {
    uint16_t key_code;
    OFStringView characters;
    OFStringView characters_ignoring_modifiers;
    uint64_t modifier_flags;
    bool is_a_repeat;
} OFKeyEvent;

typedef struct {
    OFBrowserMessageKind kind;
    union {
        OFInitializeContent initialize;
        struct { uint64_t frame_number; double target_timestamp; } display_link_fired;
        struct { OFUUID callback_id; OFUUID browser_callback_id; } display_link_callback_registered;
        CGSize resize;
        struct { double x; double y; uint64_t modifier_flags; uint32_t click_count; } mouse;
        struct { double x; double y; double delta_x; double delta_y; uint64_t modifier_flags; uint32_t phase; uint32_t momentum_phase; bool has_precise_scrolling_deltas; } scroll;
        OFKeyEvent key;
        struct { uint32_t surface_id; double magnification; double x; double y; double scroll_x; double scroll_y; } magnification;
        struct { double x; double y; } point;
        struct { OFUUID request_id; OFDataView alpha_mask_data; bool has_alpha_mask_data; uint32_t width; uint32_t height; uint32_t bytes_per_row; bool success; OFStringView error_message; bool has_error_message; } image_response;
        struct { OFStringView text; bool has_replacement_range; uint64_t replacement_location; uint64_t replacement_length; } text_input;
        struct { OFStringView text; uint64_t selected_location; uint64_t selected_length; bool has_replacement_range; uint64_t replacement_location; uint64_t replacement_length; } marked_text;
        struct { OFUUID field_id; bool has_focus; } text_focus;
        struct { OFStringView command; } text_command;
        struct { OFUUID field_id; uint64_t position; bool modify_selection; } cursor_position;
        struct { OFDataView appearance_archive; } appearance;
        struct { bool value; } boolean_update;
        struct { OFUUID request_id; } request;
        struct { OFPasteboardItemView *items; size_t count; } pasteboard;
        struct { OFUUID entry_id; OFStringView url; OFStringView error_message; uint32_t length; bool can_go_back; bool can_go_forward; } history;
    } as;
} OFBrowserMessage;

bool OFBrowserMessageDecode(const uint8_t *message, size_t message_length, OFBrowserMessage *out_message);
void OFBrowserMessageFree(OFBrowserMessage *message);

bool OFEncodeFrame(uint16_t type, OFDataView payload, OFBuffer *out_frame);
bool OFEncodeCursorUpdate(OFCursorType cursor_type, OFBuffer *out_frame);
bool OFEncodeInputModeUpdate(OFContentInputMode input_mode, OFBuffer *out_frame);
bool OFEncodeShowContextMenu(OFDataView attributed_text_rtf, double location_x, double location_y, OFBuffer *out_frame);
bool OFEncodeShowDefinition(OFDataView attributed_text_rtf, double location_x, double location_y, OFBuffer *out_frame);
bool OFEncodeGetImageWithSystemSymbolName(OFUUID request_id, const char *symbol_name, double point_size, double weight, double scale, OFBuffer *out_frame);
bool OFEncodePageMetadata(bool start_page, const char *title_or_null, const uint8_t *icon_png_or_null, size_t icon_png_length, uint32_t icon_width, uint32_t icon_height, OFBuffer *out_frame);
bool OFEncodeAccessibilitySnapshotResponse(OFUUID request_id, const uint8_t *snapshot_or_null, size_t snapshot_length, OFBuffer *out_frame);
bool OFEncodeAccessibilityTreeChanged(uint8_t notification_mask, OFBuffer *out_frame);
bool OFEncodeHapticFeedback(OFHapticFeedbackStyle style, OFBuffer *out_frame);
bool OFEncodeStartDisplayLink(OFUUID callback_id, OFBuffer *out_frame);
bool OFEncodeStopDisplayLink(OFUUID browser_callback_id, OFBuffer *out_frame);
bool OFEncodeCopySelectedPasteboardResponse(OFUUID request_id, const OFPasteboardItemView *items, size_t item_count, OFBuffer *out_frame);
bool OFEncodePasteboardCapabilities(bool can_copy, bool can_cut, const OFStringView *pasteboard_types, size_t type_count, OFBuffer *out_frame);
bool OFEncodeTextCursorUpdate(const OFTextCursorSnapshot *cursors, size_t cursor_count, OFBuffer *out_frame);
bool OFEncodeOpenNewWindow(const char *url, const char *display_string_or_null, bool has_preferred_size, CGSize preferred_size, OFBuffer *out_frame);
bool OFEncodeHistoryEntry(uint16_t message_type, OFUUID entry_id, const char *url_or_null, OFBuffer *out_frame);
bool OFEncodeHistoryGo(int32_t delta, OFBuffer *out_frame);
void OFBufferFree(OFBuffer *buffer);

#ifdef __cplusplus
}
#endif

#endif
