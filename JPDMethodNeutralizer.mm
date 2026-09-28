#import "JPDMethodNeutralizer.h"

#import <objc/message.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifndef JPD_TRACE_BLOCKED_CALLS
#define JPD_TRACE_BLOCKED_CALLS 0
#endif

#ifndef JPD_TRACE_BLOCKED_CALL_LIMIT
#define JPD_TRACE_BLOCKED_CALL_LIMIT 100
#endif

#if JPD_TRACE_BLOCKED_CALLS
static NSMutableSet<NSString *> *JPDSeenBlockedCalls(void) {
    static NSMutableSet<NSString *> *seenCalls;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        seenCalls = [NSMutableSet set];
    });
    return seenCalls;
}

static void JPDRecordBlockedCall(id receiver, SEL selector) {
    Class dispatchClass = object_getClass(receiver);
    BOOL isClassMethod = dispatchClass != Nil && class_isMetaClass(dispatchClass);
    Class receiverClass = isClassMethod ? (Class)receiver : dispatchClass;
    const char *className = receiverClass == Nil ? "<unknown>"
                                                 : class_getName(receiverClass);
    NSString *callName = [NSString
        stringWithFormat:@"%c[%s %s]", isClassMethod ? '+' : '-', className,
                         sel_getName(selector)];

    NSMutableSet<NSString *> *seenCalls = JPDSeenBlockedCalls();
    BOOL shouldLog = NO;
    BOOL reachedLimit = NO;
    @synchronized (seenCalls) {
        if (![seenCalls containsObject:callName]) {
            if (seenCalls.count < JPD_TRACE_BLOCKED_CALL_LIMIT) {
                [seenCalls addObject:callName];
                shouldLog = YES;
            } else if (seenCalls.count == JPD_TRACE_BLOCKED_CALL_LIMIT) {
                [seenCalls addObject:@"<limit-reported>"];
                reachedLimit = YES;
            }
        }
    }

    if (shouldLog) {
        NSLog(@"[JPushDisable][runtime-test] Blocked %@", callName);
    } else if (reachedLimit) {
        NSLog(@"[JPushDisable][runtime-test] Unique-call limit reached; further calls suppressed");
    }
}
#else
static inline void JPDRecordBlockedCall(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
}
#endif

static void JPDDisabledVoid(id self, SEL _cmd, ...) {
    JPDRecordBlockedCall(self, _cmd);
}

static id JPDDisabledObject(id self, SEL _cmd, ...) {
    JPDRecordBlockedCall(self, _cmd);
    return nil;
}

static uintptr_t JPDDisabledInteger(id self, SEL _cmd, ...) {
    JPDRecordBlockedCall(self, _cmd);
    return 0;
}

static double JPDDisabledFloatingPoint(id self, SEL _cmd, ...) {
    JPDRecordBlockedCall(self, _cmd);
    return 0.0;
}

static NSMethodSignature *JPDDisabledMethodSignature(id self, SEL _cmd,
                                                      SEL selector) {
    (void)_cmd;
    Class dispatchClass = object_getClass(self);
    Method method = class_getInstanceMethod(dispatchClass, selector);
    const char *typeEncoding = method == NULL ? NULL : method_getTypeEncoding(method);
    return typeEncoding == NULL
        ? nil
        : [NSMethodSignature signatureWithObjCTypes:typeEncoding];
}

