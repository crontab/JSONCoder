//
//  JSONCoder.h
//  Jsonic
//
//  Created by Hovik Melikyan on 24/08/2016.
//  Copyright © 2016 Hovik Melikyan. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef enum {
		kJSONUseClassOptions,
		kJSONSnakeCase,
		kJSONCamelCase,
	} JSONCoderOptions;


@interface JSONCoder : NSObject

// Global options that affect all classes by default
+ (void)setGlobalEncoderOptions:(JSONCoderOptions)options; // to JSON
+ (void)setGlobalDecoderOptions:(JSONCoderOptions)options; // from JSON

// These can be overridden in your subclasses; by default they return the global options
+ (JSONCoderOptions)encoderOptions;
+ (JSONCoderOptions)decoderOptions;

// This is compatible with JSONModel
+ (Class)classForCollectionProperty:(NSString *)propertyName;

- (NSDictionary *)toDictionary;
- (NSDictionary *)toDictionaryWithOptions:(JSONCoderOptions)options error:(NSError **)error; // currently no errors are returned

- (NSData *)toJSON;
- (NSData *)toJSONWithOptions:(JSONCoderOptions)options error:(NSError **)error;

- (NSString *)toJSONString;
- (NSString *)toJSONStringWithOptions:(JSONCoderOptions)options error:(NSError **)error;

+ (instancetype)fromDictionary:(NSDictionary *)dict;
+ (instancetype)fromDictionary:(NSDictionary *)dict options:(JSONCoderOptions)options error:(NSError **)error;
+ (NSArray *)fromArrayOfDictionaries:(NSArray *)array options:(JSONCoderOptions)options error:(NSError **)error;

+ (instancetype)fromData:(NSData *)data;
+ (instancetype)fromData:(NSData *)data options:(JSONCoderOptions)options error:(NSError **)error;

+ (instancetype)fromString:(NSString *)jsonString;
+ (instancetype)fromString:(NSString *)jsonString options:(JSONCoderOptions)options error:(NSError **)error;

@end


@protocol Ignore
@end


@protocol Optional
@end

