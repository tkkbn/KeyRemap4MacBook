#import "NotificationKeys.h"
#import "PreferencesKeys.h"
#import "PreferencesManager.h"
#include <sys/time.h>

@implementation PreferencesManager

// ----------------------------------------
+ (void) initialize
{
  NSDictionary* dict = @ { kIsQuitByHand : @NO,
                           kIsStatusBarEnabled : @YES,
                           kIsShowSettingNameInStatusBar : @NO,
                           kConfigListSelectedIndex : @0,
                           kCheckForUpdates : @1,
                           kIsStatusWindowEnabled : @YES,
                           kIsStatusWindowShowStickyModifier : @NO,
                           kIsStatusWindowShowPointingButtonLock : @YES,
                           kStatusWindowTheme : @0, // White
                           kStatusWindowOpacity : @80,
                           kStatusWindowFontSize : @0, // Small
                           kStatusWindowPosition : @3, // Bottom left
  };
  [[NSUserDefaults standardUserDefaults] registerDefaults:dict];
}

// ----------------------------------------
+ (void) setIsQuitByHand:(NSNumber*)newvalue
{
  [[NSUserDefaults standardUserDefaults] setObject:newvalue forKey:kIsQuitByHand];

  int RETRY = 5;
  for (int i = 0; i < RETRY; ++i) {
    // Call "synchronize" in order to ensure saving changes.
    if ([[NSUserDefaults standardUserDefaults] synchronize]) {
      break;
    }
    [NSThread sleepForTimeInterval:0.1];
  }
}

// ----------------------------------------
- (void) addToDefault:(NSXMLElement*)element
{
  for (NSXMLElement* e in [element elementsForName : @"identifier"]) {
    NSXMLNode* attr_default = [e attributeForName:@"default"];
    if (! attr_default) continue;

    [default_ setObject:[NSNumber numberWithInt:[[attr_default stringValue] intValue]] forKey:[e stringValue]];
  }

  for (NSXMLElement* e in [element elementsForName : @"list"]) {
    [self addToDefault:e];
  }
  for (NSXMLElement* e in [element elementsForName : @"item"]) {
    [self addToDefault:e];
  }
}

- (void) setDefault
{
  NSURL* xmlurl = [[NSBundle mainBundle] URLForResource:@"number" withExtension:@"xml"];
  NSXMLDocument* xmldocument = [[[NSXMLDocument alloc] initWithContentsOfURL:xmlurl options:0 error:NULL] autorelease];
  if (xmldocument) {
    [self addToDefault:[xmldocument rootElement]];
  }
}

// ----------------------------------------
- (id) init
{
  self = [super init];

  if (self) {
    default_ = [NSMutableDictionary new];
    [self setDefault];

    essential_configuration_identifiers_ = [[NSArray arrayWithObjects:
#include "../../../bridge/output/include.bridge_essential_configuration_identifiers.m"
                                            ] retain];
  }

  return self;
}

- (void) dealloc
{
  [default_ release];
  [essential_configuration_identifiers_ release];

  [super dealloc];
}

- (void) load
{
  // ------------------------------------------------------------
  // initialize
  if (! [self configlist_selectedIdentifier]) {
    [self configlist_select:0];

    if (! [self configlist_selectedIdentifier]) {
      NSLog(@"initialize configlist");

      // add new item
      [self configlist_append];
      [self configlist_setName:0 name:@"Default"];
      [self configlist_select:0];
    }
  }

  // ------------------------------------------------------------
  // scan config_* and detech notsave.*
  for (NSDictionary* dict in [self configlist_getConfigList]) {
    if (! dict) continue;

    NSString* identifier = [dict objectForKey:@"identify"];
    if (! identifier) continue;

    NSDictionary* d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:identifier];
    if (! d) continue;

    NSMutableDictionary* md = [NSMutableDictionary dictionaryWithDictionary:d];

    for (NSString* name in [md allKeys]) {
      if ([name hasPrefix:@"notsave."]) {
        [md removeObjectForKey:name];
      }
    }

    [[NSUserDefaults standardUserDefaults] setObject:md forKey:identifier];
  }
}

