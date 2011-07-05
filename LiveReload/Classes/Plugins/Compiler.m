
#import "Compiler.h"
#import "Plugin.h"

#import "RegexKitLite.h"
#import "NSTask+OneLineTasksWithOutput.h"
#import "NSArray+Substitutions.h"

@interface NSString (SmartRegexpCaptures)

- (NSDictionary *)dictionaryByMatchingWithRegexp:(NSString *)regexp withSmartSubstitutions:(NSDictionary *)substitutions options:(RKLRegexOptions)options;

@end

@implementation NSString (SmartRegexpCaptures)

- (NSDictionary *)dictionaryByMatchingWithRegexp:(NSString *)regexp withSmartSubstitutions:(NSDictionary *)substitutions options:(RKLRegexOptions)options {

    int captureIndexes[100];
    NSString *captureNames[100];
    NSUInteger captureCount = 0;

    while (1) {
        NSRange minRange = NSMakeRange(NSNotFound, 0);
        NSString *minKey = nil;

        for (NSString *key in substitutions) {
            NSRange range = [regexp rangeOfString:[NSString stringWithFormat:@"((%@))", key]];
            if (range.length > 0) {
                if (minRange.location == NSNotFound || range.location < minRange.location) {
                    minRange = range;
                    minKey = key;
                }
            }
        }

        if (minRange.length == 0) {
            break;
        } else {
            NSString *value = [substitutions objectForKey:minKey];
            value = [NSString stringWithFormat:@"(%@)", value];
            regexp = [regexp stringByReplacingCharactersInRange:minRange withString:value];
            captureIndexes[captureCount] = captureCount + 1;
            captureNames[captureCount] = minKey;
            ++captureCount;
        }
    }

    return [self dictionaryByMatchingRegex:regexp options:options range:NSMakeRange(0, [self length]) error:nil withKeys:captureNames forCaptures:captureIndexes count:captureCount];
}

@end


@implementation Compiler

@synthesize extensions=_extensions;
@synthesize destinationExtension=_destinationExtension;


#pragma mark - init/dealloc

- (id)initWithDictionary:(NSDictionary *)info plugin:(Plugin *)plugin {
    self = [super init];
    if (self) {
        _plugin = plugin;
        _name = [[info objectForKey:@"Name"] copy];
        _commandLine = [[info objectForKey:@"CommandLine"] copy];
        _extensions = [[info objectForKey:@"Extensions"] copy];
        _destinationExtension = [[info objectForKey:@"DestinationExtension"] copy];
        _errorFormat = [[info objectForKey:@"ErrorFormat"] copy];
    }
    return self;
}

- (void)dealloc {
    [_commandLine release], _commandLine = nil;
    _plugin = nil;
    [super dealloc];
}


#pragma mark - Paths

- (NSString *)derivedNameForFile:(NSString *)path {
    return [[[path lastPathComponent] stringByDeletingPathExtension] stringByAppendingPathExtension:self.destinationExtension];
}


#pragma mark - Compilation

- (void)compile:(NSString *)sourcePath into:(NSString *)destinationPath {
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                          [[NSBundle mainBundle] pathForResource:@"node" ofType:nil], @"$(node)",
                          _plugin.path, @"$(plugin)",
                          sourcePath, @"$(src_file)",
                          destinationPath, @"$(dst_file)",
                          [destinationPath stringByDeletingLastPathComponent], @"$(dst_dir)",
                          nil];

    NSArray *arguments = [_commandLine arrayBySubstitutingValuesFromDictionary:info];
    NSLog(@"Running compiler: %@", [arguments description]);

    NSString *command = [arguments objectAtIndex:0];
    arguments = [arguments subarrayWithRange:NSMakeRange(1, [arguments count] - 1)];

    NSError *error = nil;
    NSString *output = [NSTask stringByLaunchingPath:command
                                       withArguments:arguments
                                               error:&error];

    if (error) {
        NSLog(@"Error: %@", [error description]);
        if ([error code] == kNSTaskProcessOutputError) {
            NSDictionary *substitutions = [NSDictionary dictionaryWithObjectsAndKeys:
                                           @"[^\\n]+?", @"file",
                                           @"\\d+", @"line",
                                           @"[^\\n]+?", @"message",
                                           nil];

            NSDictionary *data = [output dictionaryByMatchingWithRegexp:_errorFormat withSmartSubstitutions:substitutions options:0];

            NSString *file = [data objectForKey:@"file"];
            NSString *line = [data objectForKey:@"line"];
            NSString *message = [[data objectForKey:@"message"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

            if (!file) {
                file = sourcePath;
            }
            if (!message) {
                if ([output length] < 200) {
                    message = output;
                } else {
                    message = [output substringWithRange:[output rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, 200)]];
                }
                if ([message length] == 0) {
                    message = @"Compilation failed with an empty output.";
                }
            }

            NSString *fileName = [file lastPathComponent];
            NSString *dir = [[file stringByDeletingLastPathComponent] stringByAbbreviatingWithTildeInPath];

            NSAlert *alert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"%@ error", _name]
                                             defaultButton:@"Edit in TextMate"
                                           alternateButton:@"Ignore"
                                               otherButton:nil
                                 informativeTextWithFormat:@"%@\n\nLine: %@\n\nFile: %@\n\nFolder: %@", message, (line ? line : @"?"), fileName, dir];
            if ([alert runModal] == NSAlertDefaultReturn) {
                NSString *url = [NSString stringWithFormat:@"txmt://open/?url=file://%@&line=%@", [file stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding], line];
                [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
            }
        }
    } else {
        NSLog(@"Output: [[[%@]]]", output);
    }
}

@end
