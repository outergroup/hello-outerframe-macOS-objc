#import "OuterframeAccessibility.h"

#include <stdlib.h>
#include <string.h>

typedef struct {
    uint8_t *bytes;
    size_t length;
    size_t capacity;
} OFAXWriter;

static bool OFAXReserve(OFAXWriter *writer, size_t additional) {
    if (additional > SIZE_MAX - writer->length) return false;
    size_t needed = writer->length + additional;
    if (needed <= writer->capacity) return true;
    size_t capacity = writer->capacity ? writer->capacity : 128;
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

static bool OFAXWriteBytes(OFAXWriter *writer, const void *bytes, size_t length) {
    if (!OFAXReserve(writer, length)) return false;
    memcpy(writer->bytes + writer->length, bytes, length);
    writer->length += length;
    return true;
}

static bool OFAXWriteU8(OFAXWriter *writer, uint8_t value) {
    return OFAXWriteBytes(writer, &value, sizeof(value));
}

static bool OFAXWriteU16(OFAXWriter *writer, uint16_t value) {
    uint8_t bytes[2] = { (uint8_t)(value & 0xff), (uint8_t)((value >> 8) & 0xff) };
    return OFAXWriteBytes(writer, bytes, sizeof(bytes));
}

static bool OFAXWriteU32(OFAXWriter *writer, uint32_t value) {
    uint8_t bytes[4] = {
        (uint8_t)(value & 0xff),
        (uint8_t)((value >> 8) & 0xff),
        (uint8_t)((value >> 16) & 0xff),
        (uint8_t)((value >> 24) & 0xff),
    };
    return OFAXWriteBytes(writer, bytes, sizeof(bytes));
}

static bool OFAXWriteU64(OFAXWriter *writer, uint64_t value) {
    uint8_t bytes[8] = {
        (uint8_t)(value & 0xff),
        (uint8_t)((value >> 8) & 0xff),
        (uint8_t)((value >> 16) & 0xff),
        (uint8_t)((value >> 24) & 0xff),
        (uint8_t)((value >> 32) & 0xff),
        (uint8_t)((value >> 40) & 0xff),
        (uint8_t)((value >> 48) & 0xff),
        (uint8_t)((value >> 56) & 0xff),
    };
    return OFAXWriteBytes(writer, bytes, sizeof(bytes));
}

static bool OFAXWriteF64(OFAXWriter *writer, double value) {
    uint64_t bits = 0;
    memcpy(&bits, &value, sizeof(bits));
    return OFAXWriteU64(writer, bits);
}

static bool OFAXWriteOptionalCString(OFAXWriter *writer, const char *string) {
    if (!string) return OFAXWriteU8(writer, 0);
    size_t length = strlen(string);
    if (length > UINT32_MAX) return false;
    return OFAXWriteU8(writer, 1) &&
           OFAXWriteU32(writer, (uint32_t)length) &&
           OFAXWriteBytes(writer, string, length);
}

static bool OFAXWriteOptionalInt32(OFAXWriter *writer, bool present, int32_t value) {
    if (!present) return OFAXWriteU8(writer, 0);
    return OFAXWriteU8(writer, 1) && OFAXWriteU32(writer, (uint32_t)value);
}

static void OFAXFreeWriter(OFAXWriter *writer) {
    free(writer->bytes);
    writer->bytes = NULL;
    writer->length = 0;
    writer->capacity = 0;
}

static bool OFAXEncodeNode(OFAXWriter *writer, const OFAccessibilityNode *node) {
    if (!node) return false;
    size_t child_count = node->child_count > UINT16_MAX ? UINT16_MAX : node->child_count;

    bool ok = OFAXWriteU32(writer, node->identifier) &&
              OFAXWriteU8(writer, node->role) &&
              OFAXWriteF64(writer, node->frame.origin.x) &&
              OFAXWriteF64(writer, node->frame.origin.y) &&
              OFAXWriteF64(writer, node->frame.size.width) &&
              OFAXWriteF64(writer, node->frame.size.height) &&
              OFAXWriteOptionalCString(writer, node->label) &&
              OFAXWriteOptionalCString(writer, node->value) &&
              OFAXWriteOptionalCString(writer, node->hint) &&
              OFAXWriteOptionalInt32(writer, node->has_row_count, node->row_count) &&
              OFAXWriteOptionalInt32(writer, node->has_column_count, node->column_count) &&
              OFAXWriteU8(writer, node->enabled ? 1 : 0) &&
              OFAXWriteU16(writer, (uint16_t)child_count);
    for (size_t i = 0; ok && i < child_count; i++) {
        ok = OFAXEncodeNode(writer, &node->children[i]);
    }
    return ok;
}

bool OFAccessibilitySnapshotEncode(const OFAccessibilitySnapshot *snapshot, OFBuffer *out_data) {
    if (!snapshot || !out_data) return false;
    OFAXWriter writer = {0};
    size_t root_count = snapshot->root_count > UINT16_MAX ? UINT16_MAX : snapshot->root_count;
    bool ok = OFAXWriteU8(&writer, 1) && OFAXWriteU16(&writer, (uint16_t)root_count);
    for (size_t i = 0; ok && i < root_count; i++) {
        ok = OFAXEncodeNode(&writer, &snapshot->root_nodes[i]);
    }
    if (!ok) {
        OFAXFreeWriter(&writer);
        return false;
    }
    out_data->bytes = writer.bytes;
    out_data->length = writer.length;
    return true;
}

bool OFAccessibilityNotImplementedSnapshot(const char *message, OFBuffer *out_data) {
    OFAccessibilityNode child = {
        .identifier = 1,
        .role = OFAccessibilityRoleStaticText,
        .frame = CGRectZero,
        .label = message ? message : "Accessibility not implemented",
        .enabled = true,
    };
    OFAccessibilityNode root = {
        .identifier = 0,
        .role = OFAccessibilityRoleContainer,
        .frame = CGRectZero,
        .enabled = true,
        .children = &child,
        .child_count = 1,
    };
    OFAccessibilitySnapshot snapshot = {
        .root_nodes = &root,
        .root_count = 1,
    };
    return OFAccessibilitySnapshotEncode(&snapshot, out_data);
}
