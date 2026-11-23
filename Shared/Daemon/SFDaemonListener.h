//
//  SFDaemonListener.h
//  Sevenfold
//
//  BY: T4MAG0
//
//  The background service: keeps the schedule, wakes the phone at the planned time,
//  opens Sevenfold in the background to sign, and keeps it running until it's done.
//

#import <Foundation/Foundation.h>
#import "SFDaemonProtocol.h"

@interface SFDaemonListener : NSObject <NSXPCListenerDelegate, SFDaemonProtocol>

/// Registers for system events and arms the schedule. Call once at start.
- (void)initialiseListener;

@end
