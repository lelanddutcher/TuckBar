#import "VDisplay.h"
#import <objc/message.h>

static NSMutableArray *gDisplays;
static NSString *gError = @"";

const char *VDLastError(void) { return gError.UTF8String; }

uint32_t VDCreate(uint32_t width, uint32_t height, const char *name) {
    if (!gDisplays) gDisplays = [NSMutableArray array];
    Class Desc = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class Disp = NSClassFromString(@"CGVirtualDisplay");
    Class Mode = NSClassFromString(@"CGVirtualDisplayMode");
    Class Sett = NSClassFromString(@"CGVirtualDisplaySettings");
    if (!Desc || !Disp || !Mode || !Sett) { gError = @"CGVirtualDisplay classes not found"; return 0; }
    @try {
        id desc = [[Desc alloc] init];
        SEL setQueue = NSSelectorFromString(@"setDispatchQueue:");
        if ([desc respondsToSelector:setQueue]) {
            ((void (*)(id, SEL, id))objc_msgSend)(desc, setQueue, dispatch_get_main_queue());
        } else {
            [desc setValue:dispatch_get_main_queue() forKey:@"queue"];
        }
        [desc setValue:[NSString stringWithUTF8String:name] forKey:@"name"];
        [desc setValue:@(width) forKey:@"maxPixelsWide"];
        [desc setValue:@(height) forKey:@"maxPixelsHigh"];
        [desc setValue:[NSValue valueWithSize:NSMakeSize(width * 0.25, height * 0.25)] forKey:@"sizeInMillimeters"];
        [desc setValue:@(0x7442) forKey:@"productID"];
        [desc setValue:@(0x7442) forKey:@"vendorID"];
        [desc setValue:@((uint32_t)gDisplays.count + 1) forKey:@"serialNum"];

        id disp = ((id (*)(id, SEL, id))objc_msgSend)([Disp alloc], NSSelectorFromString(@"initWithDescriptor:"), desc);
        if (!disp) { gError = @"initWithDescriptor returned nil"; return 0; }
        id mode = ((id (*)(id, SEL, unsigned int, unsigned int, double))objc_msgSend)(
            [Mode alloc], NSSelectorFromString(@"initWithWidth:height:refreshRate:"), width, height, 60.0);
        id settings = [[Sett alloc] init];
        [settings setValue:@0 forKey:@"hiDPI"];
        [settings setValue:@[mode] forKey:@"modes"];
        BOOL ok = ((BOOL (*)(id, SEL, id))objc_msgSend)(disp, NSSelectorFromString(@"applySettings:"), settings);
        if (!ok) { gError = @"applySettings failed"; return 0; }
        [gDisplays addObject:disp];
        return ((unsigned int (*)(id, SEL))objc_msgSend)(disp, NSSelectorFromString(@"displayID"));
    } @catch (NSException *e) {
        gError = [NSString stringWithFormat:@"%@: %@", e.name, e.reason];
        return 0;
    }
}