static void JPDDisabledForwardInvocation(id self, SEL _cmd,
                                         NSInvocation *invocation) {
    (void)_cmd;
    JPDRecordBlockedCall(self, invocation.selector);

    NSUInteger returnLength = invocation.methodSignature.methodReturnLength;
    if (returnLength == 0) {
        return;
    }

    void *zeroValue = calloc(1, returnLength);
    if (zeroValue != NULL) {
        [invocation setReturnValue:zeroValue];
        free(zeroValue);
    }
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

// The blacklist must not break NSObject's construction and runtime contract.
// Jiguang objects are still allowed to be allocated, initialized, copied,
// queried, and released; their SDK operations remain neutralized below.
static BOOL JPDShouldPreserveSelector(SEL selector) {
    const char *name = sel_getName(selector);
    if (name == NULL) {
        return NO;
    }

    if (strcmp(name, "init") == 0 || strncmp(name, "initWith", 8) == 0 ||
        strcmp(name, "new") == 0 || strcmp(name, "alloc") == 0 ||
        strcmp(name, "allocWithZone:") == 0 || strcmp(name, "dealloc") == 0 ||
        strcmp(name, "copyWithZone:") == 0 ||
        strcmp(name, "mutableCopyWithZone:") == 0) {
        return YES;
    }

    if (strcmp(name, "class") == 0 || strcmp(name, "superclass") == 0 ||
        strcmp(name, "self") == 0 || strcmp(name, "zone") == 0 ||
        strcmp(name, "isKindOfClass:") == 0 ||
        strcmp(name, "isMemberOfClass:") == 0 ||
        strcmp(name, "conformsToProtocol:") == 0 ||
        strcmp(name, "respondsToSelector:") == 0 ||
        strcmp(name, "isEqual:") == 0 || strcmp(name, "hash") == 0 ||
        strcmp(name, "description") == 0 ||
        strcmp(name, "debugDescription") == 0 ||
        strcmp(name, "isProxy") == 0 || strcmp(name, "retain") == 0 ||
        strcmp(name, "release") == 0 || strcmp(name, "autorelease") == 0 ||
        strcmp(name, "retainCount") == 0 ||
        strcmp(name, "allowsWeakReference") == 0 ||
        strcmp(name, "retainWeakReference") == 0) {
        return YES;
    }

    // These are common JCore singleton entry points. Returning the real
    // singleton keeps dependent application code alive; methods invoked on it
    // are still neutralized unless they are themselves runtime plumbing.
    return strcmp(name, "sharedInstance") == 0 ||
           strcmp(name, "sharedManager") == 0 ||
           strcmp(name, "defaultManager") == 0 ||
           strcmp(name, "defaultService") == 0 ||
           strcmp(name, "service") == 0 || strcmp(name, "instance") == 0;
}

static BOOL JPDHasPrefix(const char *name, const char *prefix) {
    return strncmp(name, prefix, strlen(prefix)) == 0;
}

static BOOL JPDShouldNeutralizeSelector(SEL selector) {
    const char *name = sel_getName(selector);
    if (name == NULL || JPDShouldPreserveSelector(selector)) {
        return NO;
    }

    // High-confidence SDK actions. Property accessors and data-model methods
    // are deliberately left alone so internal launch configuration survives.
    static const char *const prefixes[] = {
        "setup",       "commonSetup",  "registerFor", "registerDevice",
        "unregister",  "report",       "send",        "upload",
        "collect",     "track",        "connect",     "disconnect",
        "login",       "logout",       "push",        "handleRemote",
        "turnOn",      "turnOff",      "addNotification",
        "removeNotification",          "findNotification",
        "startNetwork", "stopNetwork", "openConnection", "closeConnection",
    };
    for (size_t index = 0; index < sizeof(prefixes) / sizeof(prefixes[0]);
         index++) {
        if (JPDHasPrefix(name, prefixes[index])) {
            return YES;
        }
    }

    // These public JPush mutators are action APIs, unlike ordinary model
    // setters used during object construction.
    return JPDHasPrefix(name, "setTags") || JPDHasPrefix(name, "setAlias") ||
           JPDHasPrefix(name, "setBadge");
}

static IMP JPDReplacementForMethod(Method method) {
    switch (JPDReturnTypeForMethod(method)) {
        case 'v':
            return (IMP)JPDDisabledVoid;
        case '@':
        case '#':
            return (IMP)JPDDisabledObject;
        case 'f':
        case 'd':
        case 'D':
            return (IMP)JPDDisabledFloatingPoint;
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
        case ':':
        case '*':
            return (IMP)JPDDisabledInteger;
        default:
            return (IMP)_objc_msgForward;
    }
}

NSUInteger JPDNeutralizeMethodsDeclaredByClass(Class targetClass, BOOL selective) {
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(targetClass, &methodCount);
    NSUInteger neutralizedCount = 0;

    for (unsigned int index = 0; index < methodCount; index++) {
        Method method = methods[index];
        SEL selector = method_getName(method);
        if (JPDShouldPreserveSelector(selector) ||
            selector == @selector(methodSignatureForSelector:) ||
            selector == @selector(forwardInvocation:) ||
            (selective && !JPDShouldNeutralizeSelector(selector))) {
            continue;
        }

        IMP replacement = JPDReplacementForMethod(method);
        if (method_getImplementation(method) == replacement) {
            continue;
        }
        method_setImplementation(method, replacement);
        neutralizedCount++;
    }

    free(methods);

    if (neutralizedCount > 0) {
        class_replaceMethod(targetClass, @selector(methodSignatureForSelector:),
                            (IMP)JPDDisabledMethodSignature, "@@::");
        class_replaceMethod(targetClass, @selector(forwardInvocation:),
                            (IMP)JPDDisabledForwardInvocation, "v@:@");
    }
    return neutralizedCount;
}
