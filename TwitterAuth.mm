//
//  OAuth.m
//
//  Created by Jaanus Kase on 12.01.10.
//  Copyright 2010. All rights reserved.
//

#import "NSData+Base64.h"
#import "TwitterAuth.h"
#import "OAuthCore.h"
#import "KeychainUtils.h"
#import <CommonCrypto/CommonHMAC.h>

@interface NSString (TwitterAuthAdditions)

- (NSString *)encodedURLString;
- (NSString *)encodedURLParameterString;
- (NSString *)decodedURLString;
- (NSString *)removeQuotes;

@end

@implementation NSString (TwitterAuthAdditions)

- (NSString *)encodedURLString {
	NSString* result = (NSString *)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                           (CFStringRef)self,
                                                                           NULL,                   // characters to leave unescaped (NULL = all escaped sequences are replaced)
                                                                           CFSTR("?=&+"),          // legal URL characters to be escaped (NULL = all legal characters are replaced)
                                                                           kCFStringEncodingUTF8); // encoding
	return [result autorelease];
}

- (NSString *)encodedURLParameterString {
    	NSString* result = (NSString *)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                           (CFStringRef)self,
                                                                           NULL,
                                                                           CFSTR(":/=,!$&'()*;[]@#?"),
                                                                           kCFStringEncodingUTF8);
	return [result autorelease];
}

- (NSString *)decodedURLString {
	NSString *result = (NSString*)CFURLCreateStringByReplacingPercentEscapesUsingEncoding(kCFAllocatorDefault,
																						  (CFStringRef)self,
																						  CFSTR(""),
																						  kCFStringEncodingUTF8);
	
	return [result autorelease];
	
}

-(NSString *)removeQuotes
{
	NSUInteger length = [self length];
	NSString *ret = self;
	if ([self characterAtIndex:0] == '"') {
		ret = [ret substringFromIndex:1];
	}
	if ([self characterAtIndex:length - 1] == '"') {
		ret = [ret substringToIndex:length - 2];
	}
	
	return ret;
}

@end

static NSString* CONSUMER_KEY = @"";
static NSString* CONSUMER_SECRET  = @"";

@implementation TwitterAuth

@synthesize oauth_consumer_key;
@synthesize oauth_consumer_secret;
@synthesize oauth_token;
@synthesize oauth_token_secret;
@synthesize oauth_token_authorized;
@synthesize user_id;
@synthesize screen_name;

#pragma mark -
#pragma mark Init and dealloc

/**
 * Initialize an OAuth context object with a given consumer key and secret. These are immutable as you
 * always work in the context of one app.
 */
- (id) init
{
	if (self = [super init]) {
		self.oauth_consumer_key = CONSUMER_KEY;
		self.oauth_consumer_secret = CONSUMER_SECRET;
		srandom(time(NULL)); // seed the random number generator, used for generating nonces
		self.user_id = @"";
		self.screen_name = @"";

		NSError* error;
		self.oauth_token = [KeychainUtils getPasswordForUsername:@"OAuthToken" andServiceName:@"LockInfoTwitter" error:&error];
		self.oauth_token_secret = [KeychainUtils getPasswordForUsername:@"OAuthTokenSecret" andServiceName:@"LockInfoTwitter" error:&error];
		self.oauth_token_authorized = (self.oauth_token && self.oauth_token_secret);
		if (!self.oauth_token_authorized)
		{
			self.oauth_token = @"";
			self.oauth_token_secret = @"";
		}
	}
	
	return self;
}

#pragma mark -
#pragma mark KVC

/**
 * We specify a set of keys that are known to be returned from OAuth responses, but that we are not interested in.
 * In case of any other keys, we log them since they may indicate changes in API that we are not prepared
 * to deal with, but we continue nevertheless.
 * This is only relevant for the Twitter request/authorize convenience methods that do HTTP calls and parse responses.
 */
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {
	// KVC: define a set of keys that are known but that we are not interested in. Just ignore them.
	if ([[NSSet setWithObjects:
		  @"oauth_callback_confirmed",
		  nil] containsObject:key]) {
		
	// ... but if we got a new key that is not known, log it.
	} else {
		NSLog(@"Got unknown key from provider response. Key: \"%@\", value: \"%@\"", key, value);
	}
}

#pragma mark -
#pragma mark Public methods

/**
 * You will be calling this most of the time in your app, after the bootstrapping (authorization) is complete. You pass it
 * a set of information about your HTTP request (HTTP method, URL and any extra parameters), and you get back a header value
 * that you can put in the "Authorization" header. The header will also include a signature.
 *
 * "params" should be NSDictionary with any extra material to add in the signature. If you are doing a POST request,
 * this needs to exactly match what you will be POSTing. If you are GETting, this should include the parameters in your
 * QUERY_STRING; if there are none, this is nil.
 */
- (NSString *)signClearText:(NSString *)text withSecret:(NSString *)secret 
{
	NSData *secretData = [secret dataUsingEncoding:NSUTF8StringEncoding];
	NSData *clearTextData = [text dataUsingEncoding:NSUTF8StringEncoding];
	unsigned char result[20];
	CCHmac(kCCHmacAlgSHA1, [secretData bytes], [secretData length], [clearTextData bytes], [clearTextData length], result);
	NSData *theData = [NSData dataWithBytes:result length:sizeof(result)];
	return theData.base64EncodedString;
}

/**
 * An extra method that lets the caller override the token secret used to sign the header. This is determined automatically
 * most of the time based on if our token has been authorized or not and you can use the method without the extra parameter,
 * but we need to override it for our /authorize request because our token has not been authorized by this point,
 * yet we still need to sign our /authorize request with both consumer and token secrets.
 */
