//
//  JSONCoder.m
//
//  Created by Hovik Melikyan on 24/08/2016.
//  Copyright © 2016 Hovik Melikyan. All rights reserved.
//

#import "JSONCoder.h"

#import <objc/runtime.h>


typedef enum { kISODateTimeMs, kISODateTime, kISODate,
	kISOMax = kISODate } ISODateFormat;


@interface NSDate (ISO8601)
- (NSString *)toISO8601DateTimeString;
- (NSString *)toISO8601DateString;
+ (NSDate *)fromISO8601String:(NSString *)string;
@end


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



typedef enum { kTypeObject, kTypeArray, kTypeString, kTypeNumeric, kTypeDateTime, kTypeDate } PropertyType;


@interface JSONProperty : NSObject
- (id)initWithObjCProperty:(objc_property_t)property coderClass:(Class)coderClass;

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) BOOL optional;

- (id)toValueWithInstance:(JSONCoder*)coder options:(JSONCoderOptions)options error:(NSError **)error;
- (void)fromValue:(id)value withInstance:(JSONCoder*)coder options:(JSONCoderOptions)options error:(NSError **)error;
@end


@implementation JSONProperty
{
#if DEBUG
	Class _coderClass; // for diagnostics messages
#endif
	Class _itemClass; // nested model or array item class
	PropertyType _type;
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
			else if ([cls isSubclassOfClass:NSNumber.class])
			{
				_type = kTypeNumeric;
			}
			else if ([cls isSubclassOfClass:NSString.class])
			{
				_type = kTypeString;
			}
			else
				[self errorWithCode:2 description:@"Unsupported type (%@)"];
		}

		// Non-object type, assume scalar and see if we can support it
		// c - char/BOOL, i - int, I - unsigned int, q - long, Q - unsigned long, f - float, d - double
		else if (strchr("ciIqQfd", type[0]))
		{
			_type = kTypeNumeric;
		}
		else
			[self errorWithCode:2 description:@"Unsupported type (%@)"];

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
	{ return [NSError errorWithDomain:@"JSONCoder" code:code userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:description, self.fullName]}]; }


- (NSError *)errorTypeMismatch:(NSString *)expected
	{ return [self errorWithCode:1 description:[@"Type mismatch for %@: expecting " stringByAppendingString:expected]]; }


- (id)toValueWithInstance:(JSONCoder *)coder options:(JSONCoderOptions)options error:(NSError *__autoreleasing*)error
{
	id value = [coder valueForKey:_name];

	switch (_type)
	{

	case kTypeObject:
		return [value toDictionaryWithOptions:options error:error];

	case kTypeArray:
		if (_itemClass)
		{
			if (value)
			{
				NSMutableArray *a = [NSMutableArray new];
				for (id element in value)
					[a addObject:[element toDictionaryWithOptions:options error:error]];
				return a;
			}
			else
				return nil;
		}
		else
			return value;

	case kTypeDateTime:
		return [value toISO8601DateTimeString];

	case kTypeDate:
		return [value toISO8601DateString];
		
	case kTypeString:
	case kTypeNumeric:
		return value;

	}

	assert(0);
}


- (void)fromValue:(id)value withInstance:(JSONCoder*)coder options:(JSONCoderOptions)options error:(NSError *__autoreleasing*)error
{
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

	case kTypeString:
		if (error && ![value isKindOfClass:NSString.class])
			*error = [self errorTypeMismatch:@"string"];
		break;

	case kTypeNumeric:
		if (error && ![value isKindOfClass:NSNumber.class])
			*error = [self errorTypeMismatch:@"numeric"];
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
					NSString *camelCaseName = ([prop.name hasPrefix:@"$"]) ? [prop.name substringFromIndex:1] : prop.name;
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
	{ return [self toDictionaryWithOptions:kJSONUseClassOptions error:nil]; }


- (NSDictionary *)toDictionaryWithOptions:(JSONCoderOptions)options error:(NSError *__autoreleasing*)error
{
	if (options == kJSONUseClassOptions)
		options = self.class.encoderOptions;

	NSError *localError = nil;

	NSDictionary <NSString *, JSONProperty *> *map = [self.class mapWithOptions:options];

	NSMutableDictionary *result = [NSMutableDictionary new];
	for (NSString *key in map)
	{
		JSONProperty *prop = map[key];
		id value = [prop toValueWithInstance:self options:options error:&localError];
		if (localError)
			break;
		if (value)
			result[key] = value;
		else if (!prop.optional)
		{
			localError = [prop errorWithCode:4 description:@"%@ is required"];
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


- (NSData *)toJSONData
	{ return [self toJSONDataWithOptions:kJSONUseClassOptions error:nil]; }


- (NSData *)toJSONDataWithOptions:(JSONCoderOptions)options error:(NSError *__autoreleasing*)error
{
	NSDictionary *dict = [self toDictionaryWithOptions:options error:error];
#if DEBUG
	NSJSONWritingOptions jsonOpts = NSJSONWritingPrettyPrinted;
#else
	NSJSONWritingOptions jsonOpts = 0;
#endif
	return dict ? [NSJSONSerialization dataWithJSONObject:dict options:jsonOpts error:error] : nil;
}


- (NSString *)toJSONString
	{ return [self toJSONStringWithOptions:kJSONUseClassOptions error:nil]; }


- (NSString *)toJSONStringWithOptions:(JSONCoderOptions)options error:(NSError *__autoreleasing*)error
{
	NSData* data = [self toJSONDataWithOptions:options error:error];
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
			if (!value && !prop.optional)
				localError = [prop errorWithCode:5 description:@"%@ is required"];
			else
				[prop fromValue:value withInstance:result options:options error:&localError];
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


+ (instancetype)fromData:(NSData *)data
	{ return [self fromData:data options:kJSONUseClassOptions error:nil]; }


+ (instancetype)fromData:(NSData *)data options:(JSONCoderOptions)options error:(NSError *__autoreleasing*)error
{
	id result = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
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
	{ return [self fromData:[jsonString dataUsingEncoding:NSUTF8StringEncoding] options:options error:error]; }


@end

