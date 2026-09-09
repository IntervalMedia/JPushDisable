#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "JPDMethodNeutralizer.h"

typedef struct {
    uintptr_t integerValue;
    double floatingValue;
} JPDAggregateValue;

static NSUInteger executionCount = 0;

@interface JPDNeutralizerFixture : NSObject
+ (NSInteger)classOperation;
- (void)voidOperation;
- (id)objectOperation;
- (NSUInteger)integerOperation;
- (double)floatingOperation;
- (JPDAggregateValue)aggregateOperation;
@end

@implementation JPDNeutralizerFixture

+ (NSInteger)classOperation {
    executionCount++;
    return 41;
}

- (void)voidOperation {
    executionCount++;
}

- (id)objectOperation {
    executionCount++;
    return @"active";
}

- (NSUInteger)integerOperation {
    executionCount++;
    return 42;
}

- (double)floatingOperation {
    executionCount++;
    return 43.0;
}

- (JPDAggregateValue)aggregateOperation {
    executionCount++;
    return (JPDAggregateValue){44, 45.0};
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    executionCount++;
    return [super methodSignatureForSelector:selector];
}

@end

int main(void) {
    @autoreleasepool {
        JPDNeutralizeMethodsDeclaredByClass(JPDNeutralizerFixture.class);
        JPDNeutralizeMethodsDeclaredByClass(object_getClass(JPDNeutralizerFixture.class));

        JPDNeutralizerFixture *fixture = [JPDNeutralizerFixture new];
        [fixture voidOperation];
        if ([JPDNeutralizerFixture classOperation] != 0 ||
            [fixture objectOperation] != nil ||
            [fixture integerOperation] != 0 ||
            [fixture floatingOperation] != 0.0) {
            return 1;
        }

        JPDAggregateValue aggregate = [fixture aggregateOperation];
        if (aggregate.integerValue != 0 || aggregate.floatingValue != 0.0) {
            return 2;
        }

        return executionCount == 0 ? 0 : 3;
    }
}
