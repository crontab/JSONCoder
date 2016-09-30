/*

	JSONCoder.m

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

#import "JSONCoder.h"

#import <objc/runtime.h>


typedef enum { kISODateTimeMs, kISODateTime, kISODate,
	kISOMax = kISODate } ISODateFormat;


@implementation NSDate (ISO8601)


static NSDateFormatter *ISO8601Formatter(ISODateFormat format)
{
	static NSDateFormatter *fmt[kISOMax + 1];
	if (!fmt[format])
	{
		fmt[format] = [NSDateFormatter new];
		fmt[format].locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
		fmt[format].timeZone = [[NSTimeZone alloc] initWithName:@"UTC"];
		switch (format)
		{
			case kISODateTimeMs: fmt[format].dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"; break;
			case kISODateTime: fmt[format].dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ"; break;
			case kISODate: fmt[format].dateFormat = @"yyyy-MM-dd"; break;
		}
	}
	return fmt[format];
}


- (NSString *)toISO8601DateTimeString
	{ return [ISO8601Formatter(kISODateTime) stringFromDate:self]; }


- (NSString *)toISO8601DateString
	{ return [ISO8601Formatter(kISODate) stringFromDate:self]; }


+ (NSDate *)fromISO8601String:(NSString *)string
{
	return [ISO8601Formatter(kISODateTimeMs) dateFromString:string] ?: [ISO8601Formatter(kISODateTime) dateFromString:string] ?: [ISO8601Formatter(kISODate) dateFromString:string];
}


@end



typedef enum { kTypeObject, kTypeArray, kTypeDict, kTypeString, kTypeNumeric, kTypeBoolean, kTypeDateTime, kTypeDate } PropertyType;


@interface JSONProperty : NSObject
- (id)initWithObjCProperty:(objc_property_t)property coderClass:(Class)coderClass;

- (id)toValueWithInstance:(JSONCoder*)coder options:(JSONCoderOptions)options;
- (void)fromValue:(id)value withInstance:(JSONCoder*)coder options:(JSONCoderOptions)options error:(NSError **)error;
@end


@implementation JSONProperty
{
#if DEBUG
	Class _coderClass; // for diagnostics messages
#endif
	Class _itemClass; // nested model or array item class
	PropertyType _type;

@public
	NSString *_name;
	BOOL _optional;
	BOOL _decodeOnly;
}


static NSString *toSnakeCase(NSString *s)
{
	static NSRegularExpression *regex;
	if (!regex)
		regex = [NSRegularExpression regularExpressionWithPattern:@"(?<=.)([A-Z]*)([A-Z])" options:0 error:nil];
	return [regex stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"$1_$2"].lowercaseString;
}


- (id)initWithObjCProperty:(objc_property_t)property coderClass:(Class)coderClass
{
	if (self = [super init])
	{
		const char *name = property_getName(property);
		_name = @(name);

#if DEBUG
		assert([coderClass isSubclassOfClass:JSONCoder.class]);
		_coderClass = coderClass;
		// NSLog(@"%s: %s", name, property_getAttributes(property));
#endif

		char *readonly = property_copyAttributeValue(property, "R");
		BOOL ignore = readonly != NULL;
		free(readonly);
		if (ignore)
			return nil;

		char *type = property_copyAttributeValue(property, "T");
		_optional = strstr(type, "<Optional>") != NULL || [coderClass propertyIsOptional:_name];
		_decodeOnly = strstr(type, "<DecodeOnly>") != NULL || [coderClass propertyIsDecodeOnly:_name];
		ignore = strstr(type, "<Ignore>") != NULL;

		if (ignore)
		{
			free(type);
			return nil;
		}

		// Class, e.g. T@"NSString<Optional>"
		if (type[0] == '@' && type[1] == '"')
		{
			const char *b = type + 2;
			const char *e = strpbrk(b, "\"<");
			Class cls = NSClassFromString([[NSString alloc] initWithBytes:b length:(e - b) encoding:NSUTF8StringEncoding]);
			if ([cls isSubclassOfClass:JSONCoder.class])
			{
				_type = kTypeObject;
				_itemClass = cls;
			}
			else if ([cls isSubclassOfClass:NSDate.class])
			{
				bool dateOnly = strstr(type, "<DateOnly>") != NULL;
				_type = dateOnly ? kTypeDate : kTypeDateTime;
			}
			else if ([cls isSubclassOfClass:NSArray.class])
			{
				_type = kTypeArray;
				_itemClass = [coderClass classForCollectionProperty:_name]; // no encoding/decoding if _itemClass is nil; simply assign the array as is in that case
			}
			else if ([cls isSubclassOfClass:NSDictionary.class])
			{
				_type = kTypeDict;
			}
			else if ([cls isSubclassOfClass:NSNumber.class])
			{
				_type = kTypeNumeric;
			}
			else if ([cls isSubclassOfClass:NSString.class])
			{
				_type = kTypeString;
			}
			else
				[self throwWithDescription:@"Unsupported type (%@)"];
		}

		// Non-object type, assume scalar and see if we can support it
		// c - char/BOOL, i - int, I - unsigned int, q - long, Q - unsigned long, f - float, d - double
		// Also on 64-bit hardware (?) B - BOOL
		else if (strchr("iIqQfd", type[0]))
		{
			_type = kTypeNumeric;
		}
		else if (type[0] == 'c' || type[0] == 'B')
		{
			_type = kTypeBoolean;
		}
		else
			[self throwWithDescription:@"Unsupported type (%@)"];

		free(type);
	}

	return self;
}


- (NSString *)fullName
#if DEBUG
	{ return [NSString stringWithFormat:@"%@.%@", NSStringFromClass(_coderClass), _name]; }
#else
	{ return [NSString stringWithFormat:@"<JSONCoder>.%@", _name]; }
#endif


- (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description
{
	NSString* descr = [NSString stringWithFormat:description, self.fullName];
#if DEBUG
	NSLog(@"JSONCoder error: %@", descr);
#endif
	return [NSError errorWithDomain:@"JSONCoder" code:code userInfo:@{NSLocalizedDescriptionKey: descr}];
}


- (void)throwWithDescription:(NSString *)description
	{ [NSException raise:@"JSONCoderPropertyError" format:description, self.fullName]; }


- (NSError *)errorTypeMismatch:(NSString *)expected
	{ return [self errorWithCode:1 description:[@"Type mismatch for %@: expecting " stringByAppendingString:expected]]; }


- (id)toValueWithInstance:(JSONCoder *)coder options:(JSONCoderOptions)options
{
	id value = [coder valueForKey:_name];

	switch (_type)
	{

	case kTypeObject:
		return [value toDictionaryWithOptions:options];

	case kTypeArray:
		if (_itemClass)
		{
			if (value)
			{
				NSMutableArray *a = [NSMutableArray new];
				for (id element in value)
					[a addObject:[element toDictionaryWithOptions:options]];
				return a;
			}
			else
				return nil;
		}
		else
			return value;

	case kTypeDict:
		return value;

	case kTypeDateTime:
		return [value toISO8601DateTimeString];

	case kTypeDate:
		return [value toISO8601DateString];

	case kTypeBoolean:
		return [value boolValue] ? @(YES) : @(NO);

	case kTypeString:
	case kTypeNumeric:
		return value;

	}

	assert(0);
}


- (void)fromValue:(id)value withInstance:(JSONCoder*)coder options:(JSONCoderOptions)options error:(NSError *__autoreleasing*)error
{
	// TODO: in case of NSNull the value should be set to its default: 0 or nil depending on the type
	if (!value || [value isKindOfClass:NSNull.class])
		return;

	switch (_type)
	{

	case kTypeObject:
		if ([value isKindOfClass:NSDictionary.class])
			value = [_itemClass fromDictionary:value options:options error:error];
		else if (error)
			*error = [self errorTypeMismatch:@"nested object"];
		break;

	case kTypeArray:
		if ([value isKindOfClass:NSArray.class])
		{
			if (_itemClass) // transform if item class is known
				value = [_itemClass fromArrayOfDictionaries:value options:options error:error];
		}
		else if (error)
			*error = [self errorTypeMismatch:@"array of objects"];
		break;

	case kTypeDict:
		if (error && ![value isKindOfClass:NSDictionary.class])
			*error = [self errorTypeMismatch:@"dictionary"];
		break;

	case kTypeString:
		if (error && ![value isKindOfClass:NSString.class])
			*error = [self errorTypeMismatch:@"string"];
		break;

	case kTypeNumeric:
	case kTypeBoolean:
		if (error && ![value isKindOfClass:NSNumber.class])
			*error = [self errorTypeMismatch:(_type == kTypeBoolean ? @"boolean" : @"numeric")];
		break;

	case kTypeDateTime:
	case kTypeDate:
		if ([value isKindOfClass:NSString.class])
		{
			value = [NSDate fromISO8601String:value];
			if (!value && error)
				*error = [self errorWithCode:3 description:@"Invalid date string (%@)"];
		}
		else if (error)
			*error = [self errorTypeMismatch:@"date string"];
		break;

	}

	if (!value || (error && *error))
		return;

	[coder setValue:value forKey:_name];
}


@end



@interface JSONCoderMaps : NSObject
@property (nonatomic) NSMutableDictionary <NSString *, JSONProperty *> *camelCaseMap;
@property (nonatomic) NSMutableDictionary <NSString *, JSONProperty *> *snakeCaseMap;
@end


@implementation JSONCoderMaps
@end



@interface JSONCoder ()
@property (class) JSONCoderMaps *JSONMaps;
@end


@implementation JSONCoder


static JSONCoderOptions _globalEncoderOptions = kJSONSnakeCase;
static JSONCoderOptions _globalDecoderOptions = kJSONSnakeCase;


+ (JSONCoderOptions)globalEncoderOptions						{ return _globalEncoderOptions; }
+ (void)setGlobalEncoderOptions:(JSONCoderOptions)options		{ _globalEncoderOptions = options; }
+ (JSONCoderOptions)globalDecoderOptions						{ return _globalDecoderOptions; }
+ (void)setGlobalDecoderOptions:(JSONCoderOptions)options		{ _globalDecoderOptions = options; }


+ (JSONCoderOptions)encoderOptions								{ return _globalEncoderOptions; }
+ (JSONCoderOptions)decoderOptions								{ return _globalDecoderOptions; }


+ (Class)classForCollectionProperty:(NSString *)propertyName
	{ return nil; }


+ (BOOL)propertyIsOptional:(NSString *)propertyName
	{ return NO; }


+ (BOOL)propertyIsDecodeOnly:(NSString *)propertyName
	{ return NO; }


+ (JSONCoderMaps *)JSONMaps
{
	JSONCoderMaps *maps = objc_getAssociatedObject(self, @selector(JSONMaps));
	if (!maps)
	{
		maps = [JSONCoderMaps new];
		maps.camelCaseMap = [NSMutableDictionary new];
		maps.snakeCaseMap = [NSMutableDictionary new];
		Class cls = self;
		while (cls != JSONCoder.class)
		{
			unsigned propertyCount;
			objc_property_t *properties = class_copyPropertyList(cls, &propertyCount);
			for (unsigned i = 0; i < propertyCount; i++)
			{
				JSONProperty *prop = [[JSONProperty alloc] initWithObjCProperty:properties[i] coderClass:self];
				if (prop)
				{
					NSString *camelCaseName = ([prop->_name hasPrefix:@"$"]) ? [prop->_name substringFromIndex:1] : prop->_name;
					maps.camelCaseMap[camelCaseName] = prop;
					NSString *snakeCaseName = toSnakeCase(camelCaseName);
					maps.snakeCaseMap[snakeCaseName] = prop;
				}
			}
			free(properties);
			cls = cls.superclass;
		}
		self.JSONMaps = maps;
	}
	return maps;
}


+ (void)setJSONMaps:(JSONCoderMaps *)maps
	{ objc_setAssociatedObject(self, @selector(JSONMaps), maps, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }


+ (NSDictionary <NSString *, JSONProperty *> *)mapWithOptions:(JSONCoderOptions)options
{
	JSONCoderMaps *maps = [self.class JSONMaps];
	return (options & kJSONSnakeCase) ? maps.snakeCaseMap : maps.camelCaseMap;
}


+ (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description
	{ return [NSError errorWithDomain:@"JSONCoder" code:code userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:description, NSStringFromClass(self)]}]; }


- (NSDictionary *)toDictionary
	{ return [self toDictionaryWithOptions:kJSONUseClassOptions]; }


- (NSDictionary *)toDictionaryWithOptions:(JSONCoderOptions)options
{
	if (options == kJSONUseClassOptions)
		options = self.class.encoderOptions;

	NSDictionary <NSString *, JSONProperty *> *map = [self.class mapWithOptions:options];

	NSMutableDictionary *result = [NSMutableDictionary new];
	for (NSString *key in map)
	{
		JSONProperty *prop = map[key];
		if ((options & kJSONClone) || !prop->_decodeOnly)
		{
			id value = [prop toValueWithInstance:self options:options];
			if (value)
				result[key] = value;
		}
	}

	return result;
}


- (NSData *)toJSONData
	{ return [self toJSONDataWithOptions:kJSONUseClassOptions]; }


- (NSData *)toJSONDataWithOptions:(JSONCoderOptions)options
{
	NSDictionary *dict = [self toDictionaryWithOptions:options];
#if DEBUG
	NSJSONWritingOptions jsonOpts = NSJSONWritingPrettyPrinted;
#else
	NSJSONWritingOptions jsonOpts = 0;
#endif
	return dict ? [NSJSONSerialization dataWithJSONObject:dict options:jsonOpts error:nil] : nil;
}


- (NSString *)toJSONString
	{ return [self toJSONStringWithOptions:kJSONUseClassOptions]; }


- (NSString *)toJSONStringWithOptions:(JSONCoderOptions)options
{
	NSData* data = [self toJSONDataWithOptions:options];
	return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}


+ (instancetype)fromDictionary:(NSDictionary *)dict
	{ return [self fromDictionary:dict options:kJSONUseClassOptions error:nil]; }


+ (instancetype)fromDictionary:(NSDictionary *)dict options:(JSONCoderOptions)options error:(NSError *__autoreleasing*)error
{
	if (!dict)
		return nil;

	if (options == kJSONUseClassOptions)
		options = self.decoderOptions;

	NSError *localError = nil;
	JSONCoder *result = [self new];

	NSDictionary <NSString *, JSONProperty *> *map = [self.class mapWithOptions:options];

	for (NSString *key in map)
	{
		JSONProperty *prop = map[key];
		if (prop)
		{
			id value = dict[key];
			if (value || prop->_optional || (options & kJSONClone))
				[prop fromValue:value withInstance:result options:options error:&localError];
			else
				localError = [prop errorWithCode:5 description:@"%@ is required"];
			if (localError)
				break;
		}
	}

	if (localError)
	{
		if (error)
			*error = localError;
		return nil;
	}

	return result;
}


+ (NSArray *)fromArrayOfDictionaries:(NSArray *)array options:(JSONCoderOptions)options error:(NSError *__autoreleasing*)error
{
	if (!array)
		return nil;

	NSMutableArray <JSONCoder *> *result = [NSMutableArray new];
	for (id element in array)
	{
		if ([element isKindOfClass:NSDictionary.class])
		{
			id object = [self fromDictionary:element options:options error:error];
			if (object)
				[result addObject:object];
			if (error && *error)
				return nil;
		}
		else
		{
			if (error)
				*error = [self errorWithCode:1 description:@"Type mismatch for array of %@, expecting dictionary element"];
			return nil;
		}
	}
	return result;
}


+ (instancetype)fromJSONData:(NSData *)data
	{ return [self fromJSONData:data options:kJSONUseClassOptions error:nil]; }


+ (instancetype)fromJSONData:(NSData *)data options:(JSONCoderOptions)options error:(NSError *__autoreleasing*)error
{
	id result = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:error] : nil;
	if (!result)
		return nil;

	if (![result isKindOfClass:NSDictionary.class])
	{
		if (error)
			*error = [self errorWithCode:1 description:@"Type mismatch for root element %@, expecting dictionary"];
		return nil;
	}

	return [self fromDictionary:result options:options error:error];
}


+ (instancetype)fromJSONString:(NSString *)jsonString
	{ return [self fromJSONString:jsonString options:kJSONUseClassOptions error:nil]; }


+ (instancetype)fromJSONString:(NSString *)jsonString options:(JSONCoderOptions)options error:(NSError *__autoreleasing*)error
	{ return [self fromJSONData:[jsonString dataUsingEncoding:NSUTF8StringEncoding] options:options error:error]; }


- (instancetype)clone
	{ return [self.class fromDictionary:[self toDictionaryWithOptions:(kJSONNoMapping | kJSONClone)] options:(kJSONNoMapping | kJSONClone) error:nil]; }


@end

