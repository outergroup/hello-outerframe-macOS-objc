#ifndef OUTERFRAME_HOST_H
#define OUTERFRAME_HOST_H

#include "OuterframeAccessibility.h"
#include "OuterframeMessage.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct OFHost OFHost;

typedef void (*OFHostMessageCallback)(OFHost *host, const OFBrowserMessage *message, void *context);
typedef void (*OFHostDisconnectCallback)(OFHost *host, void *context);
typedef bool (*OFHostAccessibilitySnapshotCallback)(OFHost *host, OFBuffer *out_snapshot_data, void *context);
typedef void (*OFHostDisplayLinkCallback)(OFHost *host, double target_timestamp, void *context);
typedef void (*OFHostImageCallback)(OFHost *host, OFDataView image_data, uint32_t width, uint32_t height, void *context);

typedef struct {
    OFHostMessageCallback message;
    OFHostDisconnectCallback disconnected;
    OFHostAccessibilitySnapshotCallback accessibility_snapshot;
} OFHostCallbacks;

OFHost *OFHostCreate(int32_t socket_fd, OFHostCallbacks callbacks, void *context);
void OFHostDestroy(OFHost *host);

void OFHostConfigureFromInitialize(OFHost *host, const OFInitializeContent *initialize);
const char *OFHostURL(OFHost *host);
const char *OFHostBundleURL(OFHost *host);

void OFHostSetCursor(OFHost *host, OFCursorType cursor_type);
void OFHostSetInputMode(OFHost *host, OFContentInputMode input_mode);
void OFHostUpdatePageMetadata(OFHost *host, const char *title_or_null, const uint8_t *icon_png_or_null, size_t icon_png_length, uint32_t icon_width, uint32_t icon_height);
void OFHostUpdateStartPageMetadata(OFHost *host, const char *title_or_null, const uint8_t *icon_png_or_null, size_t icon_png_length, uint32_t icon_width, uint32_t icon_height);
void OFHostShowContextMenu(OFHost *host, OFDataView attributed_text_rtf, float location_x, float location_y);
void OFHostShowDefinition(OFHost *host, OFDataView attributed_text_rtf, float location_x, float location_y);
void OFHostSendAccessibilityTreeChanged(OFHost *host, OFAccessibilityNotification notification_mask);
void OFHostPerformHapticFeedback(OFHost *host, OFHapticFeedbackStyle style);
OFUUID OFHostRegisterDisplayLinkCallback(OFHost *host, OFHostDisplayLinkCallback callback, void *context);
void OFHostStopDisplayLinkCallback(OFHost *host, OFUUID callback_id);
OFUUID OFHostRequestSystemSymbolImage(OFHost *host, const char *symbol_name, float point_size, const char *weight, float scale, float tint_red, float tint_green, float tint_blue, float tint_alpha, OFHostImageCallback callback, void *context);

#ifdef __cplusplus
}
#endif

#endif
