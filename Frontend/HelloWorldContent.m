#import "HelloWorldContent.h"
#import "Vendor/OuterframeC/OuterframeHost.h"

#import <AppKit/AppKit.h>
#import <stdlib.h>

typedef struct {
    OFHost *host;
    __strong id<OuterframeAppConnection> app_connection;
    __strong NSAppearance *appearance;
    __strong CALayer *root_layer;
    __strong CATextLayer *title_layer;
    __strong CATextLayer *subtitle_layer;
    CGSize current_size;
    bool destroy_scheduled;
} HelloWorldApp;

static void HelloWorldSetAppearance(HelloWorldApp *app, NSAppearance *appearance) {
    app->appearance = appearance ?: NSAppearance.currentDrawingAppearance;
}

static void HelloWorldConfigureLayersIfNeeded(HelloWorldApp *app) {
    CALayer *root_layer = app->root_layer;
    CATextLayer *title_layer = app->title_layer;
    CATextLayer *subtitle_layer = app->subtitle_layer;

    if (title_layer.superlayer) {
        return;
    }

    title_layer.string = @"Hello, world!";
    title_layer.font = (__bridge CFTypeRef)[NSFont systemFontOfSize:34 weight:NSFontWeightSemibold];
    title_layer.fontSize = 34;
    title_layer.alignmentMode = kCAAlignmentCenter;
    title_layer.contentsScale = 2.0;
    title_layer.wrapped = YES;

    subtitle_layer.string = @"This is an outerframe app.";
    subtitle_layer.font = (__bridge CFTypeRef)[NSFont systemFontOfSize:15 weight:NSFontWeightRegular];
    subtitle_layer.fontSize = 15;
    subtitle_layer.alignmentMode = kCAAlignmentCenter;
    subtitle_layer.contentsScale = 2.0;
    subtitle_layer.wrapped = YES;

    [root_layer addSublayer:title_layer];
    [root_layer addSublayer:subtitle_layer];
}

static void HelloWorldUpdateLayout(HelloWorldApp *app) {
    CGFloat width = MAX(app->current_size.width, 1);
    CGFloat height = MAX(app->current_size.height, 1);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    app->root_layer.frame = CGRectMake(0, 0, width, height);
    CGFloat horizontal_padding = MIN(MAX(width * 0.1, 24), 80);
    app->title_layer.frame = CGRectMake(horizontal_padding, height * 0.5, width - (horizontal_padding * 2), 44);
    app->subtitle_layer.frame = CGRectMake(horizontal_padding, MAX(CGRectGetMinY(app->title_layer.frame) - 48, 24), width - (horizontal_padding * 2), 40);

    [CATransaction commit];
}

static void HelloWorldUpdateColors(HelloWorldApp *app) {
    NSAppearance *appearance = app->appearance ?: NSAppearance.currentDrawingAppearance;

    [appearance performAsCurrentDrawingAppearance:^{
        app->root_layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
        app->title_layer.foregroundColor = NSColor.labelColor.CGColor;
        app->subtitle_layer.foregroundColor = NSColor.secondaryLabelColor.CGColor;
    }];
}

static bool HelloWorldWriteAccessibilitySnapshot(HelloWorldApp *app, OFBuffer *out_snapshot_data) {
    NSString *title = [app->title_layer.string isKindOfClass:NSString.class] ? (NSString *)app->title_layer.string : @"Hello, world!";
    NSString *subtitle = [app->subtitle_layer.string isKindOfClass:NSString.class] ? (NSString *)app->subtitle_layer.string : @"";

    OFAccessibilityNode nodes[3] = {
        {
            .identifier = 1,
            .role = OFAccessibilityRoleStaticText,
            .frame = app->title_layer.frame,
            .label = title.UTF8String,
            .enabled = true,
        },
        {
            .identifier = 2,
            .role = OFAccessibilityRoleStaticText,
            .frame = app->subtitle_layer.frame,
            .label = subtitle.UTF8String,
            .enabled = true,
        },
        {
            .identifier = 0,
            .role = OFAccessibilityRoleContainer,
            .frame = app->root_layer.frame,
            .label = "Hello world outerframe app",
            .enabled = true,
        },
    };
    nodes[2].children = nodes;
    nodes[2].child_count = 2;

    OFAccessibilitySnapshot snapshot = {
        .root_nodes = &nodes[2],
        .root_count = 1,
    };
    return OFAccessibilitySnapshotEncode(&snapshot, out_snapshot_data);
}

