// Tweak.xm
// JPushDisableTweak written by silentninjabee 17th August 2026

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <mach-o/dyld.h>
#include <stdlib.h>

#import "JPDMethodNeutralizer.h"

// Neutralize the Jiguang/JPush Objective-C classes found in the target game's
// IDA exports without linking this tweak against a particular SDK release.

static NSSet<NSString *> *JPDKnownJiguangClassNames(void) {
    static NSSet<NSString *> *classNames;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
#define JPD_JIGUANG_CLASS(name) @name,
        classNames = [NSSet setWithArray:@[
#include "JiguangClassNames.inc"
        ]];
#undef JPD_JIGUANG_CLASS
    });
    return classNames;
}

static BOOL JPDIsKnownJiguangClass(const char *className) {
    if (className == NULL) {
        return NO;
    }
    return [JPDKnownJiguangClassNames()
            containsObject:[NSString stringWithUTF8String:className]];
}

static NSUInteger JPDMethodCount(Class targetClass) {
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(targetClass, &methodCount);
    free(methods);
    return methodCount;
}

static NSMutableDictionary<NSValue *, NSNumber *> *JPDLastMethodCounts(void) {
    static NSMutableDictionary<NSValue *, NSNumber *> *methodCounts;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        methodCounts = [NSMutableDictionary dictionary];
    });
    return methodCounts;
}

static NSUInteger JPDLastRuntimeClassCount = 0;
static BOOL JPDCompletedInitialScan = NO;

static BOOL JPDClassNeedsScan(Class targetClass) {
    NSValue *key = [NSValue valueWithPointer:(__bridge const void *)(targetClass)];
    NSNumber *lastCount = JPDLastMethodCounts()[key];
    NSUInteger currentCount = JPDMethodCount(targetClass);
    if (lastCount != nil && lastCount.unsignedIntegerValue == currentCount) {
        return NO;
    }
    return YES;
}

static void JPDRememberClassMethodCount(Class targetClass) {
    NSValue *key = [NSValue valueWithPointer:(__bridge const void *)(targetClass)];
    JPDLastMethodCounts()[key] = @(JPDMethodCount(targetClass));
}

static void JPDInstallHooks(void) {
    NSUInteger runtimeClassCount = (NSUInteger)objc_getClassList(NULL, 0);
    @synchronized (JPDLastMethodCounts()) {
        // dyld can report many image additions while the process launches.
        // If no Objective-C classes were added, there is nothing new for the
        // manifest to inspect and we must return before copying the class list.
        if (JPDCompletedInitialScan &&
            runtimeClassCount == JPDLastRuntimeClassCount) {
            return;
        }
        JPDLastRuntimeClassCount = runtimeClassCount;
        JPDCompletedInitialScan = YES;
    }

    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    if (classes == NULL) {
        return;
    }

    NSUInteger hookedCount = 0;
    NSUInteger scannedClassCount = 0;
    @synchronized (JPDLastMethodCounts()) {
        for (unsigned int index = 0; index < classCount; index++) {
            Class cls = classes[index];
            const char *runtimeClassName = class_getName(cls);
            if (!JPDIsKnownJiguangClass(runtimeClassName)) {
                continue;
            }

            // Instance methods live on the class and class methods on its
            // metaclass. Revisit a class only when a newly loaded image added
            // methods (for example through a category).
            if (JPDClassNeedsScan(cls)) {
                hookedCount += JPDNeutralizeMethodsDeclaredByClass(cls);
                JPDRememberClassMethodCount(cls);
                scannedClassCount++;
            }

            Class metaClass = object_getClass(cls);
            if (metaClass != Nil && JPDClassNeedsScan(metaClass)) {
                hookedCount += JPDNeutralizeMethodsDeclaredByClass(metaClass);
                JPDRememberClassMethodCount(metaClass);
                scannedClassCount++;
            }
        }
    }

    free(classes);

#if DEBUG
    NSLog(@"[JPushDisable] Disabled %lu Jiguang method(s); scanned %lu class tables",
          (unsigned long)hookedCount, (unsigned long)scannedClassCount);
#else
    (void)hookedCount;
#endif
}

static void JPDImageDidLoad(const struct mach_header *header,
                            intptr_t vmAddressSlide) {
    (void)header;
    (void)vmAddressSlide;
    @autoreleasepool {
        JPDInstallHooks();
    }
}

%ctor {
    @autoreleasepool {
        JPDInstallHooks();
        _dyld_register_func_for_add_image(JPDImageDidLoad);
    }
}
