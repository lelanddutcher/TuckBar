#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

/// Create a virtual display (private CGVirtualDisplay, as used by Chromium's tests and DeskPad).
/// Returns its CGDirectDisplayID, or 0 on failure (reason in VDLastError). It lives until the process exits.
uint32_t VDCreate(uint32_t width, uint32_t height, const char *name);
const char *VDLastError(void);