static void HelloWorldAppDestroy(HelloWorldApp *app) {
    if (!app) return;
    if (app->host) {
        OFHostDestroy(app->host);
        app->host = NULL;
    }
    app->app_connection = nil;
    app->appearance = nil;
    app->root_layer = nil;
    app->title_layer = nil;
    app->subtitle_layer = nil;
    free(app);
}

static void HelloWorldScheduleDestroy(HelloWorldApp *app) {
    if (!app || app->destroy_scheduled) {
        return;
    }
    app->destroy_scheduled = true;
    dispatch_async(dispatch_get_main_queue(), ^{
        HelloWorldAppDestroy(app);
    });
}

static void HelloWorldHandleMessage(OFHost *host, const OFBrowserMessage *message, void *context) {
    HelloWorldApp *app = context;
    switch (message->kind) {
        case OFBrowserMessageInitializeContent: {
            const OFInitializeContent *initialize = &message->as.initialize;
            OFHostConfigureFromInitialize(host, initialize);

            NSAppearance *appearance;
            if (initialize->has_appearance_archive) {
                NSData *data = [NSData dataWithBytesNoCopy:(void *)initialize->appearance_archive.bytes
                                                     length:initialize->appearance_archive.length
                                               freeWhenDone:NO];
                appearance = [NSKeyedUnarchiver unarchivedObjectOfClass:NSAppearance.class fromData:data error:nil];
            } else {
                appearance = NSAppearance.currentDrawingAppearance;
            }

            HelloWorldSetAppearance(app, appearance);
            app->current_size = initialize->has_content_size ? initialize->content_size : CGSizeMake(800, 600);

            HelloWorldConfigureLayersIfNeeded(app);
            HelloWorldUpdateLayout(app);
            HelloWorldUpdateColors(app);

            if ([app->app_connection respondsToSelector:@selector(registerLayer:)]) {
                [app->app_connection registerLayer:app->root_layer];
            }

            OFHostUpdateStartPageMetadata(host, "Hello, world!", NULL, 0, 0, 0);
            OFHostUpdatePageMetadata(host, "Hello, world!", NULL, 0, 0, 0);
            break;
        }

        case OFBrowserMessageResizeContent:
            app->current_size = message->as.resize;
            HelloWorldUpdateLayout(app);
            break;

        case OFBrowserMessageSystemAppearanceUpdate:  {
            NSData *data = [NSData dataWithBytesNoCopy:(void *)message->as.appearance.appearance_archive.bytes
                                                 length:message->as.appearance.appearance_archive.length
                                           freeWhenDone:NO];
            NSAppearance *appearance = [NSKeyedUnarchiver unarchivedObjectOfClass:NSAppearance.class fromData:data error:nil];

            HelloWorldSetAppearance(app, appearance ?: NSAppearance.currentDrawingAppearance);
            HelloWorldUpdateColors(app);
            break;
        }

        case OFBrowserMessageAccessibilitySnapshotRequest: {
            OFBuffer snapshot_data = {0};
            if (!HelloWorldWriteAccessibilitySnapshot(app, &snapshot_data)) {
                OFAccessibilityNotImplementedSnapshot("Accessibility not implemented", &snapshot_data);
            }
            OFHostSendAccessibilitySnapshotResponse(host, message->as.request.request_id, snapshot_data.bytes, snapshot_data.length);
            OFBufferFree(&snapshot_data);
            break;
        }

        case OFBrowserMessageShutdown:
            HelloWorldScheduleDestroy(app);
            break;

        default:
            break;
    }
}

static void HelloWorldHandleDisconnect(OFHost *host, void *context) {
    (void)host;
    HelloWorldScheduleDestroy(context);
}

static HelloWorldApp *HelloWorldAppCreate(int32_t socket_fd, id<OuterframeAppConnection> app_connection) {
    HelloWorldApp *app = calloc(1, sizeof(*app));
    if (!app) {
        return NULL;
    }

    app->app_connection = app_connection;
    app->root_layer = [CALayer layer];
    app->title_layer = [CATextLayer layer];
    app->subtitle_layer = [CATextLayer layer];
    app->current_size = CGSizeMake(800, 600);

    OFHostCallbacks callbacks = {
        .message = HelloWorldHandleMessage,
        .disconnected = HelloWorldHandleDisconnect,
    };
    app->host = OFHostCreate(socket_fd, callbacks, app);
    if (!app->host) {
        HelloWorldAppDestroy(app);
        return NULL;
    }

    return app;
}

@implementation HelloWorldContent

+ (int32_t)startWithSocketFD:(int32_t)socketFD appConnection:(id<OuterframeAppConnection>)appConnection {
    return HelloWorldAppCreate(socketFD, appConnection) ? 0 : 1;
}

@end
