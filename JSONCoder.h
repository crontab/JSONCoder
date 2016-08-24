//
//  JSONCoder.h
//  Jsonic
//
//  Created by Hovik Melikyan on 24/08/2016.
//  Copyright © 2016 Hovik Melikyan. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef enum {
		kJSONSnakeCase = 0x01, // JSON data is snake case, will be converted to and from camelCase; otherwise keys will not be transformed with the exception of the $ removal
		kJSONExceptions = 0x02, // Throw NSException instead of returning NSError; otherwise if the error argument is nil then errors are effectively ignored
		kJSONUseClassOptions = -1,
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

+ (instancetype)fromDictionary:(NSDictionary *)dict;
+ (instancetype)fromDictionary:(NSDictionary *)dict options:(JSONCoderOptions)options error:(NSError **)error;

+ (NSArray *)arrayFromRawArray:(NSArray *)array options:(JSONCoderOptions)options error:(NSError **)error;

@end


@protocol Ignore
@end


@protocol Optional
@end

