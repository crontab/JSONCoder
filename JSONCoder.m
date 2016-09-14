//
//  JSONCoder.m
//  Jsonic
//
//  Created by Hovik Melikyan on 24/08/2016.
//  Copyright © 2016 Hovik Melikyan. All rights reserved.
//

#import "JSONCoder.h"

#import <objc/runtime.h>


@interface JSONProperty : NSObject
- (id)initWithObjCProperty:(objc_property_t)property coderClass:(Class)coderClass;

@property (nonatomic, readonly) NSString* name;
@property (nonatomic, readonly) BOOL optional;

- (id)toValueWithInstance:(JSONCoder*)coder options:(JSONCoderOptions)options error:(NSError **)error;
- (void)fromValue:(id)value withInstance:(JSONCoder*)coder options:(JSONCoderOptions)options error:(NSError **)error;
@end


@implementation JSONProperty
{
	Class _coderClass; // for diagnostics messages
	Class _nestedJSONCoderClass;
	BOOL _isDate;
	Class _itemClass; // for array properties
}


static NSString* toSnakeCase(NSString* s)
{
	static NSRegularExpression *regex;
	if (!regex)
		regex = [NSRegularExpression regularExpressionWithPattern:@"(?<=.)([A-Z]*)([A-Z])" options:0 error:nil];
	return [regex stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"$1_$2"].lowercaseString;
}


static NSDateFormatter* ISO8601Formatter()
{
	static NSDateFormatter* fmt;
	if (!fmt)
	{
		// TODO: microseconds are optional
		fmt = [NSDateFormatter new];
		fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
		fmt.timeZone = [[NSTimeZone alloc] initWithName:@"UTC"];
		fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZ";
	}
	return fmt;
}


- (id)initWithObjCProperty:(objc_property_t)property coderClass:(Class)coderClass
{
	if (self = [super init])
	{
		_coderClass = coderClass;
		// NSLog(@"%s", property_getAttributes(property));
		const char* name = property_getName(property);
		_name = @(name);

		char* readonly = property_copyAttributeValue(property, "R");
		BOOL ignore = readonly != NULL;
		free(readonly);
		if (ignore)
			return nil;

		char* type = property_copyAttributeValue(property, "T");
		_optional = strstr(type, "<Optional>") != NULL;
		ignore = strstr(type, "<Ignore>") != NULL;
		if (!ignore && type[0] == '@' && type[1] == '"')
		{
			const char* b = type + 2;
			const char* e = strpbrk(b, "\"<");
			Class cls = NSClassFromString([[NSString alloc] initWithBytes:b length:(e - b) encoding:NSUTF8StringEncoding]);
			if ([cls isSubclassOfClass:JSONCoder.class])
				_nestedJSONCoderClass = cls;
			else if ([cls isSubclassOfClass:NSDate.class])
				_isDate = YES;
			else if ([cls isSubclassOfClass:NSArray.class])
				_itemClass = [coderClass classForCollectionProperty:_name];
		}
		free(type);
		if (ignore)
			return nil;
	}
	return self;
}


- (NSString *)fullName
	{ return [NSString stringWithFormat:@"%@.%@", NSStringFromClass(_coderClass), _name]; }


- (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description
	{ return [NSError errorWithDomain:@"JSONCoder" code:code userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:description, self.fullName]}]; }


- (NSError *)errorTypeMismatch:(NSString *)expected
	{ return [self errorWithCode:1 description:[@"JSONCoder type mismatch for %@: expecting " stringByAppendingString:expected]]; }


- (id)toValueWithInstance:(JSONCoder *)coder options:(JSONCoderOptions)options error:(NSError **)error
{
	id value = [coder valueForKey:_name];

	if (_nestedJSONCoderClass)
		return [value toDictionaryWithOptions:options error:error];

	else if (_isDate)
		return [ISO8601Formatter() stringFromDate:value];

	else if (_itemClass)
	{
		NSMutableArray *a = [NSMutableArray new];
		for (id element in value)
			[a addObject:[element toDictionaryWithOptions:options error:error]];
		return a;
	}

	else
		return value;
}


