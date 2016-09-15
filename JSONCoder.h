//
//  JSONCoder.h
//
//  Created by Hovik Melikyan on 24/08/2016.
//  Copyright © 2016 Hovik Melikyan. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef enum
	{
		kJSONUseClassOptions,	// fall back to class default if overridden, otherwise global default
		kJSONSnakeCase,			// this is the global default at startup
		kJSONCamelCase,
	}
	JSONCoderOptions;


@interface JSONCoder : NSObject

// Global options that affect all classes by default
@property (class) JSONCoderOptions globalEncoderOptions; // to JSON
@property (class) JSONCoderOptions globalDecoderOptions; // from JSON

// These can be overridden in your subclasses; by default they return the global options
@property (class, readonly) JSONCoderOptions encoderOptions;
@property (class, readonly) JSONCoderOptions decoderOptions;

- (NSDictionary *)toDictionary;
- (NSDictionary *)toDictionaryWithOptions:(JSONCoderOptions)options error:(NSError **)error; // currently no errors are returned

- (NSData *)toJSONData;
- (NSData *)toJSONDataWithOptions:(JSONCoderOptions)options error:(NSError **)error;

- (NSString *)toJSONString;
- (NSString *)toJSONStringWithOptions:(JSONCoderOptions)options error:(NSError **)error;

+ (instancetype)fromDictionary:(NSDictionary *)dict;
+ (instancetype)fromDictionary:(NSDictionary *)dict options:(JSONCoderOptions)options error:(NSError **)error;
+ (NSArray *)fromArrayOfDictionaries:(NSArray *)array options:(JSONCoderOptions)options error:(NSError **)error;

+ (instancetype)fromData:(NSData *)data;
+ (instancetype)fromData:(NSData *)data options:(JSONCoderOptions)options error:(NSError **)error;

+ (instancetype)fromJSONString:(NSString *)jsonString;
+ (instancetype)fromJSONString:(NSString *)jsonString options:(JSONCoderOptions)options error:(NSError **)error;

// These are compatible with JSONModel
+ (Class)classForCollectionProperty:(NSString *)propertyName;
+ (BOOL)propertyIsOptional:(NSString *)propertyName;

@end


@protocol Ignore
@end


@protocol Optional
@end


// By default NSDate is encoded as a full ISO8601 string; use DateOnly to encode as YYYY-MM-DD
@protocol DateOnly
@end


// Prevent compiler warnings when assigning to and from properties with JSON protocols
@interface NSObject (JSONCoderPropertyCompatibility) <Optional, Ignore, DateOnly>
@end
