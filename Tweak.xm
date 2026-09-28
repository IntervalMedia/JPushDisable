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

static void JPDInstallHooks(void) {
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    if (classes == NULL) {
        return;
    }

    NSUInteger hookedCount = 0;
    for (unsigned int index = 0; index < classCount; index++) {
        Class cls = classes[index];
        const char *runtimeClassName = class_getName(cls);
        if (!JPDIsKnownJiguangClass(runtimeClassName)) {
            continue;
        }

        // Instance methods live on the class and class methods on its
        // metaclass. Every method declared by the IDA-identified SDK classes
        // is neutralized, including public APIs without action-like names.
        hookedCount += JPDNeutralizeMethodsDeclaredByClass(cls);
        Class metaClass = object_getClass(cls);
        if (metaClass != Nil) {
            hookedCount += JPDNeutralizeMethodsDeclaredByClass(metaClass);
        }
    }

    free(classes);

#if DEBUG
    NSLog(@"[JPushDisable] Disabled %lu Jiguang method(s)",
          (unsigned long)hookedCount);
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