// ----------------------------------------------------------------------
- (int) value:(NSString*)name
{
  // user setting
  NSString* identifier = [self configlist_selectedIdentifier];
  if (identifier) {
    NSDictionary* dict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:identifier];
    if (dict) {
      NSNumber* number = [dict objectForKey:name];
      if (number) {
        return [number intValue];
      }
    }
  }

  return [self defaultValue:name];
}

- (int) defaultValue:(NSString*)name
{
  NSNumber* number = [default_ objectForKey:name];
  if (number) {
    return [number intValue];
  } else {
    return 0;
  }
}

- (void) setValueForName:(int)newval forName:(NSString*)name
{
  NSString* identifier = [self configlist_selectedIdentifier];
  if (! identifier) {
    NSLog(@"[ERROR] %s identifier == nil", __FUNCTION__);
    return;
  }

  NSMutableDictionary* md = nil;

  NSDictionary* dict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:identifier];
  if (dict) {
    md = [NSMutableDictionary dictionaryWithDictionary:dict];
  } else {
    md = [[NSMutableDictionary new] autorelease];
  }
  if (! md) {
    NSLog(@"[ERROR] %s md == nil", __FUNCTION__);
    return;
  }

  int defaultvalue = 0;
  NSNumber* defaultnumber = [default_ objectForKey:name];
  if (defaultnumber) {
    defaultvalue = [defaultnumber intValue];
  }

  if (newval == defaultvalue) {
    [md removeObjectForKey:name];
  } else {
    [md setObject:[NSNumber numberWithInt:newval] forKey:name];
  }

  [[NSUserDefaults standardUserDefaults] setObject:md forKey:identifier];
  // [[NSUserDefaults standardUserDefaults] synchronize];

  [[NSNotificationCenter defaultCenter] postNotificationName:kPreferencesChangedNotification object:nil];
}

- (void) clearNotSave
{
  // user setting
  NSString* identifier = [self configlist_selectedIdentifier];
  if (identifier) {
    NSDictionary* dict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:identifier];
    if (dict) {
      NSMutableDictionary* md = [NSMutableDictionary dictionaryWithDictionary:dict];

      for (NSString* key in dict) {
        if ([key hasPrefix:@"notsave."]) {
          [md removeObjectForKey:key];
        }
      }

      [[NSUserDefaults standardUserDefaults] setObject:md forKey:identifier];

      [[NSNotificationCenter defaultCenter] postNotificationName:kPreferencesChangedNotification object:nil];
    }
  }
}

- (NSArray*) essential_config
{
  NSMutableArray* a = [[NSMutableArray new] autorelease];

  if (essential_configuration_identifiers_) {
    for (NSString* identifier in essential_configuration_identifiers_) {
      [a addObject:[NSNumber numberWithInt:[self value:identifier]]];
    }
  }

  return a;
}

- (NSDictionary*) changed
{
  NSString* identifier = [self configlist_selectedIdentifier];
  if (! identifier) return nil;

  return [[NSUserDefaults standardUserDefaults] dictionaryForKey:identifier];
}

// ----------------------------------------------------------------------
- (NSInteger) configlist_selectedIndex
{
  return [[NSUserDefaults standardUserDefaults] integerForKey:@"selectedIndex"];
}

- (NSString*) configlist_selectedName
{
  return [self configlist_name:[self configlist_selectedIndex]];
}

- (NSString*) configlist_selectedIdentifier
{
  return [self configlist_identifier:[self configlist_selectedIndex]];
}

- (NSArray*) configlist_getConfigList
{
  return [[NSUserDefaults standardUserDefaults] arrayForKey:@"configList"];
}

- (NSUInteger) configlist_count
{
  NSArray* a = [self configlist_getConfigList];
  if (! a) return 0;
  return [a count];
}

- (NSDictionary*) configlist_dictionary:(NSInteger)rowIndex
{
  NSArray* list = [self configlist_getConfigList];
  if (! list) return nil;

  if (rowIndex < 0 || (NSUInteger)(rowIndex) >= [list count]) return nil;

  return [list objectAtIndex:rowIndex];
}

- (NSString*) configlist_name:(NSInteger)rowIndex
{
  NSDictionary* dict = [self configlist_dictionary:rowIndex];
  if (! dict) return nil;
  return [dict objectForKey:@"name"];
}

