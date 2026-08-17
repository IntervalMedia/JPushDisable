// Tweak.xm
// JPushDisableTweak written by silentninjabee 17th August 2026

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// This tweak disables Jiguang/JPush telemetry and network activity in applications 
// that statically link the JPush SDK 
// It uses the Objective-C runtime instead of linking against a particular SDK
// release.  Only Jiguang-owned classes and telemetry/network action are disabled.

//
// For this example the target game was the iOS version of Farlight84
// 1094 Jiguang methods were disabled upon startup!
// THE GAME STILL WORKS FINE, BUT NO LONGER SENDS ANY DATA TO JIGUANG SERVERS
//

static void JPDDisabledVoid(id self, SEL _cmd, ...) {
    (void)self;
    (void)_cmd;
}

static id JPDDisabledObject(id self, SEL _cmd, ...) {
    (void)self;
    (void)_cmd;
    return nil;
}

static uintptr_t JPDDisabledInteger(id self, SEL _cmd, ...) {
    (void)self;
    (void)_cmd;
    return 0;
}

static BOOL JPDHasJiguangClassPrefix(const char *className) {
    if (className == NULL) {
        return NO;
    }

    return strncmp(className, "JPUSH", 5) == 0 ||
           strncmp(className, "JPush", 5) == 0 ||
           strncmp(className, "JCORE", 5) == 0 ||
           strncmp(className, "JCore", 5) == 0 ||
           strncmp(className, "JCommon", 7) == 0;
}

static BOOL JPDIsBlockedSelector(SEL selector) {
    NSString *name = NSStringFromSelector(selector).lowercaseString;
    static NSArray<NSString *> *blockedTerms;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blockedTerms = @[
            @"setup", @"start", @"resume", @"register", @"login",
            @"connect", @"request", @"send", @"heartbeat",
            @"collect", @"track", @"report", @"upload",
            @"monitor", @"moniter", @"location", @"paste",
            @"applist", @"activeuser", @"crash"
        ];
    });

    for (NSString *term in blockedTerms) {
        if ([name containsString:term]) {
            return YES;
        }
    }
    return NO;
}

static char JPDReturnTypeForMethod(Method method) {
    char returnType[32] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));

    const char *type = returnType;
    while (*type == 'r' || *type == 'n' || *type == 'N' || *type == 'o' ||
           *type == 'O' || *type == 'R' || *type == 'V') {
        type++;
    }
    return *type;
}

static IMP JPDReplacementForMethod(Method method) {
    switch (JPDReturnTypeForMethod(method)) {
        case 'v':
            return (IMP)JPDDisabledVoid;
        case '@':
        case '#':
            return (IMP)JPDDisabledObject;
        case 'B':
        case 'c':
        case 'C':
        case 's':
        case 'S':
        case 'i':
        case 'I':
        case 'l':
        case 'L':
        case 'q':
        case 'Q':
        case '^':
            return (IMP)JPDDisabledInteger;
        default:
            // Struct and floating-point returns use different ARM64 return
            // conventions, so leave them untouched rather than risk a crash.
            return NULL;
    }
}

static NSUInteger JPDHookMethodsOnClass(Class targetClass) {
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(targetClass, &methodCount);
    NSUInteger hookedCount = 0;

    for (unsigned int index = 0; index < methodCount; index++) {
        Method method = methods[index];
        SEL selector = method_getName(method);
        if (!JPDIsBlockedSelector(selector)) {
            continue;
        }

        IMP replacement = JPDReplacementForMethod(method);
        if (replacement != NULL) {
            MSHookMessageEx(targetClass, selector, replacement, NULL);
            hookedCount++;
        }
    }

    free(methods);
    return hookedCount;
}

static void JPDInstallHooks(void) {
    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) {
        return;
    }

    Class *classes = (__unsafe_unretained Class *)calloc((size_t)classCount,
                                                          sizeof(Class));
    if (classes == NULL) {
        return;
    }

    classCount = objc_getClassList(classes, classCount);
    NSUInteger hookedCount = 0;
    for (int index = 0; index < classCount; index++) {
        Class cls = classes[index];
        if (!JPDHasJiguangClassPrefix(class_getName(cls))) {
            continue;
        }

        // Instance methods live on the class and class methods on its
        // metaclass. This catches public JPUSHService setup APIs as well as
        // internal JCore collectors and transport/reporting entry points.
        hookedCount += JPDHookMethodsOnClass(cls);
        Class metaClass = object_getClass(cls);
        if (metaClass != Nil) {
            hookedCount += JPDHookMethodsOnClass(metaClass);
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

%ctor {
    @autoreleasepool {
        JPDInstallHooks();
    }
}
