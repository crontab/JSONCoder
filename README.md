# JSONCoder
Simple JSON model support for Objective C

Provides conversion of Objective-C objects to and from JSON, optionally with property name conversion to and from the "snake case" (underscore case).

How to use: derive your class from JSONCoder, declare properties you want to be present in JSON, then use the fromXXX family of class methods for instantiating objects from JSON data, or the toXXX family of methods for encoding your objects to JSON.

Only read-write properties are included in JSON encoding/decoding. To exclude a read-write property, mark its type with the `<Ignore>` protocol. Everything else, i.e. read-only properties, methods, constructors, etc. are ignored by the converter.

Data types allowed in encodable properties are:
	
- NSString
- NSNumber
- NSDate, optionally with `<DateOnly>` protocol; these are converted to and from ISO8601 time stamps
- Object types derived from JSONCoder
- Primitive scalar types such as int, BOOL, float
- Arrays of any of the above; the array item type can be specified by overriding the classForCollectionProperty method, though this is not required for NSString and NSNumber element types
- Dictionaries with the following element types: NSString, NSNumber, nested arrays and dictionaries of the same

All proprties are required to be present in JSON data when decoding, as well as they are required to be non-nil when encoding to JSON, unless a property is makred with the `<Optional>` protocol. Optional properties are not included in encoding if their value is nil. This does not apply to scalar types, which are always encoded.

NSNumber and the scalar types are all mutually convertible; an attempt to convert between any other types listed above results in error.

Scalar types are always included in conversions to JSON; marking them as optional (using the propertyIsOptional method, as there is no way of attaching the `<Optional>` protocol to these types) only affects conversion from JSON.

A property name can start with the dollar sign ($) in case of keyword or other naming conflicts. For example, a property named `description` or `class` can be disambiguated by declaring them as `$description` and `$class`. Such properties are mapped to JSON names without the `$` prefix.

Example class:

    @interface Person : JSONCoder
    @property (nonatomic) NSString *name;
    @property (nonatomic) NSString <Optional> *nickname;
    @property (nonatomic) NSDate <DateOnly>* dateOfBirth;
    @property (nonatomic) NSArray *preferredBands;
    @end

Then:

    Person *person = [Person new];
    person.name = @"Jimi Hendrix";
    person.dateOfBirth = [NSDate dateFromJimiHendrixBirthdate]; // okay, you get the idea
    person.preferredBands = @[@"B.B. King", @"The Beatles"];
    NSLog(@"%@", person.toJSONString);

Should print:

    {
      "name" : "Jimi Hendrix",
      "date_of_birth" : "1942-27-11",
      "preferred_bands" : [
        "B.B. King",
        "The Beatles"
      ]
    }

(Pretty JSON printing is enabled for DEBUG builds only)