- (void)fromValue:(id)value withInstance:(JSONCoder*)coder options:(JSONCoderOptions)options error:(NSError **)error
{
	if (!value || [value isKindOfClass:NSNull.class])
		return;

	if (_nestedJSONCoderClass)
	{
		if ([value isKindOfClass:NSDictionary.class])
			value = [_nestedJSONCoderClass fromDictionary:value options:options error:error];
		else if (error)
			*error = [self errorTypeMismatch:@"nested object"];
	}

	else if (_isDate)
	{
		if ([value isKindOfClass:NSString.class])
		{
			value = [ISO8601Formatter() dateFromString:value];
			if (!value && error)
				*error = [self errorWithCode:2 description:@"Invalid date string"];
		}
		else if (error)
			*error = [self errorTypeMismatch:@"date string"];
	}

	else if (_itemClass)
	{
		if ([value isKindOfClass:NSArray.class])
			value = [_itemClass fromArrayOfDictionaries:value options:options error:error];
		else if (error)
			*error = [self errorTypeMismatch:@"array of objects"];
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
+ (JSONCoderMaps *)JSONMaps;
+ (void)setJSONMaps:(JSONCoderMaps *)maps;
@end


@implementation JSONCoder


static JSONCoderOptions _globalEncoderOptions;
static JSONCoderOptions _globalDecoderOptions;


+ (void)setGlobalEncoderOptions:(JSONCoderOptions)options
	{ _globalEncoderOptions = options; }


+ (void)setGlobalDecoderOptions:(JSONCoderOptions)options
	{ _globalDecoderOptions = options; }


+ (JSONCoderOptions)encoderOptions
	{ return _globalEncoderOptions; }


+ (JSONCoderOptions)decoderOptions
	{ return _globalDecoderOptions; }


+ (Class)classForCollectionProperty:(NSString *)propertyName
	{ return nil; }


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


- (NSDictionary *)toDictionaryWithOptions:(JSONCoderOptions)options error:(NSError **)error
{
	if (options == kJSONUseClassOptions)
		options = self.class.encoderOptions;
	NSError *localError = nil;

	NSDictionary <NSString *, JSONProperty *> *map = [self.class mapWithOptions:options];

	NSMutableDictionary *result = [NSMutableDictionary new];
	for (NSString *key in map)
	{
		id value = [map[key] toValueWithInstance:self options:options error:&localError];
		if (localError)
			break;
		if (value)
			result[key] = value;
	}

	if (localError)
	{
		if (error)
			*error = localError;
		return nil;
	}

	return result;
}


- (NSData *)toJSON
	{ return [self toJSONWithOptions:kJSONUseClassOptions error:nil]; }


- (NSData *)toJSONWithOptions:(JSONCoderOptions)options error:(NSError **)error
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


- (NSString *)toJSONStringWithOptions:(JSONCoderOptions)options error:(NSError **)error
	{ return [[NSString alloc] initWithData:[self toJSON] encoding:NSUTF8StringEncoding]; }


+ (instancetype)fromDictionary:(NSDictionary *)dict
	{ return [self fromDictionary:dict options:kJSONUseClassOptions error:nil]; }


+ (instancetype)fromDictionary:(NSDictionary *)dict options:(JSONCoderOptions)options error:(NSError **)error
{
	if (!dict)
		return nil;

	NSError *localError = nil;
	JSONCoder *result = [self new];

	NSDictionary <NSString *, JSONProperty *> *map = [self.class mapWithOptions:options];

	for (NSString *key in map)
	{
		JSONProperty* prop = map[key];
		if (prop)
			[prop fromValue:dict[key] withInstance:result options:options error:&localError];
		if (localError)
			break;
	}

	if (localError)
	{
		if (error)
			*error = localError;
		return nil;
	}

	return result;
}


+ (NSArray *)fromArrayOfDictionaries:(NSArray *)array options:(JSONCoderOptions)options error:(NSError **)error
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


+ (instancetype)fromData:(NSData *)data options:(JSONCoderOptions)options error:(NSError **)error
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


+ (instancetype)fromString:(NSString *)jsonString
	{ return [self fromString:jsonString options:kJSONUseClassOptions error:nil]; }


+ (instancetype)fromString:(NSString *)jsonString options:(JSONCoderOptions)options error:(NSError **)error
	{ return [self fromData:[jsonString dataUsingEncoding:NSUTF8StringEncoding] options:options error:error]; }


@end