- (NSString*) configlist_identifier:(NSInteger)rowIndex
{
  NSDictionary* dict = [self configlist_dictionary:rowIndex];
  if (! dict) return nil;
  return [dict objectForKey:@"identify"];
}

- (void) configlist_select:(NSInteger)newindex
{
  if (newindex < 0) return;
  if (newindex == [self configlist_selectedIndex]) return;

  NSArray* list = [self configlist_getConfigList];
  if (! list) return;
  if ((NSUInteger)(newindex) >= [list count]) return;

  NSUserDefaults* userdefaults = [NSUserDefaults standardUserDefaults];
  [userdefaults setInteger:newindex forKey:@"selectedIndex"];

  [[NSNotificationCenter defaultCenter] postNotificationName:kConfigListChangedNotification object:nil];
  [[NSNotificationCenter defaultCenter] postNotificationName:kPreferencesChangedNotification object:nil];
}

- (void) configlist_setName:(NSInteger)rowIndex name:(NSString*)name
{
  if ([name length] == 0) return;

  NSArray* a = [[NSUserDefaults standardUserDefaults] arrayForKey:@"configList"];
  if (! a) return;
  if (rowIndex < 0 || (NSUInteger)(rowIndex) >= [a count]) return;

  NSDictionary* d = [a objectAtIndex:rowIndex];
  if (! d) return;

  NSMutableDictionary* md = [NSMutableDictionary dictionaryWithDictionary:d];
  if (! md) return;
  [md setObject:name forKey:@"name"];

  NSMutableArray* ma = [NSMutableArray arrayWithArray:a];
  if (! ma) return;
  [ma replaceObjectAtIndex:rowIndex withObject:md];

  [[NSUserDefaults standardUserDefaults] setObject:ma forKey:@"configList"];

  [[NSNotificationCenter defaultCenter] postNotificationName:kConfigListChangedNotification object:nil];
}

- (void) configlist_append
{
  NSMutableArray* ma = nil;

  NSArray* a = [[NSUserDefaults standardUserDefaults] arrayForKey:@"configList"];
  if (a) {
    ma = [NSMutableArray arrayWithArray:a];
  } else {
    ma = [[NSMutableArray new] autorelease];
  }
  if (! ma) return;

  struct timeval tm;
  gettimeofday(&tm, NULL);
  NSString* identifier = [NSString stringWithFormat:@"config_%d_%d", (int)(tm.tv_sec), (int)(tm.tv_usec)];

  NSMutableDictionary* md = [NSMutableDictionary dictionaryWithCapacity:0];
  [md setObject:@"NewItem" forKey:@"name"];
  [md setObject:identifier forKey:@"identify"];

  [ma addObject:md];

  [[NSUserDefaults standardUserDefaults] setObject:ma forKey:@"configList"];

  [[NSNotificationCenter defaultCenter] postNotificationName:kConfigListChangedNotification object:nil];
}

- (void) configlist_delete:(NSInteger)rowIndex
{
  NSArray* a = [[NSUserDefaults standardUserDefaults] arrayForKey:@"configList"];
  if (! a) return;

  if (rowIndex < 0 || (NSUInteger)(rowIndex) >= [a count]) return;

  NSInteger selectedIndex = [self configlist_selectedIndex];
  if (rowIndex == selectedIndex) return;

  NSMutableArray* ma = [NSMutableArray arrayWithArray:a];
  if (! ma) return;

  [ma removeObjectAtIndex:(NSUInteger)(rowIndex)];

  [[NSUserDefaults standardUserDefaults] setObject:ma forKey:@"configList"];

  // When Item2 is deleted in the following condition,
  // we need to decrease selected index 2->1.
  //
  // - Item1
  // - Item2
  // - Item3 [selected]
  //
  if (rowIndex < selectedIndex) {
    [self configlist_select:(selectedIndex - 1)];
  }

  [[NSNotificationCenter defaultCenter] postNotificationName:kConfigListChangedNotification object:nil];
}

// ----------------------------------------------------------------------
- (NSInteger) checkForUpdatesMode
{
  return [[NSUserDefaults standardUserDefaults] integerForKey:kCheckForUpdates];
}

// ----------------------------------------------------------------------
- (IBAction) sendConfigListChangedNotification:(id)sender
{
  [[NSNotificationCenter defaultCenter] postNotificationName:kConfigListChangedNotification object:nil];
}

@end
