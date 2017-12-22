/*

	JSONCoder.h

	Copyright (c) 2016 Hovik Melikyan

	Permission is hereby granted, free of charge, to any person obtaining a copy of
	this software and associated documentation files (the "Software"), to deal in
	the Software without restriction, including without limitation the rights to
	use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
	the Software, and to permit persons to whom the Software is furnished to do so,
	subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
	FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
	COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
	IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
	CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

/*

    class JSONCoder

	Provides conversion of Objective-C objects to and from JSON, optionally with property name conversion to and from the "snake case" (underscore case).

	How to use: derive your class from JSONCoder, declare properties you want to be present in JSON, then use the fromXXX family of class methods for instantiating objects from JSON, or the toXXX family of methods for encoding your objects to JSON.

	Only read-write properties are included in JSON encoding/decoding. To exclude a read-write property, mark its type with the <Ignore> protocol. Everything else, i.e. read-only properties, methods, constructors, etc. are ignored by the converter.

	Data types allowed in encodable properties are:
		
		- NSString
		- NSNumber
		- NSDate, optionally with <DateOnly> protocol; these are converted to and from ISO8601 time stamps
		- Object types derived from JSONCoder
		- NSArray of any of the above; the array item type can be specified by overriding the classForCollectionProperty method, though this is not required for NSString and NSNumber element types
		- NSDictionary with the following element types: NSString, NSNumber, also nested arrays and dictionaries of the same
		- Primitive scalar types such as int, BOOL, float

	All proprties are required to be present in JSON data when decoding from JSON, unless a property is makred with the <Optional> protocol. For scalar properties, because there is no way of attaching protocols to them, use the propertyIsOptional method instead.
		
	When encoding to JSON, properties with the value of nil are not included in the resulting JSON string; scalar types are always included regardless of their value.

	NSNumber and the scalar types are all mutually convertible; an attempt to convert between any other types listed above during decoding results in error.

	A property name can start with the dollar sign ($) in case of keyword or other naming conflicts. For example, a property named `description` or `class` can be disambiguated by declaring them as `$description` and `$class`. Such properties are mapped to JSON names without the `$` prefix.

	The fromDictionary and toDictionary family of methods are used internally as an intermediate step between JSON and Objective-C objects, but are also exposed in the public interface.

*/


#import <Foundation/Foundation.h>


typedef enum
	{
		kJSONUseClassOptions = 0,	// Fall back to class default if overridden, otherwise global default
		kJSONSnakeCase = 1,			// Convert property names to underscore format, this is the global default on start up
		kJSONNoMapping = 2,			// Do not convert property names
		kJSONClone = 4,				// Internal, used in the clone method; relaxes all requirements so that clone always works
	}
	JSONCoderOptions;


@protocol JSONable
- (NSDictionary *)toDictionary;
+ (instancetype)fromDictionary:(NSDictionary *)dict;
@end


@interface JSONCoder : NSObject <JSONable>

// Global options that affect all classes by default
@property (class) JSONCoderOptions globalEncoderOptions; // to JSON
@property (class) JSONCoderOptions globalDecoderOptions; // from JSON

// These can be overridden in your subclasses; by default they return the global options
+ (JSONCoderOptions)encoderOptions;
+ (JSONCoderOptions)decoderOptions;

- (NSDictionary *)toDictionary;
- (NSDictionary *)toDictionaryWithOptions:(JSONCoderOptions)options;

- (NSData *)toJSONData;
- (NSData *)toJSONDataWithOptions:(JSONCoderOptions)options;

- (NSString *)toJSONString;
- (NSString *)toJSONStringWithOptions:(JSONCoderOptions)options;

+ (instancetype)fromDictionary:(NSDictionary *)dict;
+ (instancetype)fromDictionary:(NSDictionary *)dict options:(JSONCoderOptions)options error:(NSError **)error;
+ (NSArray *)fromArrayOfDictionaries:(NSArray *)array;
+ (NSArray *)fromArrayOfDictionaries:(NSArray *)array options:(JSONCoderOptions)options error:(NSError **)error;

+ (instancetype)fromJSONData:(NSData *)data;
+ (instancetype)fromJSONData:(NSData *)data options:(JSONCoderOptions)options error:(NSError **)error;

+ (instancetype)fromJSONString:(NSString *)jsonString;
+ (instancetype)fromJSONString:(NSString *)jsonString options:(JSONCoderOptions)options error:(NSError **)error;

+ (Class)classForCollectionProperty:(NSString *)propertyName;
+ (BOOL)propertyIsOptional:(NSString *)propertyName;

- (instancetype)clone; // Deep copy of all encodable properties; assumes that all NSString, NSArray and NSDictionary properties are immutable, i.e. copying of pointers is enough

- (instancetype)diff:(JSONCoder *)other; // An object with only fields that are different from other's, i.e. a diff of two objects; returns nil if they are equal

@end


@protocol Ignore
@end


@protocol Optional // not required when converting from JSON
@end


// By default NSDate is encoded as a full ISO8601 string; use DateOnly to encode as YYYY-MM-DD
@protocol DateOnly
@end


// Prevent compiler warnings when assigning to and from properties with JSON protocols
@interface NSObject (JSONCoderPropertyCompatibility) <Optional, Ignore, DateOnly>
@end


@interface NSDate (ISO8601)
- (NSString *)toISO8601DateTimeString;
- (NSString *)toISO8601DateString;
+ (NSDate *)fromISO8601String:(NSString *)string;
@end

