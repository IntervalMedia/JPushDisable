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
- (instancetype)init;
- (void)voidOperation;
- (id)objectOperation;
- (NSUInteger)integerOperation;
- (double)floatingOperation;
- (JPDAggregateValue)aggregateOperation;
@end

@implementation JPDNeutralizerFixture

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        executionCount++;
    }
    return self;
}

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
    return [super methodSignatureForSelector:selector];
}

@end

int main(void) {
    @autoreleasepool {
        JPDNeutralizeMethodsDeclaredByClass(JPDNeutralizerFixture.class);
        JPDNeutralizeMethodsDeclaredByClass(object_getClass(JPDNeutralizerFixture.class));

        JPDNeutralizerFixture *fixture = [JPDNeutralizerFixture new];
        if (fixture == nil || executionCount != 1) {
            return 4;
        }
        NSUInteger executionCountAfterInit = executionCount;
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

        return executionCount == executionCountAfterInit ? 0 : 3;
    }
}
