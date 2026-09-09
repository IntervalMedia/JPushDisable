#import "JPDMethodNeutralizer.h"

#import <objc/message.h>
#include <stdint.h>
#include <stdlib.h>

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

static double JPDDisabledFloatingPoint(id self, SEL _cmd, ...) {
    (void)self;
    (void)_cmd;
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
    (void)self;
    (void)_cmd;

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

NSUInteger JPDNeutralizeMethodsDeclaredByClass(Class targetClass) {
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(targetClass, &methodCount);
    NSUInteger neutralizedCount = 0;

    for (unsigned int index = 0; index < methodCount; index++) {
        Method method = methods[index];
        SEL selector = method_getName(method);
        if (selector == @selector(methodSignatureForSelector:) ||
            selector == @selector(forwardInvocation:)) {
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

    class_replaceMethod(targetClass, @selector(methodSignatureForSelector:),
                        (IMP)JPDDisabledMethodSignature, "@@::");
    class_replaceMethod(targetClass, @selector(forwardInvocation:),
                        (IMP)JPDDisabledForwardInvocation, "v@:@");
    return neutralizedCount;
}
