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

- (id)toObjectWithInstance:(JSONCoder*)coder options:(JSONCoderOptions)options error:(NSError **)error;
- (void)fromObject:(id)value withInstance:(JSONCoder*)coder options:(JSONCoderOptions)options error:(NSError **)error;
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
		fmt = [NSDateFormatter new];
		fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
		fmt.timeZone = [[NSTimeZone alloc] initWithName:@"UTC"];
		fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
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
			{
				_itemClass = [coderClass classForCollectionProperty:_name];
				if (!_itemClass)
					NSLog(@"JSONCoder: WARNING: possibly invalid collection property %@.%@", NSStringFromClass(coderClass), _name);
			}
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


- (id)toObjectWithInstance:(JSONCoder *)coder options:(JSONCoderOptions)options error:(NSError **)error
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


- (void)fromObject:(id)value withInstance:(JSONCoder*)coder options:(JSONCoderOptions)options error:(NSError **)error
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
			value = [ISO8601Formatter() dateFromString:value];
		else if (error)
			*error = [self errorTypeMismatch:@"date string"];
	}

	else if (_itemClass)
	{
		if ([value isKindOfClass:NSArray.class])
			value = [_itemClass arrayFromRawArray:value options:options error:error];
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
			for (int i = 0; i < propertyCount; i++)
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


- (NSDictionary *)toDictionary
	{ return [self toDictionaryWithOptions:kJSONUseClassOptions error:nil]; }


- (NSDictionary *)toDictionaryWithOptions:(JSONCoderOptions)options error:(NSError **)error;
{
	if (options == kJSONUseClassOptions)
		options = self.class.encoderOptions;
	NSError *localError = nil;

	NSDictionary <NSString *, JSONProperty *> *map = [self.class mapWithOptions:options];

	NSMutableDictionary *result = [NSMutableDictionary new];
	for (NSString *key in map)
	{
		id value = [map[key] toObjectWithInstance:self options:options error:&localError];
		if (localError)
			break;
		if (value)
			result[key] = value;
	}

	if (localError)
	{
		if (options & kJSONExceptions)
			[NSException raise:@"JSONCoder" format:@"%@", localError.localizedDescription];
		else if (error)
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
	if (error && *error)
		return nil;
	NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:error];
	if (error && *error)
	{
		if (options & kJSONExceptions)
			[NSException raise:@"JSONCoder" format:@"%@", (*error).localizedDescription];
		return nil;
	}
	return data;
}


+ (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description
	{ return [NSError errorWithDomain:@"JSONCoder" code:code userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:description, NSStringFromClass(self)]}]; }


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
		UNFINISHED
	}

	return result;
}


+ (NSArray *)arrayFromRawArray:(NSArray *)array options:(JSONCoderOptions)options error:(NSError **)error
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


@end