- (NSString *) OAuthorizationHeader:(NSURL*) url method:(NSString *)method body:(NSData*) body
{
	return OAuthorizationHeader(url, method, body, CONSUMER_KEY, CONSUMER_SECRET, self.oauth_token, self.oauth_token_secret);
}

/**
 * When the user invokes the "sign out" function in the app, forget the current OAuth context.
 * We still remember consumer key and secret
 * since those are for an app and don't change, but we forget everything else.
 */
- (void) forget {
	self.oauth_token_authorized = NO;
	self.oauth_token = @"";
	self.oauth_token_secret = @"";
	self.user_id = @"";
	self.screen_name = @"";
}

- (NSString *) description {
	return [NSString stringWithFormat:@"OAuth context object with consumer key \"%@\", token \"%@\". Authorized: %@",
			self.oauth_consumer_key, self.oauth_token, self.oauth_token_authorized ? @"YES" : @"NO"]; 
}

#pragma mark -
#pragma mark Twitter convenience methods

-(BOOL) authorized
{
	return self.oauth_token_authorized;
}

/**
 * Given a request URL, request an unauthorized OAuth token from that URL. This starts
 * the process of getting permission from user. This is done synchronously. If you want
 * threading, do your own.
 *
 * This is the request/response specified in OAuth Core 1.0A section 6.1.
 */
- (BOOL) requestTwitterToken {

	NSString *url = @"https://api.twitter.com/oauth/request_token";
	
	// Invalidate the previous request token, whether it was authorized or not.
	self.oauth_token_authorized = NO; // We are invalidating whatever token we had before.
	self.oauth_token = @"";
	self.oauth_token_secret = @"";
	
	// Calculate the header.
	NSString *oauth_header = OAuthorizationHeader([NSURL URLWithString:url], @"GET", nil, CONSUMER_KEY, CONSUMER_SECRET, @"", @"");
	
	// Synchronously perform the HTTP request.
	NSMutableURLRequest* request = [[[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]] autorelease];
	request.HTTPMethod = @"GET";
	[request setValue:oauth_header forHTTPHeaderField:@"Authorization"];

	NSError* error;
        NSHTTPURLResponse* response;
        NSData* data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
	
	NSString* responseString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
//	NSLog(@"LI:Twitter: Token response: %@, %@", responseString, oauth_header);
	NSArray *responseBodyComponents = [responseString componentsSeparatedByString:@"&"];

	// For a successful response, break the response down into pieces and set the properties
	// with KVC. If there's a response for which there is no local property or ivar, this
	// may end up with setValue:forUndefinedKey:.
	for (NSString *component in responseBodyComponents) 
	{
		NSArray *subComponents = [component componentsSeparatedByString:@"="];
		if (subComponents.count == 2)
			[self setValue:[subComponents objectAtIndex:1] forKey:[subComponents objectAtIndex:0]];			
	}

	return (self.oauth_token.length > 0);
}


/**
 * By this point, we have a token, and we have a verifier such as PIN from the user. We combine
 * these together and exchange the unauthorized token for a new, authorized one.
 *
 * This is the request/response specified in OAuth Core 1.0A section 6.3.
 */
- (BOOL) authorizeTwitterToken
{
	NSString *url = @"https://api.twitter.com/oauth/access_token";
	
	NSString *oauth_header = OAuthorizationHeader([NSURL URLWithString:url], @"GET", nil, CONSUMER_KEY, CONSUMER_SECRET, self.oauth_token, self.oauth_token_secret);

	NSMutableURLRequest* request = [[[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:url]] autorelease];
	request.HTTPMethod = @"GET";
	[request setValue:oauth_header forHTTPHeaderField:@"Authorization"];

	self.oauth_token = @"";
	self.oauth_token_secret = @"";

	NSError* error;
        NSHTTPURLResponse* response;
        NSData* data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
	
	NSString* responseString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
	NSArray *responseBodyComponents = [responseString componentsSeparatedByString:@"&"];

	// For a successful response, break the response down into pieces and set the properties
	// with KVC. If there's a response for which there is no local property or ivar, this
	// may end up with setValue:forUndefinedKey:.
	for (NSString *component in responseBodyComponents) 
	{
		NSArray *subComponents = [component componentsSeparatedByString:@"="];
		if (subComponents.count == 2)
			[self setValue:[subComponents objectAtIndex:1] forKey:[subComponents objectAtIndex:0]];			
	}

	if (self.oauth_token.length > 0)
	{
		self.oauth_token_authorized = YES;
		[KeychainUtils storeUsername:@"OAuthToken" andPassword:self.oauth_token forServiceName:@"LockInfoTwitter" updateExisting:YES error:&error];
		[KeychainUtils storeUsername:@"OAuthTokenSecret" andPassword:self.oauth_token_secret forServiceName:@"LockInfoTwitter" updateExisting:YES error:&error];

		return YES;
	}

	return NO;
}

#pragma mark -
#pragma mark Internal utilities for crypto, signing.

// http://stackoverflow.com/questions/1353771/trying-to-write-nsstring-sha1-function-but-its-returning-null
- (NSString *)sha1:(NSString *)str {
	const char *cStr = [str UTF8String];
	unsigned char result[CC_SHA1_DIGEST_LENGTH];
	CC_SHA1(cStr, strlen(cStr), result);
	NSMutableString *out = [NSMutableString stringWithCapacity:20];
	for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
		[out appendFormat:@"%02X", result[i]];
	}
	return [out lowercaseString];
}


@end
