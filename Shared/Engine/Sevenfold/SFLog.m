//
//  SFLog.m
//  Sevenfold
//

#import "SFLog.h"

static NSString *SFLogPath(void) {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    dir = [dir stringByAppendingPathComponent:@"Sevenfold"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"events.log"];
}

static dispatch_queue_t SFLogQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.t4mag0.sevenfold.log", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static const unsigned long long SFLogMaxBytes = 256 * 1024;

void SFLogEvent(SFLogLevel level, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[Sevenfold] %@", message);

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    dispatch_async(SFLogQueue(), ^{
        NSString *path = SFLogPath();
        NSString *clean = [[message stringByReplacingOccurrencesOfString:@"\n" withString:@" "] stringByReplacingOccurrencesOfString:@"\t" withString:@" "];
        NSString *line = [NSString stringWithFormat:@"%.0f\t%ld\t%@\n", now, (long)level, clean];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];

        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:path]) {
            [data writeToFile:path atomically:YES];
            return;
        }

        unsigned long long size = [[fm attributesOfItemAtPath:path error:nil] fileSize];
        if (size > SFLogMaxBytes) {
            // Keep the newest half.
            NSData *old = [NSData dataWithContentsOfFile:path];
            NSData *tail = [old subdataWithRange:NSMakeRange(old.length / 2, old.length - old.length / 2)];
            NSRange nl = [tail rangeOfData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding] options:0 range:NSMakeRange(0, tail.length)];
            if (nl.location != NSNotFound)
                tail = [tail subdataWithRange:NSMakeRange(nl.location + 1, tail.length - nl.location - 1)];
            NSMutableData *fresh = [tail mutableCopy];
            [fresh appendData:data];
            [fresh writeToFile:path atomically:YES];
            return;
        }

        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    });
}

@implementation SFLog

+ (NSArray<NSDictionary *> *)recentEntries:(NSUInteger)limit {
    __block NSString *contents = nil;
    dispatch_sync(SFLogQueue(), ^{
        contents = [NSString stringWithContentsOfFile:SFLogPath() encoding:NSUTF8StringEncoding error:nil];
    });
    NSArray *lines = [contents componentsSeparatedByString:@"\n"];
    NSMutableArray *entries = [NSMutableArray array];
    for (NSString *line in [lines reverseObjectEnumerator]) {
        NSArray *parts = [line componentsSeparatedByString:@"\t"];
        if (parts.count < 3) continue;
        [entries addObject:@{
            @"date": [NSDate dateWithTimeIntervalSince1970:[parts[0] doubleValue]],
            @"level": @([parts[1] integerValue]),
            @"message": [[parts subarrayWithRange:NSMakeRange(2, parts.count - 2)] componentsJoinedByString:@" "]
        }];
        if (entries.count >= limit) break;
    }
    return entries;
}

+ (NSString *)exportText {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSMutableString *text = [NSMutableString string];
    for (NSDictionary *entry in [[self recentEntries:2000] reverseObjectEnumerator]) {
        static NSArray *names;
        names = @[@"info", @"ok", @"warn", @"error"];
        NSInteger level = MIN(MAX([entry[@"level"] integerValue], 0), 3);
        [text appendFormat:@"%@  %-5@ %@\n", [formatter stringFromDate:entry[@"date"]], names[level], entry[@"message"]];
    }
    return text;
}

+ (void)clear {
    dispatch_sync(SFLogQueue(), ^{
        [[NSFileManager defaultManager] removeItemAtPath:SFLogPath() error:nil];
    });
}

@end
