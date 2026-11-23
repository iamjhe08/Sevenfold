//
//  main.mm
//  sevenfoldd
//
//  BY: T4MAG0
//

#import "SFDaemonListener.h"

@interface NSXPCListener (SFMachService)
- (id)initWithMachServiceName:(NSString *)name;
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        setuid(0);

        SFDaemonListener *service = [SFDaemonListener new];
        [service initialiseListener];

        // initWithMachServiceName: is marked unavailable on iOS, so reach it at run time.
        NSXPCListener *listener = [[NSClassFromString(@"NSXPCListener") alloc] initWithMachServiceName:@"com.t4mag0.sevenfoldd"];
        listener.delegate = service;
        [listener resume];

        [[NSRunLoop currentRunLoop] run];
    }
    return EXIT_SUCCESS;
}
